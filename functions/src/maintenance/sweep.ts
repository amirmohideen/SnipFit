import { Timestamp } from 'firebase-admin/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';

import type { Bucket } from '../credits/ledger.js';
import { release } from '../credits/ledger.js';
import { bucket, db, ledgerEntry, readLedger, writeLedger } from '../lib/admin.js';

const HOUR = 3600_000;

/**
 * Hourly guarantee behind "deleted within 24 hours": a Storage lifecycle
 * rule alone can lag by a day, so this deletes any AI input or result older
 * than 23 hours, and refunds requests stuck for more than 2 hours.
 */
export const sweepTryOnData = onSchedule({ schedule: 'every 60 minutes', timeoutSeconds: 540 }, async () => {
  const cutoff = Date.now() - 23 * HOUR;
  let deleted = 0;
  for (const prefix of ['tryon-inputs/', 'tryon-results/']) {
    const [files] = await bucket().getFiles({ prefix });
    for (const f of files) {
      const created = Date.parse(String(f.metadata.timeCreated ?? ''));
      if (Number.isFinite(created) && created < cutoff) {
        await f.delete({ ignoreNotFound: true });
        deleted++;
      }
    }
  }

  const stuck = await db
    .collection('tryonRequests')
    .where('status', 'in', ['queued', 'checking', 'generating', 'finishing'])
    .where('updatedAt', '<', Timestamp.fromMillis(Date.now() - 2 * HOUR))
    .limit(200)
    .get();
  for (const doc of stuck.docs) {
    const uid = doc.get('uid') as string;
    const b = doc.get('bucket') as Bucket;
    await db.runTransaction(async (tx) => {
      const fresh = await tx.get(doc.ref);
      if (fresh.get('settled') === true) return;
      const userRef = db.collection('users').doc(uid);
      const user = await tx.get(userRef);
      const next = release(readLedger(user.data()), b, (doc.get('createdAt') as Timestamp).toDate());
      tx.set(userRef, writeLedger(next), { merge: true });
      ledgerEntry(tx, uid, { type: 'release', amount: 1, bucket: b, refId: doc.id, note: 'timeout' });
      tx.set(doc.ref, { status: 'failed', settled: true, error: { code: 'timeout' }, updatedAt: Timestamp.now() }, { merge: true });
    });
  }

  // Old request records carry no images; keep 30 days for support.
  const old = await db
    .collection('tryonRequests')
    .where('createdAt', '<', Timestamp.fromMillis(Date.now() - 30 * 24 * HOUR))
    .limit(500)
    .get();
  await Promise.all(old.docs.map((d) => d.ref.delete()));
  console.info('sweep done', { deletedFiles: deleted, refunded: stuck.size, prunedRequests: old.size });
});
