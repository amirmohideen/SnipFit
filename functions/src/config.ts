import { defineSecret, defineString } from 'firebase-functions/params';
import { getRemoteConfig } from 'firebase-admin/remote-config';

import './lib/admin.js';

// ----------------------------------------------------------------- secrets
// Set with: firebase functions:secrets:set <NAME>
export const REVENUECAT_WEBHOOK_SECRET = defineSecret('REVENUECAT_WEBHOOK_SECRET');
/** Optional: lets account deletion also delete the RevenueCat subscriber. */
export const REVENUECAT_SECRET_API_KEY = defineSecret('REVENUECAT_SECRET_API_KEY');
export const COVERAGE_SERVICE_TOKEN = defineSecret('COVERAGE_SERVICE_TOKEN');

// -------------------------------------------------------------- parameters
export const VERTEX_LOCATION = defineString('VERTEX_LOCATION', { default: 'us-central1' });
/** Confirm the current model ID in the Vertex AI docs before launch. */
export const TRYON_MODEL = defineString('TRYON_MODEL', { default: 'virtual-try-on-preview-08-04' });
export const GEMINI_IMAGE_MODEL = defineString('GEMINI_IMAGE_MODEL', { default: 'gemini-2.5-flash-image' });
/** URL of the `coverage` function in functions-python (deployed separately). */
export const COVERAGE_SERVICE_URL = defineString('COVERAGE_SERVICE_URL', { default: '' });

// ---------------------------------------------------------------- products
/** RevenueCat product IDs for consumable credit packs, and their size. */
export const CREDIT_PACKS: Record<string, number> = {
  snipfit_credits_20: 20,
};
export const PRO_ENTITLEMENT = 'pro';

/** AI consent versions the server accepts (bump with ConsentVersions.ai). */
export const ACCEPTED_AI_CONSENT_VERSIONS = new Set(['2026-11-05-draft+a1']);

// ----------------------------------------------------- operational switches
// Firebase Remote Config server template, so a viral spike can't run up a
// surprise AI bill: change these in the console without redeploying.
export interface AiOps {
  enabled: boolean;
  dailyCapUsd: number;
  costPerImageUsd: number;
  userHourlyLimit: number;
  deviceDailyLimit: number;
  samples: number;
  hijabProvider: 'vertex_vto' | 'gemini';
  coverageRequired: boolean;
  suspendAfterBlocks: number;
}

export const AI_OPS_DEFAULTS: AiOps = {
  enabled: true,
  dailyCapUsd: 50,
  costPerImageUsd: 0.06,
  userHourlyLimit: 6,
  deviceDailyLimit: 20,
  samples: 1,
  hijabProvider: 'vertex_vto',
  coverageRequired: true,
  suspendAfterBlocks: 3,
};

let cached: { at: number; value: AiOps } | null = null;

export async function aiOps(): Promise<AiOps> {
  if (cached && Date.now() - cached.at < 60_000) return cached.value;
  let value = AI_OPS_DEFAULTS;
  try {
    const template = await getRemoteConfig().getServerTemplate({
      defaultConfig: {
        ai_enabled: AI_OPS_DEFAULTS.enabled,
        ai_daily_cap_usd: AI_OPS_DEFAULTS.dailyCapUsd,
        ai_cost_per_image_usd: AI_OPS_DEFAULTS.costPerImageUsd,
        ai_user_hourly_limit: AI_OPS_DEFAULTS.userHourlyLimit,
        ai_device_daily_limit: AI_OPS_DEFAULTS.deviceDailyLimit,
        ai_samples: AI_OPS_DEFAULTS.samples,
        tryon_provider_hijab: AI_OPS_DEFAULTS.hijabProvider,
        ai_coverage_required: AI_OPS_DEFAULTS.coverageRequired,
        ai_suspend_after_blocks: AI_OPS_DEFAULTS.suspendAfterBlocks,
      },
    });
    const c = template.evaluate();
    const provider = c.getString('tryon_provider_hijab');
    value = {
      enabled: c.getBoolean('ai_enabled'),
      dailyCapUsd: c.getNumber('ai_daily_cap_usd'),
      costPerImageUsd: c.getNumber('ai_cost_per_image_usd'),
      userHourlyLimit: c.getNumber('ai_user_hourly_limit'),
      deviceDailyLimit: c.getNumber('ai_device_daily_limit'),
      samples: Math.min(2, Math.max(1, Math.round(c.getNumber('ai_samples')))),
      hijabProvider: provider === 'gemini' ? 'gemini' : 'vertex_vto',
      coverageRequired: c.getBoolean('ai_coverage_required'),
      suspendAfterBlocks: c.getNumber('ai_suspend_after_blocks'),
    };
  } catch (e) {
    console.warn('Remote Config server template unavailable, using defaults', (e as Error).message);
  }
  cached = { at: Date.now(), value };
  return value;
}
