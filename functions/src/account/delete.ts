import { getAuth } from 'firebase-admin/auth';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { REVENUECAT_SECRET_API_KEY } from '../config.js';
import { bucket, db, uidHash } from '../lib/admin.js';

/**
 * In-app account deletion (App Store 5.1.1(v), Google Play): deletes the
 * user's Firestore data, any stored AI inputs/results, the RevenueCat
 * subscriber record and finally the auth account. Store subscriptions must
 * still be cancelled by the user in their store account.
 *
 * Consent records are deleted too. If counsel decides some must be kept as
 * proof of consent, move them to a restricted archive here instead.
 */
export const deleteAccount = onCall({ enforceAppCheck: true, secrets: [REVENUECAT_SECRET_API_KEY] }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign-in required.');

  await db.recursiveDelete(db.collection('users').doc(uid));
  const requests = await db.collection('tryonRequests').where('uid', '==', uid).get();
  await Promise.all(requests.docs.map((d) => d.ref.delete()));
  await bucket().deleteFiles({ prefix: `tryon-inputs/${uid}/` });
  await bucket().deleteFiles({ prefix: `tryon-results/${uid}/` });

  const rcKey = REVENUECAT_SECRET_API_KEY.value();
  if (rcKey) {
    const res = await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}`, {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${rcKey}` },
    });
    if (!res.ok && res.status !== 404) console.warn('RevenueCat delete failed', res.status);
  }

  await getAuth().deleteUser(uid);
  console.info('account deleted', { user: uidHash(uid) });
  return { ok: true };
});
