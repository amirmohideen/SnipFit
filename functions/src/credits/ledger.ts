/**
 * Credit ledger logic. Pure functions, so every rule is unit-tested; the
 * Firestore transactions in ledgerStore.ts only load, apply and save.
 *
 * Rules (from the spec):
 * - The Firestore ledger is the source of truth, written only by Cloud
 *   Functions and the RevenueCat webhook.
 * - A credit is deducted only when a generation succeeds. A request first
 *   *reserves* one unit; success *commits* it, failure or a safety block
 *   *releases* it (an automatic refund).
 * - Pro includes a monthly allowance (30 AI try-ons), used before purchased
 *   credits. The allowance resets lazily each month from the period start.
 */

export type Bucket = 'allowance' | 'purchased';

export interface LedgerState {
  credits: { balance: number; reserved: number };
  allowance: { limit: number; used: number; periodStart: Date | null };
  pro: { active: boolean; expiresAt: Date | null; productId: string | null };
}

export const PRO_MONTHLY_ALLOWANCE = 30;

export function emptyState(): LedgerState {
  return {
    credits: { balance: 0, reserved: 0 },
    allowance: { limit: PRO_MONTHLY_ALLOWANCE, used: 0, periodStart: null },
    pro: { active: false, expiresAt: null, productId: null },
  };
}

/** Adds calendar months, clamping to the last day of the target month. */
export function addMonths(d: Date, months: number): Date {
  const out = new Date(d.getTime());
  const day = out.getUTCDate();
  out.setUTCDate(1);
  out.setUTCMonth(out.getUTCMonth() + months);
  const last = new Date(Date.UTC(out.getUTCFullYear(), out.getUTCMonth() + 1, 0)).getUTCDate();
  out.setUTCDate(Math.min(day, last));
  return out;
}

export function isProActive(s: LedgerState, now: Date): boolean {
  return s.pro.active && (s.pro.expiresAt === null || s.pro.expiresAt.getTime() > now.getTime());
}

/** Rolls the monthly allowance forward to the period containing [now]. */
export function normalizeAllowance(s: LedgerState, now: Date): LedgerState {
  if (!isProActive(s, now)) return s;
  let start = s.allowance.periodStart;
  if (start === null) {
    return { ...s, allowance: { limit: PRO_MONTHLY_ALLOWANCE, used: 0, periodStart: now } };
  }
  if (now.getTime() < addMonths(start, 1).getTime()) return s;
  // Find the period that contains now (handles gaps of several months).
  let guard = 0;
  while (now.getTime() >= addMonths(start, 1).getTime() && guard++ < 240) {
    start = addMonths(start, 1);
  }
  return { ...s, allowance: { limit: PRO_MONTHLY_ALLOWANCE, used: 0, periodStart: start } };
}

export function available(s: LedgerState, now: Date): { allowance: number; purchased: number } {
  const allowance = isProActive(s, now) ? Math.max(0, s.allowance.limit - s.allowance.used) : 0;
  const purchased = Math.max(0, s.credits.balance - s.credits.reserved);
  return { allowance, purchased };
}

/** Pro allowance first, then purchased credits. Null when nothing is left. */
export function chooseBucket(s: LedgerState, now: Date): Bucket | null {
  const a = available(s, now);
  if (a.allowance > 0) return 'allowance';
  if (a.purchased > 0) return 'purchased';
  return null;
}

export function reserve(s: LedgerState, bucket: Bucket): LedgerState {
  if (bucket === 'allowance') {
    return { ...s, allowance: { ...s.allowance, used: s.allowance.used + 1 } };
  }
  return { ...s, credits: { ...s.credits, reserved: s.credits.reserved + 1 } };
}

/** Success: the reserved unit is spent. */
export function commit(s: LedgerState, bucket: Bucket): LedgerState {
  if (bucket === 'allowance') return s; // counted when reserved
  return {
    ...s,
    credits: {
      balance: Math.max(0, s.credits.balance - 1),
      reserved: Math.max(0, s.credits.reserved - 1),
    },
  };
}

/** Failure or safety block: the reserved unit is returned. */
export function release(s: LedgerState, bucket: Bucket, reservedAt: Date | null = null): LedgerState {
  if (bucket === 'allowance') {
    // If the period rolled over since the reservation, the new period
    // already started at zero; don't go negative.
    const samePeriod =
      reservedAt === null || s.allowance.periodStart === null || reservedAt.getTime() >= s.allowance.periodStart.getTime();
    if (!samePeriod) return s;
    return { ...s, allowance: { ...s.allowance, used: Math.max(0, s.allowance.used - 1) } };
  }
  return { ...s, credits: { ...s.credits, reserved: Math.max(0, s.credits.reserved - 1) } };
}

export function grant(s: LedgerState, amount: number): LedgerState {
  return { ...s, credits: { ...s.credits, balance: s.credits.balance + Math.max(0, amount) } };
}

/** Refunded credit pack: take back what's still unspent (never below zero). */
export function revoke(s: LedgerState, amount: number): { state: LedgerState; revoked: number } {
  const unspent = Math.max(0, s.credits.balance - s.credits.reserved);
  const revoked = Math.min(unspent, Math.max(0, amount));
  return { state: { ...s, credits: { ...s.credits, balance: s.credits.balance - revoked } }, revoked };
}

export function setPro(
  s: LedgerState,
  pro: { active: boolean; expiresAt: Date | null; productId: string | null },
  now: Date,
  resetPeriod: boolean,
): LedgerState {
  const next: LedgerState = { ...s, pro };
  if (pro.active && (resetPeriod || s.allowance.periodStart === null)) {
    next.allowance = { limit: PRO_MONTHLY_ALLOWANCE, used: 0, periodStart: now };
  }
  return next;
}
