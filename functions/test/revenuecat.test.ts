import { describe, expect, it } from 'vitest';

import { emptyState, grant } from '../src/credits/ledger.js';
import type { RevenueCatEvent } from '../src/revenuecat/events.js';
import { applyEvent, resolveUid } from '../src/revenuecat/events.js';

const ctx = { creditPacks: { snipfit_credits_20: 20 }, proEntitlement: 'pro', now: new Date('2026-11-05T12:00:00Z') };
const ev = (e: Partial<RevenueCatEvent>): RevenueCatEvent => ({ id: 'evt', type: 'TEST', app_user_id: 'uid1', ...e });

describe('RevenueCat webhook mapping', () => {
  it('grants credits for a credit pack purchase', () => {
    const r = applyEvent(emptyState(), ev({ type: 'NON_RENEWING_PURCHASE', product_id: 'snipfit_credits_20' }), ctx);
    expect(r.state.credits.balance).toBe(20);
    expect(r.entries).toEqual([{ type: 'grant', amount: 20, note: 'pack snipfit_credits_20' }]);
  });

  it('ignores unknown non-renewing products', () => {
    const r = applyEvent(emptyState(), ev({ type: 'NON_RENEWING_PURCHASE', product_id: 'other' }), ctx);
    expect(r.state.credits.balance).toBe(0);
    expect(r.entries).toHaveLength(0);
  });

  it('activates Pro and starts a fresh allowance on initial purchase', () => {
    const r = applyEvent(
      emptyState(),
      ev({ type: 'INITIAL_PURCHASE', product_id: 'snipfit_pro_yearly', entitlement_ids: ['pro'], expiration_at_ms: Date.parse('2027-11-05T12:00:00Z') }),
      ctx,
    );
    expect(r.state.pro.active).toBe(true);
    expect(r.state.allowance.used).toBe(0);
    expect(r.state.allowance.periodStart?.toISOString()).toBe(ctx.now.toISOString());
  });

  it('ends Pro on expiration', () => {
    const active = applyEvent(emptyState(), ev({ type: 'INITIAL_PURCHASE', product_id: 'p', entitlement_ids: ['pro'] }), ctx).state;
    const r = applyEvent(active, ev({ type: 'EXPIRATION', product_id: 'p', entitlement_ids: ['pro'] }), ctx);
    expect(r.state.pro.active).toBe(false);
  });

  it('keeps Pro active after a normal cancellation until it expires', () => {
    const active = applyEvent(emptyState(), ev({ type: 'INITIAL_PURCHASE', product_id: 'p', entitlement_ids: ['pro'] }), ctx).state;
    const r = applyEvent(active, ev({ type: 'CANCELLATION', product_id: 'p', entitlement_ids: ['pro'], cancel_reason: 'UNSUBSCRIBE' }), ctx);
    expect(r.state.pro.active).toBe(true);
  });

  it('revokes unspent credits when a pack is refunded', () => {
    const r = applyEvent(
      grant(emptyState(), 20),
      ev({ type: 'CANCELLATION', product_id: 'snipfit_credits_20', cancel_reason: 'CUSTOMER_SUPPORT' }),
      ctx,
    );
    expect(r.state.credits.balance).toBe(0);
    expect(r.entries[0]).toMatchObject({ type: 'revoke', amount: 20 });
  });

  it('maps events to the Firebase UID, never to anonymous RevenueCat IDs', () => {
    expect(resolveUid(ev({ app_user_id: 'firebaseUid' }))).toBe('firebaseUid');
    expect(resolveUid(ev({ app_user_id: '$RCAnonymousID:abc', aliases: ['$RCAnonymousID:abc', 'realUid'] }))).toBe('realUid');
    expect(resolveUid(ev({ app_user_id: '$RCAnonymousID:abc', aliases: [] }))).toBeNull();
  });
});
