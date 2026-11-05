import { GoogleAuth } from 'google-auth-library';

import type { CoverageRatios, ImageAnalysis, Likelihood } from './verdicts.js';

const auth = new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/cloud-platform'] });

/** Cloud Vision SafeSearch + labels for each image (images are sent inline, never stored). */
export async function analyzeImages(images: Buffer[]): Promise<ImageAnalysis[]> {
  const client = await auth.getClient();
  const res = await client.request<{
    responses: {
      safeSearchAnnotation?: Record<string, Likelihood>;
      labelAnnotations?: { description: string; score: number }[];
      error?: { message: string };
    }[];
  }>({
    url: 'https://vision.googleapis.com/v1/images:annotate',
    method: 'POST',
    data: {
      requests: images.map((b) => ({
        image: { content: b.toString('base64') },
        features: [{ type: 'SAFE_SEARCH_DETECTION' }, { type: 'LABEL_DETECTION', maxResults: 30 }],
      })),
    },
  });
  return res.data.responses.map((r) => {
    if (r.error) throw new Error(`vision: ${r.error.message}`);
    const s = r.safeSearchAnnotation ?? {};
    return {
      safeSearch: {
        adult: s.adult ?? 'UNKNOWN',
        racy: s.racy ?? 'UNKNOWN',
        violence: s.violence ?? 'UNKNOWN',
      },
      labels: r.labelAnnotations ?? [],
    };
  });
}

/**
 * Skin/clothing shares measured by the `coverage` service (functions-python),
 * which runs the same multi-class selfie segmenter as the app.
 */
export async function measureCoverage(
  url: string,
  token: string,
  before: Buffer,
  after: Buffer[],
): Promise<{ before: CoverageRatios; after: CoverageRatios[] }> {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ before: before.toString('base64'), after: after.map((b) => b.toString('base64')) }),
    signal: AbortSignal.timeout(60_000),
  });
  if (!res.ok) throw new Error(`coverage service ${res.status}`);
  return (await res.json()) as { before: CoverageRatios; after: CoverageRatios[] };
}
