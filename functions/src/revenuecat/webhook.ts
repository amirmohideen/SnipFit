import { Timestamp } from 'firebase-admin/firestore';
import { onRequest } from 'firebase-functions/v2/https';
import { timingSafeEqual } from 'node:crypto';

import { CREDIT_PACKS, PRO_ENTITLEMENT, REVENUECAT_WEBHOOK_SECRET } from '../config.js';
import { db, ledgerEntry, readLedger, uidHash, writeLedger } from '../lib/admin.js';
import type { RevenueCatEvent } from './events.js';
import { applyEvent, resolveUid } from './events.js';

function authorized(header: string | undefined, secret: string): boolean {
  if (!header || !secret) return false;
  const a = Buffer.from(header);
  const b = Buffer.from(`Bearer ${secret}`);
  return a.length === b.length && timingSafeEqual(a, b);
}

/**
 * RevenueCat → Firestore ledger. The only place credits are granted;
 * the app never writes balances. Idempotent per event ID.
 *
 * In RevenueCat: Project settings → Integrations → Webhooks, URL of this
 * function, Authorization header "Bearer <REVENUECAT_WEBHOOK_SECRET>".
 */
export const revenuecatWebhook = onRequest(
  { secrets: [REVENUECAT_WEBHOOK_SECRET], cors: false, maxInstances: 20 },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).send('POST only');
      return;
    }
    if (!authorized(req.get('Authorization'), REVENUECAT_WEBHOOK_SECRET.value())) {
      res.status(401).send('unauthorized');
      return;
    }
    const event = (req.body?.event ?? null) as RevenueCatEvent | null;
    if (!event?.id || !event.type) {
      res.status(400).send('missing event');
      return;
    }

    // Subscription moved to another account: Pro follows it.
    if (event.type === 'TRANSFER') {
      for (const from of event.transferred_from ?? []) {
        if (from.startsWith('$RCAnonymousID:')) continue;
        await db.collection('users').doc(from).set({ pro: { active: false } }, { merge: true });
      }
      res.status(200).send('ok');
      return;
    }

    const uid = resolveUid(event);
    if (!uid) {
      console.warn('revenuecat event without a mappable user', { id: event.id, type: event.type });
      res.status(200).send('ignored');
      return;
    }

    const eventRef = db.collection('rcEvents').doc(event.id);
    const userRef = db.collection('users').doc(uid);
    await db.runTransaction(async (tx) => {
      const seen = await tx.get(eventRef);
      if (seen.exists) return;
      const snap = await tx.get(userRef);
      const before = readLedger(snap.data());
      const change = applyEvent(before, event, {
        creditPacks: CREDIT_PACKS,
        proEntitlement: PRO_ENTITLEMENT,
        now: new Date(),
      });
      tx.set(userRef, { ...writeLedger(change.state), updatedAt: Timestamp.now() }, { merge: true });
      for (const e of change.entries) {
        ledgerEntry(tx, uid, { type: e.type, amount: e.amount, refId: event.transaction_id ?? event.id, note: e.note });
      }
      tx.set(eventRef, { type: event.type, uid: uidHash(uid), environment: event.environment ?? null, processedAt: Timestamp.now() });
    });
    console.info('revenuecat event applied', { id: event.id, type: event.type, user: uidHash(uid) });
    res.status(200).send('ok');
  },
);
