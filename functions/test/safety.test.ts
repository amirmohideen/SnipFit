import { crc32, deflateSync, inflateSync } from 'node:zlib';
import { describe, expect, it } from 'vitest';

import { DIGITAL_SOURCE_TYPE, embedXmpInJpeg, embedXmpInPng } from '../src/provenance/xmp.js';
import { fixedInstruction } from '../src/tryon/providers.js';
import type { ImageAnalysis } from '../src/safety/verdicts.js';
import { judgeCoverage, judgeImage } from '../src/safety/verdicts.js';

const clean: ImageAnalysis = {
  safeSearch: { adult: 'VERY_UNLIKELY', racy: 'UNLIKELY', violence: 'VERY_UNLIKELY' },
  labels: [{ description: 'Sleeve', score: 0.9 }, { description: 'Dress', score: 0.85 }],
};

describe('image safety', () => {
  it('passes ordinary clothed photos', () => {
    expect(judgeImage(clean)).toEqual({ ok: true });
  });

  it('blocks adult, racy and violent content at LIKELY or above', () => {
    expect(judgeImage({ ...clean, safeSearch: { ...clean.safeSearch, adult: 'LIKELY' } })).toEqual({ ok: false, reason: 'adult' });
    expect(judgeImage({ ...clean, safeSearch: { ...clean.safeSearch, racy: 'VERY_LIKELY' } })).toEqual({ ok: false, reason: 'racy' });
    expect(judgeImage({ ...clean, safeSearch: { ...clean.safeSearch, violence: 'LIKELY' } })).toEqual({ ok: false, reason: 'violence' });
  });

  it('allows POSSIBLE racy (e.g. a sleeveless top) but nothing above', () => {
    expect(judgeImage({ ...clean, safeSearch: { ...clean.safeSearch, racy: 'POSSIBLE' } }).ok).toBe(true);
  });

  it('rejects swimwear, underwear and lingerie as garments or reference outfits', () => {
    for (const d of ['Swimwear', 'Lingerie', 'Brassiere', 'Undergarment', 'Bikini']) {
      expect(judgeImage({ ...clean, labels: [{ description: d, score: 0.8 }] })).toEqual({ ok: false, reason: 'restricted_garment' });
    }
    // Low-confidence labels don't block.
    expect(judgeImage({ ...clean, labels: [{ description: 'Swimwear', score: 0.3 }] }).ok).toBe(true);
  });
});

describe('coverage check', () => {
  const before = { skin: 0.18, clothes: 0.62, person: 0.4 };
  it('accepts results that cover at least as much', () => {
    expect(judgeCoverage(before, { skin: 0.17, clothes: 0.64, person: 0.41 }).ok).toBe(true);
    expect(judgeCoverage(before, { skin: 0.2, clothes: 0.6, person: 0.4 }).ok).toBe(true); // within tolerance
  });
  it('blocks results that show more skin', () => {
    expect(judgeCoverage(before, { skin: 0.3, clothes: 0.5, person: 0.4 })).toEqual({ ok: false, reason: 'coverage' });
  });
  it('blocks results with no person', () => {
    expect(judgeCoverage(before, { skin: 0, clothes: 0, person: 0.01 }).ok).toBe(false);
  });
});

describe('fixed instructions', () => {
  it('never lets clothing be removed and keeps the person unchanged', () => {
    for (const mode of ['women', 'hijab', 'men'] as const) {
      const text = fixedInstruction(mode);
      expect(text).toContain('cover at least as much');
      expect(text).toContain('Never show more skin');
    }
    expect(fixedInstruction('hijab')).toContain('face visible');
  });
});

describe('AI provenance', () => {
  it('embeds the IPTC trainedAlgorithmicMedia marker in a JPEG', () => {
    const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xdb, 0x00, 0x02, 0xff, 0xd9]);
    const out = embedXmpInJpeg(jpeg);
    expect(out[0]).toBe(0xff);
    expect(out[1]).toBe(0xd8);
    expect(out[3]).toBe(0xe1);
    expect(out.toString('latin1')).toContain(DIGITAL_SOURCE_TYPE);
  });

  it('embeds an iTXt XMP chunk after IHDR in a PNG, leaving image data intact', () => {
    const chunk = (type: string, data: Buffer) => {
      const len = Buffer.alloc(4);
      len.writeUInt32BE(data.length);
      const body = Buffer.concat([Buffer.from(type, 'latin1'), data]);
      const crc = Buffer.alloc(4);
      crc.writeUInt32BE(crc32(body) >>> 0);
      return Buffer.concat([len, body, crc]);
    };
    const ihdr = Buffer.alloc(13);
    ihdr.writeUInt32BE(1, 0);
    ihdr.writeUInt32BE(1, 4);
    ihdr[8] = 8; // bit depth
    ihdr[9] = 6; // RGBA
    const idat = chunk('IDAT', deflateSync(Buffer.from([0, 255, 0, 0, 255])));
    const png = Buffer.concat([
      Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      chunk('IHDR', ihdr),
      idat,
      chunk('IEND', Buffer.alloc(0)),
    ]);
    const out = embedXmpInPng(png);
    expect(out.subarray(0, 33).equals(png.subarray(0, 33))).toBe(true);
    expect(out.subarray(37, 41).toString('latin1')).toBe('iTXt');
    expect(out.toString('utf8')).toContain(DIGITAL_SOURCE_TYPE);
    // The iTXt chunk's CRC is valid.
    const itxtLen = out.readUInt32BE(33);
    const itxtCrc = out.readUInt32BE(33 + 8 + itxtLen);
    expect(itxtCrc).toBe(crc32(out.subarray(37, 41 + itxtLen)) >>> 0);
    // The image data chunk is unchanged.
    expect(out.includes(idat)).toBe(true);
    expect(inflateSync(out.subarray(out.indexOf(Buffer.from('IDAT')) + 4, out.indexOf(Buffer.from('IDAT')) + 4 + idat.length - 12))).toEqual(
      Buffer.from([0, 255, 0, 0, 255]),
    );
  });
});
