import { Timestamp } from 'firebase-admin/firestore';
import { getFunctions } from 'firebase-admin/functions';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { ACCEPTED_AI_CONSENT_VERSIONS, aiOps } from '../config.js';
import { chooseBucket, normalizeAllowance, reserve } from '../credits/ledger.js';
import { bucket, db, ledgerEntry, readLedger, uidHash, writeLedger } from '../lib/admin.js';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MODES = new Set(['women', 'hijab', 'men']);
const MAX_INPUT_BYTES = 8 * 1024 * 1024;

export const dayKey = (d: Date) => d.toISOString().slice(0, 10);

/** Latest consent record of a type, ordered by server time. */
async function latestConsent(uid: string, type: string) {
  const snap = await db
    .collection('users')
    .doc(uid)
    .collection('consents')
    .where('type', '==', type)
    .orderBy('serverAt', 'desc')
    .limit(1)
    .get();
  return snap.docs[0]?.data();
}

/**
 * Starts a paid AI try-on. The app has already uploaded the two input photos
 * (only after the AI consent screen). This checks App Check, sign-in, the
 * kill switch, suspension, age (18+), AI consent, inputs, rate limits, the
 * global daily spend cap and credits, then reserves one credit and queues
 * the job. Nothing is deducted until a result is delivered.
 */
export const createTryOn = onCall({ enforceAppCheck: true, maxInstances: 20 }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign-in required.');
  const { requestId, mode, deviceKey } = (req.data ?? {}) as { requestId?: string; mode?: string; deviceKey?: string };
  if (!requestId || !UUID.test(requestId) || !mode || !MODES.has(mode)) {
    throw new HttpsError('invalid-argument', 'Bad request.');
  }
  const device = typeof deviceKey === 'string' && /^[0-9a-f]{8,64}$/.test(deviceKey) ? deviceKey : 'unknown';
  const ops = await aiOps();
  if (!ops.enabled) throw new HttpsError('unavailable', 'AI try-on is paused.', { reason: 'disabled' });

  const age = await latestConsent(uid, 'age');
  if (age?.isAdult !== true) throw new HttpsError('failed-precondition', 'Adults only.', { reason: 'not_adult' });
  const ai = await latestConsent(uid, 'ai');
  if (ai?.accepted !== true || !ACCEPTED_AI_CONSENT_VERSIONS.has(String(ai.version))) {
    throw new HttpsError('failed-precondition', 'AI consent required.', { reason: 'consent' });
  }

  // Inputs must exist where only this user can write them.
  const folder = `tryon-inputs/${uid}/${requestId}`;
  for (const name of ['person.jpg', 'garment.png']) {
    const [meta] = await bucket()
      .file(`${folder}/${name}`)
      .getMetadata()
      .catch(() => [null]);
    if (!meta || Number(meta.size) > MAX_INPUT_BYTES) {
      throw new HttpsError('failed-precondition', 'Missing input.', { reason: 'inputs' });
    }
  }

  const now = new Date();
  const userRef = db.collection('users').doc(uid);
  const userRate = db.collection('rateLimits').doc(`u_${uid}_${now.toISOString().slice(0, 13)}`);
  const deviceRate = db.collection('rateLimits').doc(`d_${device}_${dayKey(now)}`);
  const spendRef = db.collection('aiSpendDays').doc(dayKey(now));
  const requestRef = db.collection('tryonRequests').doc(requestId);
  const estCost = ops.costPerImageUsd * ops.samples;

  await db.runTransaction(async (tx) => {
    const [userSnap, userRateSnap, deviceRateSnap, spendSnap, existing] = await Promise.all([
      tx.get(userRef),
      tx.get(userRate),
      tx.get(deviceRate),
      tx.get(spendRef),
      tx.get(requestRef),
    ]);
    if (existing.exists) throw new HttpsError('already-exists', 'Duplicate request.');
    const suspended = userSnap.get('suspendedUntil') as Timestamp | undefined;
    if (suspended && suspended.toMillis() > now.getTime()) {
      throw new HttpsError('permission-denied', 'Suspended.', { reason: 'suspended' });
    }
    if ((userRateSnap.get('count') ?? 0) >= ops.userHourlyLimit || (deviceRateSnap.get('count') ?? 0) >= ops.deviceDailyLimit) {
      throw new HttpsError('resource-exhausted', 'Rate limited.', { reason: 'rate_limited' });
    }
    const spent = Number(spendSnap.get('estUsd') ?? 0);
    if (spent + estCost > ops.dailyCapUsd) {
      throw new HttpsError('resource-exhausted', 'Daily cap reached.', { reason: 'daily_cap' });
    }
    const state = normalizeAllowance(readLedger(userSnap.data()), now);
    const chosen = chooseBucket(state, now);
    if (!chosen) throw new HttpsError('resource-exhausted', 'No credits.', { reason: 'no_credits' });

    const next = reserve(state, chosen);
    tx.set(userRef, { ...writeLedger(next), updatedAt: Timestamp.now() }, { merge: true });
    ledgerEntry(tx, uid, { type: 'reserve', amount: 1, bucket: chosen, refId: requestId });
    tx.set(userRate, { count: (userRateSnap.get('count') ?? 0) + 1, expiresAt: Timestamp.fromMillis(now.getTime() + 2 * 3600_000) });
    tx.set(deviceRate, { count: (deviceRateSnap.get('count') ?? 0) + 1, expiresAt: Timestamp.fromMillis(now.getTime() + 2 * 86400_000) });
    tx.set(spendRef, { estUsd: spent + estCost, count: Number(spendSnap.get('count') ?? 0) + 1 }, { merge: true });
    tx.set(requestRef, {
      uid,
      mode,
      status: 'queued',
      bucket: chosen,
      samples: ops.samples,
      deviceKey: device,
      createdAt: Timestamp.fromDate(now),
      updatedAt: Timestamp.fromDate(now),
    });
  });

  await getFunctions().taskQueue('processTryOn').enqueue({ requestId }, { dispatchDeadlineSeconds: 600 });
  console.info('tryon queued', { requestId, user: uidHash(uid), mode });
  return { requestId };
});
