import { crc32 } from 'node:zlib';

/**
 * Machine-readable AI provenance: an XMP packet with IPTC DigitalSourceType
 * "trainedAlgorithmicMedia" (the standard marker for AI-generated images).
 * The try-on model also adds its own SynthID watermark.
 */
export const DIGITAL_SOURCE_TYPE = 'http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia';

export function xmpPacket(description = 'AI-generated virtual try-on preview made with Snipfit'): string {
  return (
    '<?xpacket begin="﻿" id="W5M0MpCehiHzreSzNTczkc9d"?>' +
    '<x:xmpmeta xmlns:x="adobe:ns:meta/">' +
    '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">' +
    '<rdf:Description rdf:about="" ' +
    'xmlns:Iptc4xmpExt="http://iptc.org/std/Iptc4xmpExt/2008-02-29/" ' +
    'xmlns:dc="http://purl.org/dc/elements/1.1/" ' +
    `Iptc4xmpExt:DigitalSourceType="${DIGITAL_SOURCE_TYPE}">` +
    `<dc:description><rdf:Alt><rdf:li xml:lang="x-default">${description}</rdf:li></rdf:Alt></dc:description>` +
    '</rdf:Description></rdf:RDF></x:xmpmeta><?xpacket end="w"?>'
  );
}

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

/** Adds an iTXt "XML:com.adobe.xmp" chunk right after IHDR. */
export function embedXmpInPng(png: Buffer, xmp = xmpPacket()): Buffer {
  if (!png.subarray(0, 8).equals(PNG_SIGNATURE)) throw new Error('not a PNG');
  const ihdrLen = png.readUInt32BE(8);
  const afterIhdr = 8 + 12 + ihdrLen;
  const data = Buffer.concat([
    Buffer.from('XML:com.adobe.xmp', 'latin1'),
    Buffer.from([0, 0, 0]), // null separator, compression flag, method
    Buffer.from([0]), // empty language tag
    Buffer.from([0]), // empty translated keyword
    Buffer.from(xmp, 'utf8'),
  ]);
  const type = Buffer.from('iTXt', 'latin1');
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([type, data])) >>> 0);
  return Buffer.concat([png.subarray(0, afterIhdr), len, type, data, crc, png.subarray(afterIhdr)]);
}

/** Adds an XMP APP1 segment right after the JPEG SOI marker. */
export function embedXmpInJpeg(jpeg: Buffer, xmp = xmpPacket()): Buffer {
  if (jpeg[0] !== 0xff || jpeg[1] !== 0xd8) throw new Error('not a JPEG');
  const header = Buffer.from('http://ns.adobe.com/xap/1.0/\0', 'latin1');
  const body = Buffer.from(xmp, 'utf8');
  const len = 2 + header.length + body.length;
  const seg = Buffer.concat([Buffer.from([0xff, 0xe1, len >> 8, len & 0xff]), header, body]);
  return Buffer.concat([jpeg.subarray(0, 2), seg, jpeg.subarray(2)]);
}

export function embedXmp(image: Buffer): Buffer {
  return image.subarray(0, 8).equals(PNG_SIGNATURE) ? embedXmpInPng(image) : embedXmpInJpeg(image);
}
