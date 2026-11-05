import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snipfit/features/cutout/mask/hijab_template.dart';
import 'package:snipfit/features/cutout/mask/label_map.dart';
import 'package:snipfit/features/cutout/mask/mask_builder.dart';
import 'package:snipfit/features/cutout/mask/mask_ops.dart';
import 'package:snipfit/features/cutout/mask/photo_checks.dart';
import 'package:snipfit/features/cutout/mask/types.dart';

/// A synthetic 300x400 portrait: face skin oval, hair cap, neck skin,
/// a top (clothes) below the neck, and background elsewhere.
({LabelMap labels, FaceGeometry face}) syntheticPortrait({
  bool hijab = false,
  bool glasses = false,
}) {
  const w = 300, h = 400;
  final labels = Uint8List(w * h);
  final conf = Uint8List(w * h)..fillRange(0, w * h, 230);
  const cx = 150.0, cy = 140.0; // face center
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final dx = (x - cx) / 45, dy = (y - cy) / 60;
      final inFace = dx * dx + dy * dy <= 1;
      final hx = (x - cx) / 62, hy = (y - (cy - 15)) / 80;
      final inHead = hx * hx + hy * hy <= 1;
      final inNeck = (x - cx).abs() < 22 && y > 195 && y < 235;
      final inTop = y >= 235 && (x - cx).abs() < 120 + (y - 235) * 0.3;
      final inHijab = hijab && !inFace && ((x - cx).abs() < 85 && y > 55 && y < 300);
      if (inFace) {
        labels[i] = SegClass.faceSkin;
      } else if (inHijab) {
        labels[i] = SegClass.clothes;
      } else if (inHead) {
        labels[i] = SegClass.hair;
      } else if (inNeck) {
        labels[i] = SegClass.bodySkin;
      } else if (inTop) {
        labels[i] = SegClass.clothes;
      } else {
        labels[i] = SegClass.background;
      }
      if (glasses && (y - 125).abs() < 6 && (x - cx).abs() < 38) {
        labels[i] = SegClass.other;
      }
    }
  }
  const face = FaceGeometry(
    box: Rect.fromLTRB(105, 80, 195, 200),
    eyeA: Offset(130, 125),
    eyeB: Offset(170, 125),
    nose: Offset(150, 150),
  );
  return (
    labels: LabelMap(width: w, height: h, labels: labels, confidence: conf),
    face: face,
  );
}

bool _noWindowOnSkin(Mask window, LabelMap labels) {
  for (var i = 0; i < window.data.length; i++) {
    final c = labels.labels[i];
    if (window.data[i] > 0 && (c == SegClass.faceSkin || c == SegClass.bodySkin)) {
      return false;
    }
  }
  return true;
}

void main() {
  group('MaskOps', () {
    test('dilate then erode restores a solid square', () {
      final m = Mask(50, 50);
      for (var y = 10; y < 40; y++) {
        for (var x = 10; x < 40; x++) {
          m.data[y * 50 + x] = 255;
        }
      }
      final grown = MaskOps.dilate(m, 3);
      expect(grown.area, 36 * 36);
      expect(MaskOps.erode(grown, 3).area, 30 * 30);
    });

    test('open removes isolated specks', () {
      final m = Mask(40, 40);
      m.data[5 * 40 + 5] = 255;
      for (var y = 15; y < 35; y++) {
        for (var x = 15; x < 35; x++) {
          m.data[y * 40 + x] = 255;
        }
      }
      final opened = MaskOps.open(m, 1);
      expect(opened.data[5 * 40 + 5], 0);
      expect(opened.area, 400);
    });

    test('fillHoles fills enclosed holes but not open bays', () {
      final m = Mask(30, 30);
      for (var y = 5; y < 25; y++) {
        for (var x = 5; x < 25; x++) {
          m.data[y * 30 + x] = 255;
        }
      }
      m.data[15 * 30 + 15] = 0; // enclosed hole
      final filled = MaskOps.fillHoles(m, 10);
      expect(filled.data[15 * 30 + 15], 255);
    });

    test('feathering never extends beyond the binary mask', () {
      final m = Mask(60, 60);
      MaskOps.paintDisc(m, 30, 30, 18, 255);
      for (final r in [1, 3, 6, 10]) {
        final soft = MaskOps.featherInward(m, r);
        for (var i = 0; i < m.data.length; i++) {
          if (m.data[i] == 0) expect(soft.data[i], 0, reason: 'r=$r i=$i');
        }
        expect(soft.data[30 * 60 + 30], 255);
      }
    });

    test('polygon rasterization fills a triangle', () {
      final m = MaskOps.rasterizePolygon(
        const [Offset(0, 0), Offset(20, 0), Offset(0, 20)],
        20,
        20,
      );
      expect(m.area, inInclusiveRange(180, 220));
    });

    test('keepMainComponents drops small islands', () {
      final m = Mask(60, 20);
      for (var y = 2; y < 18; y++) {
        for (var x = 2; x < 30; x++) {
          m.data[y * 60 + x] = 255;
        }
      }
      for (var y = 5; y < 7; y++) {
        for (var x = 50; x < 52; x++) {
          m.data[y * 60 + x] = 255;
        }
      }
      final kept = MaskOps.keepMainComponents(m, minFraction: 0.1);
      expect(kept.data[6 * 60 + 50], 0);
      expect(kept.data[10 * 60 + 10], 255);
    });
  });

  group('upsampleLabels', () {
    test('maps a 2-class probability split across the letterbox', () {
      const mw = 8, mh = 8;
      final data = Float32List(mw * mh * SegClass.count);
      for (var y = 0; y < mh; y++) {
        for (var x = 0; x < mw; x++) {
          final c = x < mw / 2 ? SegClass.hair : SegClass.clothes;
          data[(y * mw + x) * SegClass.count + c] = 1;
        }
      }
      final map = upsampleLabels(
        ClassProbabilities(width: mw, height: mh, data: data),
        64,
        64,
      );
      expect(map.at(5, 30), SegClass.hair);
      expect(map.at(60, 30), SegClass.clothes);
    });
  });

  group('MaskBuilder', () {
    test('garment window covers the top and never skin', () {
      final s = syntheticPortrait();
      final r = MaskBuilder.build(
        labels: s.labels,
        face: s.face,
        strategy: WindowStrategy.garment,
      );
      expect(r.window.area, greaterThan(5000));
      expect(_noWindowOnSkin(r.window, s.labels), isTrue);
      // Hair is not part of a garment window.
      expect(r.window.data[60 * 300 + 150], 0);
      // Chest is.
      expect(r.window.data[300 * 300 + 150], 255);
      expect(r.quality, greaterThan(0.5));
    });

    test('hijab (worn) window covers hair/scarf but not face, neck or glasses', () {
      final s = syntheticPortrait(hijab: true, glasses: true);
      final r = MaskBuilder.build(
        labels: s.labels,
        face: s.face,
        strategy: WindowStrategy.hijabWorn,
      );
      expect(r.window.area, greaterThan(3000));
      expect(_noWindowOnSkin(r.window, s.labels), isTrue);
      // Glasses (accessory class inside the face) stay untouched.
      expect(r.window.data[125 * 300 + 150], 0);
      // Scarf beside the face is in the window.
      expect(r.window.data[150 * 300 + 222], 255);
    });

    test('hijab template is aligned to the face and excludes all skin', () {
      final s = syntheticPortrait();
      for (final style in HijabStyle.values) {
        final r = MaskBuilder.build(
          labels: s.labels,
          face: s.face,
          strategy: WindowStrategy.hijabTemplate,
          style: style,
        );
        expect(r.templateControlPoints, isNotNull);
        expect(r.window.area, greaterThan(4000), reason: style.name);
        expect(_noWindowOnSkin(r.window, s.labels), isTrue, reason: style.name);
        // Above the forehead is covered by the template.
        expect(r.window.data[70 * 300 + 150], 255, reason: style.name);
      }
    });

    test('brush strokes over skin are removed by the safety pass', () {
      final s = syntheticPortrait();
      final r = MaskBuilder.build(
        labels: s.labels,
        face: s.face,
        strategy: WindowStrategy.garment,
      );
      final edited = r.window.copy();
      MaskOps.paintStroke(edited, const [Offset(120, 120), Offset(180, 160)], 20, 255);
      final safe = MaskBuilder.enforceNoSkin(edited, r.skin);
      expect(_noWindowOnSkin(safe, s.labels), isTrue);
      final alpha = MaskBuilder.finalizeAlpha(safe, r.skin, softness: 4);
      expect(_noWindowOnSkin(alpha, s.labels), isTrue);
    });
  });

  group('FaceFrame', () {
    test('round-trips points with rotation', () {
      const face = FaceGeometry(
        box: Rect.fromLTRB(0, 0, 100, 100),
        eyeA: Offset(40, 50),
        eyeB: Offset(70, 60),
      );
      final frame = FaceFrame(face);
      const p = Offset(1.5, -2);
      final back = frame.toFace(frame.toImage(p));
      expect(back.dx, closeTo(p.dx, 1e-9));
      expect(back.dy, closeTo(p.dy, 1e-9));
    });
  });

  group('photo checks', () {
    final luma = Uint8List(100 * 100)..fillRange(0, 100 * 100, 140);
    const face = FaceGeometry(
      box: Rect.fromLTRB(30, 20, 70, 70),
      eyeA: Offset(40, 40),
      eyeB: Offset(60, 40),
    );

    test('no face and multiple faces block', () {
      expect(
        checkPhoto(faces: const [], luma: luma, width: 100, height: 100).blocking,
        isTrue,
      );
      final two = checkPhoto(
        faces: const [face, face],
        luma: luma,
        width: 100,
        height: 100,
      );
      expect(two.primary, PhotoIssue.multipleFaces);
      expect(two.blocking, isTrue);
    });

    test('dark photo gives a light fix; good photo passes', () {
      final dark = Uint8List(100 * 100)..fillRange(0, 100 * 100, 30);
      expect(
        checkPhoto(faces: const [face], luma: dark, width: 100, height: 100).primary,
        PhotoIssue.tooDark,
      );
      expect(checkPhoto(faces: const [face], luma: luma, width: 100, height: 100).ok, isTrue);
    });

    test('turned head is flagged as not frontal', () {
      const turned = FaceGeometry(
        box: Rect.fromLTRB(30, 20, 70, 70),
        eyeA: Offset(40, 40),
        eyeB: Offset(60, 40),
        yaw: 35,
      );
      expect(
        checkPhoto(faces: const [turned], luma: luma, width: 100, height: 100).issues,
        contains(PhotoIssue.notFrontal),
      );
    });
  });
}
