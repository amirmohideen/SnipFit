import { Timestamp } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { db, uidHash } from '../lib/admin.js';

const REASONS = new Set(['inappropriate', 'not_permitted', 'poor_quality', 'other']);

/**
 * In-app "Report" on AI results (Google Play's generative-AI policy). Reports
 * land in a moderation queue with the generation's metadata, used to tune
 * the filters. No image is copied: results are deleted within 24 hours.
 */
export const reportResult = onCall({ enforceAppCheck: true }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign-in required.');
  const { requestId, reason } = (req.data ?? {}) as { requestId?: string; reason?: string };
  if (!requestId || !reason || !REASONS.has(reason)) throw new HttpsError('invalid-argument', 'Bad request.');
  const request = await db.collection('tryonRequests').doc(requestId).get();
  if (!request.exists || request.get('uid') !== uid) throw new HttpsError('not-found', 'Not found.');
  await db.collection('moderationReports').add({
    requestId,
    user: uidHash(uid),
    reason,
    provider: request.get('provider') ?? null,
    mode: request.get('mode') ?? null,
    status: 'open',
    createdAt: Timestamp.now(),
  });
  console.info('report submitted', { requestId, reason });
  return { ok: true };
});
