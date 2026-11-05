import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics.dart';
import '../../core/analytics/analytics_events.dart';
import '../../core/images/image_utils.dart';
import '../../core/storage/local_store.dart';
import '../../core/storage/media_store.dart';
import '../../design/tokens.dart';
import '../../design/widgets/camera_controls.dart';
import '../../design/widgets/common.dart';
import '../../l10n/l10n.dart';
import 'compositor.dart';

const demoFabrics = [
  'assets/demo/fabric_rose_linen.jpg',
  'assets/demo/fabric_sage_twill.jpg',
  'assets/demo/fabric_navy_herringbone.jpg',
];

/// Full-screen rear camera with the cutout floating on top. Segmentation
/// already happened; this screen only composites, so it stays smooth.
class LiveWindowScreen extends ConsumerStatefulWidget {
  const LiveWindowScreen({required this.windowId, this.practice = false, super.key});

  final String windowId;

  /// Onboarding practice: a 3-step overlay and the demo fabric offer.
  final bool practice;

  @override
  ConsumerState<LiveWindowScreen> createState() => _LiveWindowScreenState();
}

class _LiveWindowScreenState extends ConsumerState<LiveWindowScreen> with WidgetsBindingObserver {
  CameraController? _camera;
  bool _cameraUnavailable = false;
  ui.Image? _cutout;
  ui.Image? _demo;
  int _demoIndex = 0;
  bool _useDemo = false;

  CutoutPlacement? _placement;
  CutoutPlacement? _gestureStart;
  Offset _gestureFocal = Offset.zero;
  bool _locked = false;
  bool _torch = false;
  bool _exposureLocked = false;
  bool _busy = false;
  bool _tipVisible = false;
  int _practiceStep = 0;
  Offset? _focusRing;
  Size _screen = Size.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tipVisible = !ref.read(localStoreProvider).getBool(Keys.freshSelfieTipDismissed);
    if (widget.practice) ref.read(localStoreProvider).setBool(Keys.onboardingDone, true);
    _loadCutout();
    _initCamera();
    ref.read(analyticsProvider).track(AnalyticsEvents.liveWindowOpened, {
      AnalyticsProps.source: widget.practice ? 'practice' : 'window',
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    _cutout?.dispose();
    _demo?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      final c = _camera;
      _camera = null;
      c?.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _camera == null && !_useDemo) {
      _initCamera();
    }
  }

  Future<void> _loadCutout() async {
    final file = ref.read(mediaStoreProvider).cutoutFile(widget.windowId);
    if (!await file.exists()) return;
    final decoded = await ImageUtils.decode(await file.readAsBytes(), maxSide: 2048);
    if (!mounted) {
      decoded.dispose();
      return;
    }
    setState(() => _cutout = decoded.image);
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.where((c) => c.lensDirection == CameraLensDirection.back).firstOrNull ?? cameras.firstOrNull;
      if (back == null) throw CameraException('NoCamera', null);
      final c = CameraController(back, ResolutionPreset.veryHigh, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await c.initialize();
      await c.setFlashMode(FlashMode.off);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _camera = c;
        _cameraUnavailable = false;
      });
    } on CameraException {
      if (!mounted) return;
      setState(() => _cameraUnavailable = true);
      await _setDemo(true);
    }
  }

  Future<void> _setDemo(bool on) async {
    if (on && _demo == null) {
      final data = await rootBundle.load(demoFabrics[_demoIndex]);
      final decoded = await ImageUtils.decode(data.buffer.asUint8List(), maxSide: 1920);
      _demo = decoded.image;
    }
    if (!mounted) return;
    setState(() => _useDemo = on);
  }

  Future<void> _nextDemo() async {
    _demoIndex = (_demoIndex + 1) % demoFabrics.length;
    _demo?.dispose();
    _demo = null;
    await _setDemo(true);
  }

  CutoutPlacement _initialPlacement(Size screen) =>
      CutoutPlacement(center: Offset(screen.width / 2, screen.height * 0.44), rotation: 0, width: screen.width * 0.82);

  void _onScaleStart(ScaleStartDetails d) {
    if (_locked || _placement == null) return;
    _gestureStart = _placement;
    _gestureFocal = d.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final start = _gestureStart;
    if (_locked || start == null) return;
    setState(() {
      _placement = start.copyWith(
        center: start.center + (d.focalPoint - _gestureFocal),
        width: (start.width * d.scale).clamp(_screen.width * 0.25, _screen.width * 3),
        rotation: start.rotation + d.rotation,
      );
    });
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_gestureStart != null && widget.practice && _practiceStep == 1) {
      setState(() => _practiceStep = 2);
    }
    _gestureStart = null;
  }

  Future<void> _onTapFocus(TapUpDetails d) async {
    final c = _camera;
    if (c == null || _useDemo) return;
    final preview = c.value.previewSize;
    if (preview == null) return;
    // Map the tap through the cover-fit crop into normalized preview space.
    final crop = coverCrop(Size(preview.height, preview.width), _screen);
    final x = (crop.left + d.localPosition.dx / _screen.width * crop.width) / preview.height;
    final y = (crop.top + d.localPosition.dy / _screen.height * crop.height) / preview.width;
    final p = Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
    setState(() => _focusRing = d.localPosition);
    Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _focusRing = null);
    });
    try {
      await c.setFocusPoint(p);
      await c.setExposurePoint(p);
    } on CameraException {
      // Not every lens supports metering points.
    }
  }

  Future<void> _toggleTorch() async {
    final c = _camera;
    if (c == null) return;
    try {
      await c.setFlashMode(_torch ? FlashMode.off : FlashMode.torch);
      setState(() => _torch = !_torch);
    } on CameraException {
      if (mounted) showSnack(context, context.l10n.torchUnavailable);
    }
  }

  Future<void> _toggleExposureLock() async {
    final c = _camera;
    if (c == null) return;
    try {
      final lock = !_exposureLocked;
      await c.setExposureMode(lock ? ExposureMode.locked : ExposureMode.auto);
      await c.setFocusMode(lock ? FocusMode.locked : FocusMode.auto);
      setState(() => _exposureLocked = lock);
      if (mounted) showSnack(context, lock ? context.l10n.exposureLocked : context.l10n.exposureUnlocked);
    } on CameraException {
      // Unsupported on this lens.
    }
  }

  Future<void> _capture() async {
    final cutout = _cutout;
    final placement = _placement;
    if (cutout == null || placement == null || _busy) return;
    setState(() => _busy = true);
    HapticFeedback.lightImpact();
    try {
      ui.Image scene;
      if (_useDemo || _camera == null) {
        scene = _demo!;
      } else {
        final shot = await _camera!.takePicture();
        final bytes = await File(shot.path).readAsBytes();
        unawaited(File(shot.path).delete().catchError((_) => File(shot.path)));
        scene = (await ImageUtils.decode(bytes, maxSide: 1920)).image;
      }
      final composed = await composeCapture(scene: scene, cutout: cutout, placement: placement, screen: _screen);
      if (!identical(scene, _demo)) scene.dispose();

      final record = CaptureRecord(
        id: MediaStore.newId(),
        windowId: widget.windowId,
        createdAt: DateTime.now(),
        fabricArgb: composed.fabricArgb,
        width: composed.width,
        height: composed.height,
        placement: composed.placement,
      );
      await ref.read(mediaStoreProvider).saveCapture(record, compositeJpeg: composed.compositeJpeg, sceneJpeg: composed.sceneJpeg);
      ref.read(mediaRevisionProvider.notifier).bump();
      await ref.read(localStoreProvider).setBool(Keys.firstCompareDone, true);
      await ref.read(analyticsProvider).track(AnalyticsEvents.compareSaved, {AnalyticsProps.source: _useDemo ? 'demo' : 'camera'});
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      if (widget.practice && _practiceStep == 2) {
        setState(() => _practiceStep = 3);
        await ref.read(localStoreProvider).setBool(Keys.practiceDone, true);
        if (!mounted) return;
      }
      showSnack(context, context.l10n.captureSaved(composed.fabricArgb.hex));
    } on Object {
      if (mounted) showSnack(context, context.l10n.genericError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _dismissTip() {
    setState(() => _tipVisible = false);
    ref.read(localStoreProvider).setBool(Keys.freshSelfieTipDismissed, true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final captures = ref.watch(capturesProvider(widget.windowId)).value ?? const [];
    final c = _camera;
    final cameraReady = c != null && c.value.isInitialized && !_useDemo;

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          _screen = constraints.biggest;
          _placement ??= _initialPlacement(_screen);
          return Stack(
            fit: StackFit.expand,
            children: [
              if (cameraReady)
                ClipRect(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: c.value.previewSize!.height,
                      height: c.value.previewSize!.width,
                      child: CameraPreview(c),
                    ),
                  ),
                )
              else if (_useDemo && _demo != null)
                RawImage(image: _demo, fit: BoxFit.cover),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: _onTapFocus,
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                onScaleEnd: _onScaleEnd,
                child: Semantics(
                  label: l10n.liveWindowCanvasLabel,
                  child: _cutout == null
                      ? const SizedBox.expand()
                      : RepaintBoundary(
                          child: CustomPaint(
                            size: _screen,
                            painter: CutoutPainter(cutout: _cutout!, placement: _placement!),
                          ),
                        ),
                ),
              ),
              if (_focusRing != null)
                Positioned(
                  left: _focusRing!.dx - 32,
                  top: _focusRing!.dy - 32,
                  child: IgnorePointer(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 1.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              SafeArea(
                child: Column(
                  children: [
                    _topBar(context),
                    const SizedBox(height: Space.s1),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.s2),
                      child: _hint(context),
                    ),
                    const Spacer(),
                    _bottomBar(context, captures.length),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s1),
      child: Row(
        children: [
          CameraControlButton(
            icon: Icons.close,
            semanticLabel: l10n.close,
            onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          ),
          const Spacer(),
          if (!_useDemo && _camera != null) ...[
            CameraControlButton(
              icon: Icons.exposure,
              semanticLabel: l10n.exposureLock,
              selected: _exposureLocked,
              onPressed: _toggleExposureLock,
            ),
            const SizedBox(width: Space.s1),
          ],
          CameraControlButton(
            icon: _useDemo ? Icons.texture : Icons.texture_outlined,
            semanticLabel: _useDemo ? l10n.demoFabricNext : l10n.useDemoFabric,
            selected: _useDemo,
            onPressed: () => _useDemo ? _nextDemo() : _setDemo(true),
          ),
          if (_useDemo && !_cameraUnavailable) ...[
            const SizedBox(width: Space.s1),
            CameraControlButton(
              icon: Icons.photo_camera_back_outlined,
              semanticLabel: l10n.useCamera,
              onPressed: () {
                setState(() => _useDemo = false);
                if (_camera == null) _initCamera();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _hint(BuildContext context) {
    final l10n = context.l10n;
    if (widget.practice && _practiceStep < 3) {
      final steps = [l10n.practicePoint, l10n.practiceDrag, l10n.practiceSnap];
      return Column(
        children: [
          CameraHint('${_practiceStep + 1}/3  ${steps[_practiceStep]}'),
          if (_practiceStep == 0) ...[
            const SizedBox(height: Space.s1),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.tonal(
                  onPressed: () => _setDemo(true).then((_) => setState(() => _practiceStep = 1)),
                  child: Text(l10n.useDemoFabric),
                ),
                const SizedBox(width: Space.s1),
                FilledButton.tonal(
                  onPressed: () => setState(() => _practiceStep = 1),
                  child: Text(l10n.next),
                ),
              ],
            ),
          ],
        ],
      );
    }
    if (_tipVisible) {
      return CameraHint(l10n.freshSelfieTip, onClose: _dismissTip, closeLabel: l10n.close);
    }
    return const SizedBox.shrink();
  }

  Widget _bottomBar(BuildContext context, int captureCount) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s2, 0, Space.s2, Space.s3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CameraControlButton(
            icon: _locked ? Icons.lock : Icons.lock_open,
            semanticLabel: _locked ? l10n.unlockPhoto : l10n.lockPhoto,
            label: _locked ? l10n.locked : l10n.lock,
            selected: _locked,
            onPressed: () => setState(() => _locked = !_locked),
          ),
          CameraControlButton(
            icon: _torch ? Icons.flashlight_on : Icons.flashlight_off,
            semanticLabel: l10n.torch,
            label: l10n.torch,
            selected: _torch,
            onPressed: (_useDemo || _camera == null) ? null : _toggleTorch,
          ),
          ShutterButton(semanticLabel: l10n.snapToCompare, busy: _busy, onPressed: _cutout == null ? null : _capture),
          Badge(
            isLabelVisible: captureCount > 0,
            label: Text('${math.min(captureCount, 99)}'),
            child: CameraControlButton(
              icon: Icons.grid_view_rounded,
              semanticLabel: l10n.compare,
              label: l10n.compare,
              onPressed: captureCount == 0
                  ? null
                  : () => context.push('/compare/${widget.windowId}${widget.practice ? '?first=1' : ''}'),
            ),
          ),
        ],
      ),
    );
  }
}

extension on int {
  String get hex => hexOf(this);
}
