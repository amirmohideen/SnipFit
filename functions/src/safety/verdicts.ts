/**
 * Safety decisions, kept pure so they're unit-tested with fixtures.
 * Snipfit only ever replaces clothing with fabric or another garment; it
 * must be impossible to use it to reveal skin or make sexual imagery.
 */

export type Likelihood = 'UNKNOWN' | 'VERY_UNLIKELY' | 'UNLIKELY' | 'POSSIBLE' | 'LIKELY' | 'VERY_LIKELY';

const RANK: Record<Likelihood, number> = {
  UNKNOWN: 0,
  VERY_UNLIKELY: 1,
  UNLIKELY: 2,
  POSSIBLE: 3,
  LIKELY: 4,
  VERY_LIKELY: 5,
};

export interface SafeSearch {
  adult: Likelihood;
  racy: Likelihood;
  violence: Likelihood;
}

export interface ImageAnalysis {
  safeSearch: SafeSearch;
  labels: { description: string; score: number }[];
}

export type BlockReason = 'adult' | 'racy' | 'violence' | 'restricted_garment' | 'coverage' | 'model_filtered';

export type Verdict = { ok: true } | { ok: false; reason: BlockReason };

/**
 * Garment categories Snipfit never accepts, as a try-on garment or as the
 * person's reference outfit (Google's own try-on excludes these too).
 */
export const RESTRICTED_LABELS = [
  'swimwear',
  'swimsuit',
  'swim brief',
  'bikini',
  'one-piece swimsuit',
  'bathing suit',
  'lingerie',
  'undergarment',
  'underwear',
  'brassiere',
  'bra',
  'briefs',
  'panties',
  'thong',
  'boxer briefs',
  'corset',
  'negligee',
];

export function judgeImage(a: ImageAnalysis, { labelMinScore = 0.6 }: { labelMinScore?: number } = {}): Verdict {
  const s = a.safeSearch;
  if (RANK[s.adult] >= RANK.LIKELY) return { ok: false, reason: 'adult' };
  if (RANK[s.violence] >= RANK.LIKELY) return { ok: false, reason: 'violence' };
  if (RANK[s.racy] >= RANK.LIKELY) return { ok: false, reason: 'racy' };
  const restricted = a.labels.some(
    (l) => l.score >= labelMinScore && RESTRICTED_LABELS.includes(l.description.trim().toLowerCase()),
  );
  if (restricted) return { ok: false, reason: 'restricted_garment' };
  return { ok: true };
}

/** Share of the person's pixels that are skin / clothing (from segmentation). */
export interface CoverageRatios {
  skin: number;
  clothes: number;
  person: number;
}

/**
 * Every AI result must cover at least as much of the body as the original
 * clothing: block if visible skin grows by more than [tolerance] (a share of
 * the person's area), or if the person is missing from the result.
 */
export function judgeCoverage(before: CoverageRatios, after: CoverageRatios, tolerance = 0.03): Verdict {
  if (after.person < 0.05) return { ok: false, reason: 'coverage' };
  if (after.skin > before.skin + tolerance) return { ok: false, reason: 'coverage' };
  return { ok: true };
}
