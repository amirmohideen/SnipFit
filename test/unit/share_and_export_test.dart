import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:snipfit/core/analytics/analytics_events.dart';
import 'package:snipfit/core/images/image_utils.dart';
import 'package:snipfit/core/images/provenance.dart';
import 'package:snipfit/features/invite/invite_links.dart';
import 'package:snipfit/features/live_window/compositor.dart';
import 'package:snipfit/features/modes/app_mode.dart';
import 'package:snipfit/features/paywall/entitlements.dart';
import 'package:snipfit/features/share/contour.dart';
import 'package:snipfit/features/share/watermark.dart';

void main() {
  group('exports carry no metadata', () {
    test('re-encoded JPEGs have no EXIF segment', () {
      final rgba = Uint8List(16 * 16 * 4)..fillRange(0, 16 * 16 * 4, 200);
      final jpeg = ImageUtils.encodeJpegSync(rgba, 16, 16);
      expect(jpeg[0], 0xFF);
      expect(jpeg[1], 0xD8);
      expect(ImageUtils.hasExif(jpeg), isFalse);
    });

    test('AI images get the IPTC trainedAlgorithmicMedia marker', () {
      final rgba = Uint8List(8 * 8 * 4)..fillRange(0, 8 * 8 * 4, 90);
      final jpeg = ImageUtils.encodeJpegSync(rgba, 8, 8);
      expect(Provenance.isMarkedAi(jpeg), isFalse);
      final marked = Provenance.embedInJpeg(jpeg);
      expect(Provenance.isMarkedAi(marked), isTrue);
      expect(ImageUtils.hasExif(marked), isFalse);
      expect(marked.sublist(0, 2), [0xFF, 0xD8]);
    });

    test('hasExif detects a real EXIF APP1 segment', () {
      final exif = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x08, 0x45, 0x78, 0x69, 0x66, 0x00, 0x00, 0xFF, 0xD9]);
      expect(ImageUtils.hasExif(exif), isTrue);
    });
  });

  group('fabric color', () {
    test('averages opaque pixels and ignores highlights and shadows', () {
      final px = <int>[];
      for (var i = 0; i < 80; i++) {
        px.addAll([180, 60, 60, 255]);
      }
      for (var i = 0; i < 10; i++) {
        px.addAll([255, 255, 255, 255]); // specular highlight
        px.addAll([0, 0, 0, 255]); // shadow
        px.addAll([0, 200, 0, 0]); // transparent: outside the window
      }
      expect(hexOf(averageOpaqueColor(Uint8List.fromList(px))), '#B43C3C');
    });

    test('hex codes are uppercase and zero-padded', () {
      expect(hexOf(0xFF00A1B2), '#00A1B2');
    });
  });

  group('watermark placement', () {
    test('avoids the corner with fabric and skips blocked corners', () {
      const w = 10, h = 10;
      final grid = Uint8List(w * h);
      // Fabric fills the bottom half.
      for (var y = 5; y < h; y++) {
        for (var x = 0; x < w; x++) {
          grid[y * w + x] = 255;
        }
      }
      final c = chooseCorner(avoid: grid, gridW: w, gridH: h, boxW: 0.4, boxH: 0.2, blocked: const {Corner.bottomLeft});
      expect(c, Corner.topRight);
    });
  });

  group('reveal contour', () {
    test('traces a closed outline around the largest region', () {
      const w = 20, h = 20;
      final grid = Uint8List(w * h);
      for (var y = 5; y < 15; y++) {
        for (var x = 4; x < 16; x++) {
          grid[y * w + x] = 1;
        }
      }
      grid[1 * w + 1] = 1; // a stray pixel elsewhere
      final pts = traceOuterContour(grid, w, h);
      expect(pts.length, greaterThan(30));
      for (final p in pts) {
        expect(p.dx, inInclusiveRange(4, 15));
        expect(p.dy, inInclusiveRange(5, 14));
      }
    });
  });

  group('invite links', () {
    test('are on our domain, carry the mode, and use a stable short code', () {
      final links = InviteLinks(domain: 'snipfit.app', seed: 'uid-123');
      final uri = links.link(AppMode.hijab);
      expect(uri.host, 'snipfit.app');
      expect(uri.pathSegments.first, 'i');
      expect(uri.queryParameters['m'], 'hijab');
      expect(InviteLinks.codeFor('uid-123'), InviteLinks.codeFor('uid-123'));
      expect(InviteLinks.codeFor('uid-123'), isNot(InviteLinks.codeFor('uid-124')));
      expect(InviteLinks.codeFor('uid-123'), hasLength(8));
      expect(InviteLinks.parse(uri)?.mode, AppMode.hijab);
      expect(InviteLinks.parse(Uri.parse('https://snipfit.app/legal/terms')), isNull);
    });
  });

  group('analytics properties', () {
    test('drop anything that is not allow-listed', () {
      final cleaned = AnalyticsPropertyFilter.clean({
        AnalyticsProps.mode: 'hijab',
        AnalyticsProps.quality: 0.82,
        'email': 'someone@example.com',
        'name': 'Someone',
        AnalyticsProps.source: 'x' * 200,
      });
      expect(cleaned, {AnalyticsProps.mode: 'hijab', AnalyticsProps.quality: 0.82});
    });
  });

  group('ledger snapshot', () {
    test('available try-ons subtract reserved credits and count Pro allowance', () {
      final snap = LedgerSnapshot.fromDoc({
        'credits': {'balance': 5, 'reserved': 1},
        'allowance': {'limit': 30, 'used': 12},
        'pro': {'active': true},
      });
      expect(snap.credits, 4);
      expect(snap.allowanceLeft, 18);
      expect(snap.proActive, isTrue);
      expect(LedgerSnapshot.fromDoc(null).credits, 0);
    });
  });
}
