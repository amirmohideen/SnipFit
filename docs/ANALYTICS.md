# Analytics

PostHog (EU cloud by default), with session replay and screen capture off. Events never include images, names, emails or anything identifying; `AnalyticsPropertyFilter` drops any property that isn't allow-listed. EU/UK/EEA/Swiss users are asked for consent first (opt-in); everyone else can opt out in Settings.

| Funnel | Event | Properties |
|---|---|---|
| Onboarding | `onboarding_step_viewed` | `step` (hook, age, terms, mode, camera, biometric) |
| | `age_confirmed` | `is_adult` |
| | `terms_accepted` | |
| | `mode_selected` | `mode` |
| Core | `capture_started` | `source` (camera, upload) |
| | `cutout_completed` | `quality` (auto score 0-1), `mode` |
| | `refine_used` | `tool` (brush, eraser, shape, reset) |
| | `live_window_opened` | `source` (window, practice) |
| | `compare_saved` | `source` (camera, demo) |
| Growth | `share_opened` | `format` (reveal, collage, single) |
| | `share_completed` | `target` (instagram, tiktok, snapchat, whatsapp, system), `format` |
| | `invite_opened` | `mode` |
| Money | `paywall_viewed` | `trigger` (soft_first_compare, home_badge, settings, ai_tryon) |
| | `purchase_started` | `product` |
| | `purchase_completed` | `product` |
| | `restore_tapped` | |
| AI | `ai_consent_given` | |
| | `ai_tryon_requested` | `mode` |
| | `ai_tryon_succeeded` / `ai_tryon_blocked` / `ai_tryon_failed` | `reason` (failed only: error code) |
| | `report_submitted` | `reason` |

Suggested funnels: install → `terms_accepted` → `cutout_completed` → `compare_saved` → `share_completed`; and `paywall_viewed` → `purchase_started` → `purchase_completed` by `trigger`.

Feature flag: `paywall_trial` (`control` / `trial`) for the free-trial experiment (also needs `trial_experiment_enabled` in Remote Config).
