import { describe, expect, it } from 'vitest';

import {
  addMonths,
  available,
  chooseBucket,
  commit,
  emptyState,
  grant,
  normalizeAllowance,
  release,
  reserve,
  revoke,
  setPro,
} from '../src/credits/ledger.js';

const now = new Date('2026-11-05T12:00:00Z');
const pro = (s = emptyState()) =>
  setPro(s, { active: true, expiresAt: new Date('2027-11-05T00:00:00Z'), productId: 'snipfit_pro_yearly' }, now, true);

describe('credit ledger', () => {
  it('has nothing to spend by default', () => {
    expect(chooseBucket(emptyState(), now)).toBeNull();
  });

  it('deducts a purchased credit only when the generation succeeds', () => {
    let s = grant(emptyState(), 20);
    s = reserve(s, 'purchased');
    expect(available(s, now).purchased).toBe(19);
    expect(s.credits.balance).toBe(20); // not deducted yet
    s = commit(s, 'purchased');
    expect(s.credits).toEqual({ balance: 19, reserved: 0 });
  });

  it('refunds automatically on failure or a safety block', () => {
    let s = grant(emptyState(), 1);
    s = reserve(s, 'purchased');
    expect(chooseBucket(s, now)).toBeNull(); // the only credit is held
    s = release(s, 'purchased');
    expect(s.credits).toEqual({ balance: 1, reserved: 0 });
    expect(chooseBucket(s, now)).toBe('purchased');
  });

  it('uses the Pro allowance before purchased credits', () => {
    let s = grant(pro(), 5);
    expect(chooseBucket(s, now)).toBe('allowance');
    for (let i = 0; i < 30; i++) s = reserve(s, 'allowance');
    expect(chooseBucket(s, now)).toBe('purchased');
  });

  it('releases an allowance unit back on failure', () => {
    let s = reserve(pro(), 'allowance');
    expect(s.allowance.used).toBe(1);
    s = release(s, 'allowance', now);
    expect(s.allowance.used).toBe(0);
  });

  it('resets the allowance every month, even on a yearly plan', () => {
    let s = pro();
    for (let i = 0; i < 30; i++) s = reserve(s, 'allowance');
    expect(available(s, now).allowance).toBe(0);
    const nextMonth = new Date('2026-12-06T00:00:00Z');
    s = normalizeAllowance(s, nextMonth);
    expect(s.allowance.used).toBe(0);
    expect(s.allowance.periodStart?.toISOString()).toBe('2026-12-05T12:00:00.000Z');
  });

  it('skips over months with no use', () => {
    const s = normalizeAllowance(pro(), new Date('2027-03-20T00:00:00Z'));
    expect(s.allowance.periodStart?.toISOString()).toBe('2027-03-05T12:00:00.000Z');
  });

  it('gives no allowance once Pro has expired', () => {
    const s = setPro(emptyState(), { active: true, expiresAt: new Date('2026-11-01T00:00:00Z'), productId: 'x' }, now, true);
    expect(available(s, now).allowance).toBe(0);
  });

  it('a refunded pack takes back only what is unspent', () => {
    let s = grant(emptyState(), 20);
    for (let i = 0; i < 5; i++) s = commit(reserve(s, 'purchased'), 'purchased');
    const r = revoke(s, 20);
    expect(r.revoked).toBe(15);
    expect(r.state.credits.balance).toBe(0);
  });

  it('adds months without overflowing short months', () => {
    expect(addMonths(new Date('2026-01-31T00:00:00Z'), 1).toISOString()).toBe('2026-02-28T00:00:00.000Z');
  });
});
