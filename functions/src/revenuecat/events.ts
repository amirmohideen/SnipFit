/**
 * Maps RevenueCat webhook events to ledger changes. Pure, so every event
 * type is unit-tested. See https://www.revenuecat.com/docs/webhooks.
 */
import type { LedgerState } from '../credits/ledger.js';
import { grant, revoke, setPro } from '../credits/ledger.js';

export interface RevenueCatEvent {
  id: string;
  type: string;
  app_user_id?: string;
  original_app_user_id?: string;
  aliases?: string[];
  product_id?: string;
  entitlement_ids?: string[] | null;
  period_type?: string;
  purchased_at_ms?: number | null;
  expiration_at_ms?: number | null;
  transaction_id?: string;
  cancel_reason?: string | null;
  environment?: 'SANDBOX' | 'PRODUCTION';
  transferred_from?: string[];
  transferred_to?: string[];
}

export interface EventContext {
  creditPacks: Record<string, number>;
  proEntitlement: string;
  now: Date;
}

export interface LedgerChange {
  state: LedgerState;
  entries: { type: 'grant' | 'revoke' | 'pro'; amount: number; note: string }[];
}

const isAnonymous = (id: string | undefined) => !id || id.startsWith('$RCAnonymousID:');

/**
 * The Firebase UID for an event. The app logs into RevenueCat with the
 * Firebase UID, so anonymous RevenueCat IDs can't be mapped and are skipped.
 */
export function resolveUid(e: RevenueCatEvent): string | null {
  if (!isAnonymous(e.app_user_id)) return e.app_user_id!;
  for (const a of [e.original_app_user_id, ...(e.aliases ?? [])]) {
    if (!isAnonymous(a)) return a!;
  }
  return null;
}

function isPro(e: RevenueCatEvent, ctx: EventContext): boolean {
  return (e.entitlement_ids ?? []).includes(ctx.proEntitlement);
}

export function applyEvent(state: LedgerState, e: RevenueCatEvent, ctx: EventContext): LedgerChange {
  const pack = e.product_id ? ctx.creditPacks[e.product_id] : undefined;
  const expiresAt = e.expiration_at_ms ? new Date(e.expiration_at_ms) : null;
  switch (e.type) {
    case 'NON_RENEWING_PURCHASE':
      if (pack) {
        return { state: grant(state, pack), entries: [{ type: 'grant', amount: pack, note: `pack ${e.product_id}` }] };
      }
      return { state, entries: [] };

    case 'INITIAL_PURCHASE':
    case 'RENEWAL':
    case 'UNCANCELLATION':
    case 'PRODUCT_CHANGE':
    case 'SUBSCRIPTION_EXTENDED':
    case 'TEMPORARY_ENTITLEMENT_GRANT':
      if (!isPro(e, ctx)) return { state, entries: [] };
      return {
        state: setPro(
          state,
          { active: true, expiresAt, productId: e.product_id ?? null },
          ctx.now,
          // New subscriptions start a fresh monthly allowance period.
          e.type === 'INITIAL_PURCHASE',
        ),
        entries: [{ type: 'pro', amount: 0, note: `${e.type.toLowerCase()} ${e.product_id ?? ''}`.trim() }],
      };

    case 'EXPIRATION':
      if (!isPro(e, ctx) && state.pro.productId !== e.product_id) return { state, entries: [] };
      return {
        state: { ...state, pro: { ...state.pro, active: false, expiresAt } },
        entries: [{ type: 'pro', amount: 0, note: 'expired' }],
      };

    case 'CANCELLATION':
      // A refunded credit pack takes back what's still unspent. A cancelled
      // subscription stays active until it expires (EXPIRATION event).
      if (pack && e.cancel_reason === 'CUSTOMER_SUPPORT') {
        const r = revoke(state, pack);
        return { state: r.state, entries: [{ type: 'revoke', amount: r.revoked, note: `refund ${e.product_id}` }] };
      }
      if (isPro(e, ctx) && e.cancel_reason === 'CUSTOMER_SUPPORT') {
        // Refunded subscription: Pro ends now.
        return {
          state: { ...state, pro: { ...state.pro, active: false, expiresAt: ctx.now } },
          entries: [{ type: 'pro', amount: 0, note: 'refunded' }],
        };
      }
      return { state, entries: [] };

    default:
      // TEST, BILLING_ISSUE, SUBSCRIPTION_PAUSED, TRANSFER (handled by the
      // caller), INVOICE_ISSUANCE...: no ledger change.
      return { state, entries: [] };
  }
}
