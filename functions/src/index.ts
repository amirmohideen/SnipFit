/**
 * Snipfit Cloud Functions (2nd gen). Only paid features touch the server:
 * the free cutout, live window and sharing never leave the phone.
 */
import { setGlobalOptions } from 'firebase-functions/v2';

setGlobalOptions({ region: 'us-central1', maxInstances: 50 });

export { revenuecatWebhook } from './revenuecat/webhook.js';
export { createTryOn } from './tryon/create.js';
export { processTryOn } from './tryon/process.js';
export { reportResult } from './reports/report.js';
export { deleteAccount } from './account/delete.js';
export { sweepTryOnData } from './maintenance/sweep.js';
