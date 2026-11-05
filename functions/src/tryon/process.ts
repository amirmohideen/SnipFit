import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { onTaskDispatched } from 'firebase-functions/v2/tasks';

import { aiOps, COVERAGE_SERVICE_TOKEN, COVERAGE_SERVICE_URL, GEMINI_IMAGE_MODEL, TRYON_MODEL, VERTEX_LOCATION } from '../config.js';
import type { Bucket } from '../credits/ledger.js';
import { commit, release } from '../credits/ledger.js';
import { bucket, db, ledgerEntry, readLedger, uidHash, writeLedger } from '../lib/admin.js';
import { embedXmp } from '../provenance/xmp.js';
import { analyzeImages, measureCoverage } from '../safety/google.js';
import type { BlockReason } from '../safety/verdicts.js';
import { judgeCoverage, judgeImage } from '../safety/verdicts.js';
import type { Mode, TryOnProvider } from './providers.js';
import { GeminiImageEdit, ProviderError, VertexVirtualTryOn } from './providers.js';

class Blocked extends Error {
  constructor(readonly reason: BlockReason) {
    super(reason);
  }
}

const MAX_ATTEMPTS = 3;

async function setStatus(requestId: string, status: string, extra: Record<string, unknown> = {}) {
  await db.collection('tryonRequests').doc(requestId).set({ status, updatedAt: Timestamp.now(), ...extra }, { merge: true });
}

async function deleteInputs(uid: string, requestId: string) {
  await bucket()
    .deleteFiles({ prefix: `tryon-inputs/${uid}/${requestId}/` })
    .catch((e) => console.warn('input delete failed; the sweep will retry', (e as Error).message));
}

/** Settles the reserved credit: commit on success, release (refund) otherwise. */
async function settle(uid: string, requestId: string, bucketName: Bucket, success: boolean, reservedAt: Date) {
  const userRef = db.collection('users').doc(uid);
  await db.runTransaction(async (tx) => {
    const req = await tx.get(db.collection('tryonRequests').doc(requestId));
    if (req.get('settled') === true) return;
    const snap = await tx.get(userRef);
    const state = readLedger(snap.data());
    const next = success ? commit(state, bucketName) : release(state, bucketName, reservedAt);
    tx.set(userRef, { ...writeLedger(next), updatedAt: Timestamp.now() }, { merge: true });
    ledgerEntry(tx, uid, { type: success ? 'commit' : 'release', amount: 1, bucket: bucketName, refId: requestId });
    tx.set(req.ref, { settled: true }, { merge: true });
  });
}

/** Repeated blocked requests suspend AI try-on for a week. */
async function recordBlock(uid: string, limit: number) {
  const ref = db.collection('users').doc(uid);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const now = Date.now();
    const windowStart = (snap.get('blocks.windowStart') as Timestamp | undefined)?.toMillis() ?? 0;
    const inWindow = now - windowStart < 86400_000;
    const count = (inWindow ? Number(snap.get('blocks.count') ?? 0) : 0) + 1;
    const update: Record<string, unknown> = {
      blocks: { count, windowStart: inWindow ? snap.get('blocks.windowStart') : Timestamp.fromMillis(now) },
    };
    if (count >= limit) update.suspendedUntil = Timestamp.fromMillis(now + 7 * 86400_000);
    tx.set(ref, update, { merge: true });
  });
}

async function notifyReady(uid: string, requestId: string) {
  const devices = await db.collection('users').doc(uid).collection('devices').get();
  const tokens = devices.docs.map((d) => d.id);
  if (tokens.length === 0) return;
  const res = await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title: 'Your AI look is ready', body: 'Tap to see it.' },
    data: { requestId },
    android: { notification: { channelId: 'tryon_ready' } },
  });
  // Drop tokens that are no longer valid.
  await Promise.all(
    res.responses.map((r, i) =>
      !r.success && r.error?.code === 'messaging/registration-token-not-registered' ? devices.docs[i].ref.delete() : null,
    ),
  );
}

function providerFor(mode: Mode, hijabProvider: string): TryOnProvider {
  const project = process.env.GCLOUD_PROJECT ?? process.env.GCP_PROJECT ?? '';
  if (mode === 'hijab' && hijabProvider === 'gemini') {
    return new GeminiImageEdit(project, VERTEX_LOCATION.value(), GEMINI_IMAGE_MODEL.value());
  }
  return new VertexVirtualTryOn(project, VERTEX_LOCATION.value(), TRYON_MODEL.value());
}

/**
 * Runs one try-on. Rate-limited below Vertex AI's default quota of about
 * 50 requests per minute. Logs never contain images or raw user IDs.
 */
export const processTryOn = onTaskDispatched<{ requestId: string }>(
  {
    retryConfig: { maxAttempts: MAX_ATTEMPTS, minBackoffSeconds: 20 },
    rateLimits: { maxConcurrentDispatches: 20, maxDispatchesPerSecond: 0.75 },
    timeoutSeconds: 540,
    memory: '1GiB',
    secrets: [COVERAGE_SERVICE_TOKEN],
  },
  async (req) => {
    const { requestId } = req.data;
    const ref = db.collection('tryonRequests').doc(requestId);
    const snap = await ref.get();
    if (!snap.exists) return;
    const r = snap.data()!;
    if (!['queued', 'checking', 'generating'].includes(r.status)) return; // already done
    const uid = r.uid as string;
    const mode = r.mode as Mode;
    const bucketName = r.bucket as Bucket;
    const reservedAt = (r.createdAt as Timestamp).toDate();
    const ops = await aiOps();
    const log = { requestId, user: uidHash(uid) };
    let generated = false;

    try {
      await setStatus(requestId, 'checking');
      const folder = `tryon-inputs/${uid}/${requestId}`;
      const [[person], [garment]] = await Promise.all([
        bucket().file(`${folder}/person.jpg`).download(),
        bucket().file(`${folder}/garment.png`).download(),
      ]);

      // 1. Inputs: SafeSearch + no swimwear, underwear or lingerie.
      const [personCheck, garmentCheck] = await analyzeImages([person, garment]);
      for (const v of [judgeImage(personCheck), judgeImage(garmentCheck)]) {
        if (!v.ok) throw new Blocked(v.reason);
      }

      // 2. Generate with fixed server-side instructions.
      await setStatus(requestId, 'generating');
      const output = await providerFor(mode, ops.hijabProvider).generate({
        person,
        personMime: 'image/jpeg',
        garment,
        garmentMime: 'image/png',
        mode,
        samples: Number(r.samples ?? 1),
      });
      generated = output.images.length > 0;
      if (output.images.length === 0) throw new Blocked('model_filtered');

      // 3. Outputs: SafeSearch, then the coverage check (never more skin).
      const outChecks = await analyzeImages(output.images);
      for (const c of outChecks) {
        const v = judgeImage(c);
        if (!v.ok) throw new Blocked(v.reason);
      }
      const coverageUrl = COVERAGE_SERVICE_URL.value();
      if (coverageUrl) {
        const cov = await measureCoverage(coverageUrl, COVERAGE_SERVICE_TOKEN.value(), person, output.images);
        for (const after of cov.after) {
          const v = judgeCoverage(cov.before, after);
          if (!v.ok) throw new Blocked('coverage');
        }
      } else if (ops.coverageRequired) {
        throw new Error('coverage service not configured');
      }

      // 4. Label (machine-readable provenance) and deliver.
      await setStatus(requestId, 'finishing', { provider: output.provider });
      const resultPaths: string[] = [];
      for (let i = 0; i < output.images.length; i++) {
        const path = `tryon-results/${uid}/${requestId}/result_${i}.png`;
        await bucket()
          .file(path)
          .save(embedXmp(output.images[i]), { contentType: 'image/png', resumable: false, metadata: { cacheControl: 'private, max-age=0' } });
        resultPaths.push(path);
      }
      await settle(uid, requestId, bucketName, true, reservedAt);
      await setStatus(requestId, 'succeeded', { resultPaths, completedAt: Timestamp.now() });
      await deleteInputs(uid, requestId);
      await notifyReady(uid, requestId).catch((e) => console.warn('notify failed', (e as Error).message));
      console.info('tryon succeeded', { ...log, provider: output.provider, images: output.images.length });
    } catch (e) {
      if (e instanceof ProviderError && e.retryable && req.retryCount + 1 < MAX_ATTEMPTS) {
        await setStatus(requestId, 'queued', { lastError: e.code });
        console.warn('tryon retrying', { ...log, code: e.code });
        throw e; // Cloud Tasks retries with backoff.
      }
      const blocked = e instanceof Blocked;
      await settle(uid, requestId, bucketName, false, reservedAt);
      await setStatus(requestId, blocked ? 'blocked' : 'failed', {
        error: { code: blocked ? (e as Blocked).reason : e instanceof ProviderError ? e.code : 'internal' },
        completedAt: Timestamp.now(),
      });
      await deleteInputs(uid, requestId);
      // Nothing was generated, so give back the spend estimate.
      if (!generated) await db
        .collection('aiSpendDays')
        .doc(reservedAt.toISOString().slice(0, 10))
        .set({ estUsd: FieldValue.increment(-ops.costPerImageUsd * Number(r.samples ?? 1)) }, { merge: true })
        .catch(() => undefined);
      if (blocked) await recordBlock(uid, ops.suspendAfterBlocks);
      console.warn(blocked ? 'tryon blocked' : 'tryon failed', { ...log, reason: blocked ? (e as Blocked).reason : (e as Error).message });
    }
  },
);
