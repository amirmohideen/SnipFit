import { GoogleAuth } from 'google-auth-library';

export type Mode = 'women' | 'hijab' | 'men';

export interface TryOnInput {
  person: Buffer;
  personMime: string;
  garment: Buffer;
  garmentMime: string;
  mode: Mode;
  samples: number;
}

export interface TryOnOutput {
  images: Buffer[];
  provider: string;
  /** Images the model's own safety filters withheld. */
  filtered: number;
}

export class ProviderError extends Error {
  constructor(
    message: string,
    readonly retryable: boolean,
    readonly code: string,
  ) {
    super(message);
  }
}

/** The model sits behind this interface so it can be swapped. */
export interface TryOnProvider {
  readonly name: string;
  generate(input: TryOnInput): Promise<TryOnOutput>;
}

/**
 * Fixed instructions. Users never type prompts; they can't upload a mask or
 * choose what to remove. Only the target garment is replaced, and the result
 * must cover at least as much as the original clothing.
 */
export function fixedInstruction(mode: Mode): string {
  const garment =
    mode === 'hijab'
      ? 'the headscarf (hijab). Wrap the new scarf in the same style, keep the whole face visible and unchanged, and cover the hair, ears and neck at least as much as before'
      : 'the top or dress';
  return [
    'Edit the first image, a photo of a fully clothed adult.',
    `Replace only ${garment} with the garment shown in the second image, matching its color, pattern and fabric.`,
    "Keep the person's face, identity, body shape, skin, hair, pose and the background exactly as they are.",
    'The new garment must cover at least as much of the body as the original clothing. Never show more skin.',
    'Do not add, remove or change any other clothing or accessories. Produce one photorealistic image.',
  ].join(' ');
}

const auth = new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/cloud-platform'] });

function host(location: string) {
  return location === 'global' ? 'aiplatform.googleapis.com' : `${location}-aiplatform.googleapis.com`;
}

async function post<T>(url: string, data: unknown): Promise<T> {
  const client = await auth.getClient();
  try {
    const res = await client.request<T>({ url, method: 'POST', data, timeout: 240_000 });
    return res.data;
  } catch (e) {
    const status = (e as { response?: { status?: number } }).response?.status ?? 0;
    const retryable = status === 429 || status >= 500 || status === 0;
    throw new ProviderError(`model call failed (${status})`, retryable, `http_${status}`);
  }
}

/**
 * Vertex AI Virtual Try-On: one person photo + one garment photo in,
 * 1-4 images out. Default quota is about 50 requests/minute/project; the
 * task queue dispatches below that.
 */
export class VertexVirtualTryOn implements TryOnProvider {
  readonly name = 'vertex_vto';

  constructor(
    private readonly project: string,
    private readonly location: string,
    private readonly model: string,
  ) {}

  async generate(input: TryOnInput): Promise<TryOnOutput> {
    const url = `https://${host(this.location)}/v1/projects/${this.project}/locations/${this.location}/publishers/google/models/${this.model}:predict`;
    const data = await post<{ predictions?: { bytesBase64Encoded?: string; raiFilteredReason?: string }[] }>(url, {
      instances: [
        {
          personImage: { image: { bytesBase64Encoded: input.person.toString('base64') } },
          productImages: [{ image: { bytesBase64Encoded: input.garment.toString('base64') } }],
        },
      ],
      parameters: {
        sampleCount: input.samples,
        personGeneration: 'allow_adult',
        safetySetting: 'block_low_and_above',
        addWatermark: true,
        outputOptions: { mimeType: 'image/png' },
      },
    });
    const predictions = data.predictions ?? [];
    const images = predictions.filter((p) => p.bytesBase64Encoded).map((p) => Buffer.from(p.bytesBase64Encoded!, 'base64'));
    return { images, provider: this.name, filtered: Math.max(0, input.samples - images.length) };
  }
}

/**
 * Fallback for hijabs if Virtual Try-On handles them poorly: a Gemini image
 * model with the fixed instruction above. Switched per mode in Remote Config.
 */
export class GeminiImageEdit implements TryOnProvider {
  readonly name = 'gemini';

  constructor(
    private readonly project: string,
    private readonly location: string,
    private readonly model: string,
  ) {}

  async generate(input: TryOnInput): Promise<TryOnOutput> {
    const url = `https://${host(this.location)}/v1/projects/${this.project}/locations/${this.location}/publishers/google/models/${this.model}:generateContent`;
    const images: Buffer[] = [];
    let filtered = 0;
    for (let i = 0; i < input.samples; i++) {
      const data = await post<{
        candidates?: { finishReason?: string; content?: { parts?: { inlineData?: { data?: string } }[] } }[];
        promptFeedback?: { blockReason?: string };
      }>(url, {
        contents: [
          {
            role: 'user',
            parts: [
              { inlineData: { mimeType: input.personMime, data: input.person.toString('base64') } },
              { inlineData: { mimeType: input.garmentMime, data: input.garment.toString('base64') } },
              { text: fixedInstruction(input.mode) },
            ],
          },
        ],
        generationConfig: { responseModalities: ['IMAGE'], candidateCount: 1 },
        safetySettings: [
          { category: 'HARM_CATEGORY_SEXUALLY_EXPLICIT', threshold: 'BLOCK_LOW_AND_ABOVE' },
          { category: 'HARM_CATEGORY_HARASSMENT', threshold: 'BLOCK_LOW_AND_ABOVE' },
          { category: 'HARM_CATEGORY_DANGEROUS_CONTENT', threshold: 'BLOCK_LOW_AND_ABOVE' },
          { category: 'HARM_CATEGORY_HATE_SPEECH', threshold: 'BLOCK_LOW_AND_ABOVE' },
        ],
      });
      const part = data.candidates?.[0]?.content?.parts?.find((p) => p.inlineData?.data);
      if (part?.inlineData?.data) {
        images.push(Buffer.from(part.inlineData.data, 'base64'));
      } else {
        filtered++;
      }
    }
    return { images, provider: this.name, filtered };
  }
}
