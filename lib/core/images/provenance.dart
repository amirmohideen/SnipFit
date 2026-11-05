import 'dart:convert';
import 'dart:typed_data';

/// Machine-readable AI provenance for exported AI images: an XMP packet with
/// IPTC's DigitalSourceType "trainedAlgorithmicMedia", the standard marker
/// for AI-generated imagery. (The server adds the same packet, and the
/// try-on model adds its own SynthID watermark.) Nothing else is embedded:
/// no location, device or camera data.
abstract final class Provenance {
  static const digitalSourceType = 'http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia';

  static String xmpPacket({String description = 'AI-generated virtual try-on preview made with Snipfit'}) =>
      '<?xpacket begin="﻿" id="W5M0MpCehiHzreSzNTczkc9d"?>'
      '<x:xmpmeta xmlns:x="adobe:ns:meta/">'
      '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
      '<rdf:Description rdf:about="" '
      'xmlns:Iptc4xmpExt="http://iptc.org/std/Iptc4xmpExt/2008-02-29/" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" '
      'Iptc4xmpExt:DigitalSourceType="$digitalSourceType">'
      '<dc:description><rdf:Alt><rdf:li xml:lang="x-default">$description</rdf:li></rdf:Alt></dc:description>'
      '</rdf:Description></rdf:RDF></x:xmpmeta><?xpacket end="w"?>';

  /// Inserts the XMP APP1 segment right after the JPEG SOI marker.
  static Uint8List embedInJpeg(Uint8List jpeg) {
    if (jpeg.length < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) {
      throw const FormatException('Not a JPEG');
    }
    final header = ascii.encode('http://ns.adobe.com/xap/1.0/\u0000');
    final body = utf8.encode(xmpPacket());
    final len = 2 + header.length + body.length;
    if (len > 0xFFFF) throw const FormatException('XMP too large');
    final segment = BytesBuilder()
      ..add([0xFF, 0xE1, len >> 8, len & 0xFF])
      ..add(header)
      ..add(body);
    return (BytesBuilder()
          ..add(jpeg.sublist(0, 2))
          ..add(segment.takeBytes())
          ..add(jpeg.sublist(2)))
        .takeBytes();
  }

  /// True if [jpeg] carries our AI DigitalSourceType marker.
  static bool isMarkedAi(Uint8List jpeg) {
    final text = latin1.decode(jpeg.sublist(0, jpeg.length < 65536 ? jpeg.length : 65536), allowInvalid: true);
    return text.contains('trainedAlgorithmicMedia');
  }
}
