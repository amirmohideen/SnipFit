// This directory holds tests that the analyzer doesn't classify as tests.
// ignore_for_file: invalid_use_of_visible_for_testing_member

// Renders key screens and real share outputs to docs/screenshots/ so the
// design can be reviewed without a device. Not part of the regular suite.
//
//   ./tool/test.sh test_screens --update-goldens
//
// The cutout flow below is synthetic (a drawn portrait instead of a camera
// photo) but runs the real pipeline: mask building with the no-skin
// invariant, cutout, live-window compositing over the demo fabrics, color
// sampling, and the share renderers with watermark and swatch.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snipfit/core/images/image_utils.dart';
import 'package:snipfit/core/storage/local_store.dart';
import 'package:snipfit/core/storage/media_store.dart';
import 'package:snipfit/design/theme.dart';
import 'package:snipfit/features/cutout/cutout_controller.dart';
import 'package:snipfit/features/cutout/mask/hijab_template.dart';
import 'package:snipfit/features/cutout/mask/mask_builder.dart';
import 'package:snipfit/features/cutout/mask/photo_checks.dart';
import 'package:snipfit/features/cutout/mask/types.dart';
import 'package:snipfit/features/cutout/refine/refine_screen.dart';
import 'package:snipfit/features/home/home_screen.dart';
import 'package:snipfit/features/live_window/compositor.dart';
import 'package:snipfit/features/modes/app_mode.dart';
import 'package:snipfit/features/onboarding/onboarding_screens.dart';
import 'package:snipfit/features/paywall/paywall_screen.dart';
import 'package:snipfit/features/paywall/purchases_service.dart';
import 'package:snipfit/features/settings/settings_screen.dart';
import 'package:snipfit/features/share/contour.dart';
import 'package:snipfit/features/share/renderers.dart';
import 'package:snipfit/features/share/reveal_video.dart';
import 'package:snipfit/features/share/watermark.dart';
import 'package:snipfit/l10n/l10n.dart';

import '../test/widget/paywall_test.dart' show FakePurchases;

const _out = '../docs/screenshots';

Future<void> _loadFonts() async {
  final jakarta = FontLoader('PlusJakartaSans');
  final plex = FontLoader('IBMPlexSansArabic');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    jakarta.addFont(rootBundle.load('assets/fonts/PlusJakartaSans-$w.ttf'));
    plex.addFont(rootBundle.load('assets/fonts/IBMPlexSansArabic-$w.ttf'));
  }
  final icons = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await Future.wait([jakarta.load(), plex.load(), icons.load()]);
}

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  List<Override> overrides = const [],
  Locale locale = const Locale('en'),
  bool dark = false,
  Map<String, Object> prefs = const {},
  Duration settle = const Duration(milliseconds: 600),
}) async {
  tester.view.physicalSize = const Size(780, 1688);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  final store = await LocalStore.open();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(store), ...overrides],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: SnipTheme.light(locale),
        darkTheme: SnipTheme.dark(locale),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        locale: locale,
        supportedLocales: supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: screen,
      ),
    ),
  );
  await tester.pump(settle);
  await tester.pump(settle);
}

/// A drawn portrait whose pixels match a class map, at [w] x [h].
({LabelMap labels, FaceGeometry face, Uint8List rgba}) _portrait(int w, int h) {
  final labels = Uint8List(w * h);
  final conf = Uint8List(w * h)..fillRange(0, w * h, 235);
  final rgba = Uint8List(w * h * 4);
  final cx = w / 2, cy = h * 0.33;
  final fw = w * 0.15, fh = w * 0.2;
  const colors = {
    SegClass.background: [214, 210, 204],
    SegClass.hair: [58, 40, 32],
    SegClass.faceSkin: [214, 168, 138],
    SegClass.bodySkin: [206, 160, 130],
    SegClass.clothes: [96, 102, 112],
  };
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final dx = (x - cx) / fw, dy = (y - cy) / fh;
      final hx = (x - cx) / (fw * 1.35), hy = (y - (cy - fh * 0.25)) / (fh * 1.3);
      final neck = (x - cx).abs() < fw * 0.48 && y > cy + fh * 0.8 && y < cy + fh * 1.45;
      final shoulders = y >= cy + fh * 1.45 && (x - cx).abs() < w * 0.4 + (y - (cy + fh * 1.45)) * 0.25;
      int c;
      if (dx * dx + dy * dy <= 1) {
        c = SegClass.faceSkin;
      } else if (hx * hx + hy * hy <= 1 && y < cy + fh * 0.4) {
        c = SegClass.hair;
      } else if (neck) {
        c = SegClass.bodySkin;
      } else if (shoulders) {
        c = SegClass.clothes;
      } else {
        c = SegClass.background;
      }
      labels[i] = c;
      final base = colors[c]!;
      final shade = 1 - 0.12 * ((x - cx).abs() / w) - (c == SegClass.background ? 0.05 * y / h : 0);
      for (var k = 0; k < 3; k++) {
        rgba[i * 4 + k] = (base[k] * shade).round().clamp(0, 255);
      }
      rgba[i * 4 + 3] = 255;
    }
  }
  final face = FaceGeometry(
    box: Rect.fromCenter(center: Offset(cx, cy), width: fw * 2, height: fh * 2),
    eyeA: Offset(cx - fw * 0.42, cy - fh * 0.12),
    eyeB: Offset(cx + fw * 0.42, cy - fh * 0.12),
    oval: [
      for (var k = 0; k < 36; k++) Offset(cx + fw * math.cos(2 * math.pi * k / 36), cy + fh * math.sin(2 * math.pi * k / 36)),
    ],
  );
  return (labels: LabelMap(width: w, height: h, labels: labels, confidence: conf), face: face, rgba: rgba);
}

/// Window outline the way ExportService computes it.
List<Offset> _contour(Uint8List cutoutRgba, int w, int h) {
  final grid = Uint8List(w * h);
  for (var i = 0; i < grid.length; i++) {
    grid[i] = cutoutRgba[i * 4 + 3] < 128 ? 1 : 0;
  }
  return traceOuterContour(grid, w, h);
}

class _FixedCutout extends CutoutController {
  _FixedCutout(this.session);

  final CutoutSession session;

  @override
  CutoutState build() => CutoutReady(session);
}

Future<void> _writePng(ui.Image image, String name) async {
  final png = await ImageUtils.encodePng(image);
  await File('docs/screenshots/$name').writeAsBytes(png);
}

void main() {
  setUpAll(_loadFonts);
  const offer = PaywallOffer(
    yearly: Plan(
      kind: PlanKind.yearly,
      productId: 'snipfit_pro_yearly',
      title: 'Snipfit Pro Yearly',
      priceString: r'$29.99',
      period: PlanPeriod.year,
      monthlyEquivalentString: r'$2.49',
    ),
    monthly: Plan(kind: PlanKind.monthly, productId: 'snipfit_pro_monthly', title: 'Monthly', priceString: r'$4.99', period: PlanPeriod.month),
    credits: Plan(kind: PlanKind.credits, productId: 'snipfit_credits_20', title: 'Credits', priceString: r'$4.99', period: PlanPeriod.none),
  );

  testWidgets('01 welcome', (tester) async {
    await _pump(tester, const HookScreen(), settle: const Duration(milliseconds: 1200));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_out/01_welcome.png'));
  });

  testWidgets('02 age', (tester) async {
    await _pump(tester, const AgeScreen());
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_out/02_age.png'));
  });

  testWidgets('03 terms', (tester) async {
    await _pump(tester, const TermsScreen());
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_out/03_terms.png'));
  });

  testWidgets('04 mode picker', (tester) async {
    await _pump(tester, const ModePickerScreen());
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_out/04_mode_picker.png'));
  });

  testWidgets('05 home (first run)', (tester) async {
    await _pump(tester, const HomeScreen(), overrides: [windowsProvider.overrideWith((ref) async => const [])]);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_out/05_home_empty.png'));
  });

  testWidgets('06 refine (hijab template on a synthetic portrait)', (tester) async {
    final p = _portrait(600, 800);
    late CutoutSession session;
    await tester.runAsync(() async {
      final image = await ImageUtils.fromRgba(p.rgba, 600, 800);
      final result = MaskBuilder.build(labels: p.labels, face: p.face, strategy: WindowStrategy.hijabTemplate);
      session = CutoutSession(
        photo: DecodedPhoto(image: image, rgba: p.rgba, width: 600, height: 800),
        mode: AppMode.hijab,
        someoneElse: false,
        face: p.face,
        labels: p.labels,
        checks: const PhotoCheckResult([]),
        result: result,
        strategy: WindowStrategy.hijabTemplate,
        style: HijabStyle.classicWrap,
        wearingDetected: false,
      );
    });
    await _pump(
      tester,
      const RefineScreen(),
      prefs: {'mode.current': 'hijab'},
      overrides: [cutoutControllerProvider.overrideWith(() => _FixedCutout(session))],
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_out/06_refine_hijab_template.png'));
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('07 paywall', (tester) async {
    await _pump(tester, const PaywallScreen(trigger: 'screenshot'), overrides: [purchasesServiceProvider.overrideWithValue(FakePurchases(offer: offer))]);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_out/07_paywall.png'));
  });

  testWidgets('08 paywall (dark)', (tester) async {
    await _pump(tester, const PaywallScreen(trigger: 'screenshot'), dark: true, overrides: [purchasesServiceProvider.overrideWithValue(FakePurchases(offer: offer))]);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_out/08_paywall_dark.png'));
  });

  testWidgets('09 settings', (tester) async {
    await _pump(tester, const SettingsScreen());
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_out/09_settings.png'));
  });

  testWidgets('10 terms in Arabic (right-to-left)', (tester) async {
    await _pump(tester, const TermsScreen(), locale: const Locale('ar'));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_out/10_terms_arabic_rtl.png'));
  });

  testWidgets('11 live window captures, compare collage, single result and reveal frames', (tester) async {
    await tester.runAsync(() async {
      // Women's mode cutout from the synthetic portrait.
      final p = _portrait(720, 960);
      final result = MaskBuilder.build(labels: p.labels, face: p.face, strategy: WindowStrategy.garment);
      final alpha = MaskBuilder.finalizeAlpha(result.window, result.skin, softness: 3);
      final cutoutRgba = ImageUtils.cutoutRgba(p.rgba, alpha.data);
      final cutout = await ImageUtils.fromRgba(cutoutRgba, 720, 960);
      final photo = await ImageUtils.fromRgba(p.rgba, 720, 960);
      const screen = Size(390, 844);
      final placement = CutoutPlacement(center: Offset(screen.width / 2, screen.height * 0.47), rotation: -0.04, width: screen.width * 0.86);
      const texts = ShareTexts(watermark: 'Made with Snipfit', whichOne: 'Which one?', aiLabel: 'AI-generated');

      final arts = <CaptureArt>[];
      ComposedCapture? first;
      ui.Image? firstScene;
      for (final fabric in ['fabric_rose_linen', 'fabric_sage_twill', 'fabric_navy_herringbone']) {
        final data = await rootBundle.load('assets/demo/$fabric.jpg');
        final scene = (await ImageUtils.decode(data.buffer.asUint8List(), maxSide: 1920)).image;
        final composed = await composeCapture(scene: scene, cutout: cutout, placement: placement, screen: screen);
        final composite = (await ImageUtils.decode(composed.compositeJpeg, maxSide: 2400)).image;
        arts.add(CaptureArt(composite: composite, fabricArgb: composed.fabricArgb, windowAlpha: null));
        if (first == null) {
          first = composed;
          firstScene = (await ImageUtils.decode(composed.sceneJpeg, maxSide: 2400)).image;
          await File('docs/screenshots/11_live_window_capture.jpg').writeAsBytes(composed.compositeJpeg);
        }
      }
      await _writePng(await renderSingle(arts.first, watermark: true, texts: texts), '12_share_single.png');
      await _writePng(await renderCollage(arts, watermark: true, texts: texts), '13_share_collage_story.png');
      await _writePng(await renderCollage(arts.take(2).toList(), watermark: true, texts: texts, square: true), '14_share_collage_square.png');

      final inputs = RevealInputs(
        photo: photo,
        cutout: cutout,
        scene: firstScene!,
        affine: first!.placement,
        compositeSize: Size(first.width.toDouble(), first.height.toDouble()),
        fabricArgb: first.fabricArgb,
        contour: _contour(cutoutRgba, 720, 960),
        watermark: true,
        texts: texts,
        watermarkCorner: Corner.topRight,
      );
      for (final t in [0.8, 2.4, 3.9, 6.0]) {
        await _writePng(await RevealVideo.poster(inputs, t: t), '15_reveal_t${t.toStringAsFixed(1)}.png');
      }
    });
  });
}
