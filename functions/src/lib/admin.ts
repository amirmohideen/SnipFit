import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { createHash } from 'node:crypto';

import type { LedgerState } from '../credits/ledger.js';
import { emptyState } from '../credits/ledger.js';

if (getApps().length === 0) initializeApp();

export const db = getFirestore();
export const bucket = () => getStorage().bucket();

/** Never log raw user IDs or images: a short hash is enough to investigate. */
export const uidHash = (uid: string) => createHash('sha256').update(uid).digest('hex').slice(0, 12);

const toDate = (v: unknown): Date | null => (v instanceof Timestamp ? v.toDate() : null);
const toTs = (d: Date | null) => (d === null ? null : Timestamp.fromDate(d));

export function readLedger(data: FirebaseFirestore.DocumentData | undefined): LedgerState {
  const s = emptyState();
  if (!data) return s;
  const c = data.credits ?? {};
  const a = data.allowance ?? {};
  const p = data.pro ?? {};
  return {
    credits: { balance: Number(c.balance ?? 0), reserved: Number(c.reserved ?? 0) },
    allowance: { limit: Number(a.limit ?? s.allowance.limit), used: Number(a.used ?? 0), periodStart: toDate(a.periodStart) },
    pro: { active: p.active === true, expiresAt: toDate(p.expiresAt), productId: (p.productId as string | undefined) ?? null },
  };
}

export function writeLedger(s: LedgerState) {
  return {
    credits: { balance: s.credits.balance, reserved: s.credits.reserved },
    allowance: { limit: s.allowance.limit, used: s.allowance.used, periodStart: toTs(s.allowance.periodStart) },
    pro: { active: s.pro.active, expiresAt: toTs(s.pro.expiresAt), productId: s.pro.productId },
  };
}

export type LedgerEntryType = 'grant' | 'revoke' | 'reserve' | 'commit' | 'release' | 'pro';

export function ledgerEntry(
  tx: FirebaseFirestore.Transaction,
  uid: string,
  entry: { type: LedgerEntryType; amount: number; bucket?: string; refId: string; note?: string },
) {
  const ref = db.collection('users').doc(uid).collection('ledger').doc();
  tx.set(ref, { ...entry, at: Timestamp.now() });
}
