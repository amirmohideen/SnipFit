import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/legal_versions.dart';
import '../../core/analytics/analytics.dart';
import '../../core/analytics/analytics_events.dart';
import '../../core/backend/auth_service.dart';
import '../../core/backend/backend.dart';
import '../../core/flags/remote_flags.dart';
import '../../core/images/image_utils.dart';
import '../../core/notifications/notifications.dart';
import '../../core/platform/native_channels.dart';
import '../../core/storage/media_store.dart';
import '../../design/illustrations/snip_animation.dart';
import '../../design/tokens.dart';
import '../../design/widgets/buttons.dart';
import '../../design/widgets/camera_controls.dart';
import '../../design/widgets/common.dart';
import '../../design/widgets/step_scaffold.dart';
import '../../l10n/l10n.dart';
import '../consent/consent_repository.dart';
import '../cutout/engine/segmentation_engine.dart';
import '../cutout/mask/photo_checks.dart';
import '../live_window/compositor.dart';
import '../modes/app_mode.dart';
import '../paywall/entitlements.dart';
import '../share/export_service.dart';
import 'ai_gate.dart';
import 'tryon_repository.dart';

String _locale(BuildContext context) => Localizations.localeOf(context).toLanguageTag();

// ---------------------------------------------------------------- hub/gate

class AiHubScreen extends ConsumerWidget {
  const AiHubScreen({this.windowId, super.key});

  final String? windowId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final hasRef = ref.watch(referencePhotoExistsProvider);
    if (!hasRef.hasValue) return const Scaffold(body: Center(child: SnipSpinner()));
    final gate = evaluateAiGate(
      featureEnabled: ref.watch(remoteFlagsProvider.select((f) => f.aiTryOnEnabled)),
      backendReady: ref.watch(backendStatusProvider).firebaseReady,
      isAdult: ref.watch(ageProvider).isAdult,
      aiConsent: ref.watch(consentProvider)[ConsentType.ai] ?? false,
      entitlements: ref.watch(entitlementsProvider),
      hasReferencePhoto: hasRef.value!,
    );
    void close() => context.canPop() ? context.pop() : context.go('/');
    switch (gate) {
      case AiGate.unavailable:
        return _Message(title: l10n.aiUnavailableTitle, body: l10n.aiUnavailableBody, onClose: close);
      case AiGate.notAdult:
        return _Message(title: l10n.aiAdultsOnlyTitle, body: l10n.aiAdultsOnlyBody, onClose: close);
      case AiGate.suspended:
        return _Message(title: l10n.aiSuspendedTitle, body: l10n.aiSuspendedBody, onClose: close);
      case AiGate.needsConsent:
        return const AiConsentScreen(returnTo: '/ai');
      case AiGate.needsCredits:
        return StepScaffold(
          onBack: close,
          backLabel: l10n.back,
          body: StepHeader(title: l10n.aiNeedsCreditsTitle, subtitle: l10n.aiNeedsCreditsBody),
          actions: [PrimaryButton(label: l10n.seePro, onPressed: () => context.push('/paywall?trigger=ai_tryon'))],
        );
      case AiGate.needsReference:
        return const ReferencePhotoScreen();
      case AiGate.ready:
        return _AiReady(windowId: windowId);
    }
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body, required this.onClose});

  final String title;
  final String body;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => StepScaffold(
    onBack: onClose,
    backLabel: context.l10n.back,
    body: StepHeader(title: title, subtitle: body),
    actions: [SecondaryButton(label: context.l10n.close, onPressed: onClose)],
  );
}

class _AiReady extends ConsumerWidget {
  const _AiReady({this.windowId});

  final String? windowId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final repo = ref.watch(tryOnRepositoryProvider);
    final ent = ref.watch(entitlementsProvider);
    return FutureBuilder<bool>(
      future: NativeChannels.tapSegmenterAvailable(),
      builder: (context, snap) {
        final canTap = snap.data ?? false;
        return StepScaffold(
          onBack: () => context.canPop() ? context.pop() : context.go('/'),
          backLabel: l10n.back,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StepHeader(title: l10n.aiReadyTitle, subtitle: l10n.aiReadyBody),
              const SizedBox(height: Space.s3),
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.chip),
                    child: Image.file(repo.referencePhotoFile(), width: 72, height: 96, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: Space.s2),
                  Expanded(child: Text(l10n.yourTryOnPhoto, style: Theme.of(context).textTheme.bodyLarge)),
                  TextButton(onPressed: () => context.push('/ai/reference'), child: Text(l10n.change)),
                ],
              ),
              const SizedBox(height: Space.s2),
              Text(l10n.creditBalance(ent.aiTryOnsAvailable), style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          actions: [
            if (canTap)
              PrimaryButton(
                label: l10n.tapAGarment,
                icon: Icons.touch_app_outlined,
                onPressed: () => context.push('/ai/garment${windowId == null ? '' : '?window=$windowId'}'),
              ),
            SecondaryButton(
              label: l10n.chooseGarmentFromGallery,
              icon: Icons.photo_library_outlined,
              onPressed: () => context.push('/ai/garment?gallery=1${windowId == null ? '' : '&window=$windowId'}'),
            ),
          ],
        );
      },
    );
  }
}

// ----------------------------------------------------------------- consent

/// Shown once, and again whenever its text changes. Required by App Store
/// guideline 5.1.2(i) before any photo reaches the server.
class AiConsentScreen extends ConsumerStatefulWidget {
  const AiConsentScreen({this.returnTo, super.key});

  final String? returnTo;

  @override
  ConsumerState<AiConsentScreen> createState() => _AiConsentScreenState();
}

class _AiConsentScreenState extends ConsumerState<AiConsentScreen> {
  bool _agreed = false;

  Future<void> _continue() async {
    await ref.read(consentProvider.notifier).set(ConsentType.ai, accepted: true, locale: _locale(context));
    await ref.read(analyticsProvider).track(AnalyticsEvents.aiConsentGiven);
    if (!mounted) return;
    if (widget.returnTo != null) {
      context.go(widget.returnTo!);
    } else if (context.canPop()) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return StepScaffold(
      onBack: () => context.canPop() ? context.pop() : context.go('/'),
      backLabel: l10n.back,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StepHeader(title: l10n.aiConsentTitle),
          const SizedBox(height: Space.s2),
          Text(l10n.aiConsentWhat, style: theme.textTheme.bodyLarge),
          const SizedBox(height: Space.s1),
          Text(l10n.aiConsentWho, style: theme.textTheme.bodyLarge),
          const SizedBox(height: Space.s1),
          Text(l10n.aiConsentWhy, style: theme.textTheme.bodyLarge),
          LinkButton(label: l10n.aiDisclosure, onPressed: () => context.push('/legal/${LegalDoc.aiDisclosure.slug}')),
          const SizedBox(height: Space.s1),
          ConsentCheckbox(value: _agreed, onChanged: (v) => setState(() => _agreed = v), label: l10n.aiConsentCheckbox),
        ],
      ),
      actions: [PrimaryButton(label: l10n.continueLabel, onPressed: _agreed ? _continue : null)],
    );
  }
}

// --------------------------------------------------------- reference photo

class ReferencePhotoScreen extends ConsumerStatefulWidget {
  const ReferencePhotoScreen({super.key});

  @override
  ConsumerState<ReferencePhotoScreen> createState() => _ReferencePhotoScreenState();
}

class _ReferencePhotoScreenState extends ConsumerState<ReferencePhotoScreen> {
  bool _busy = false;
  String? _problem;

  Future<void> _pick(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 92,
      requestFullMetadata: false,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (picked == null) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final bytes = await picked.readAsBytes();
      unawaited(File(picked.path).delete().catchError((_) => File(picked.path)));
      final photo = await ImageUtils.decode(bytes, maxSide: 1536);
      final png = await ImageUtils.encodePng(photo.image);
      final out = await ref.read(segmentationEngineProvider).analyze(png);
      final check = checkPhoto(faces: out.faces, luma: ImageUtils.luma(photo.rgba), width: photo.width, height: photo.height);
      if (!mounted) return;
      final l10n = context.l10n;
      if (check.blocking || check.issues.contains(PhotoIssue.tooDark)) {
        setState(() => _problem = switch (check.primary) {
          PhotoIssue.multipleFaces => l10n.fixMultipleFaces,
          PhotoIssue.tooDark => l10n.fixTooDark,
          _ => l10n.fixNoFace,
        });
        photo.dispose();
        return;
      }
      final jpeg = await ImageUtils.encodeJpeg(photo.rgba, photo.width, photo.height, quality: 90);
      photo.dispose();
      await ref.read(tryOnRepositoryProvider).saveReferencePhoto(jpeg);
      ref.invalidate(referencePhotoExistsProvider);
      if (mounted && GoRouterState.of(context).uri.path == '/ai/reference') context.pop();
    } on Object {
      if (mounted) setState(() => _problem = context.l10n.genericError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return StepScaffold(
      onBack: () => context.canPop() ? context.pop() : context.go('/'),
      backLabel: l10n.back,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StepHeader(title: l10n.referenceTitle, subtitle: l10n.referenceBody),
          const SizedBox(height: Space.s2),
          for (final tip in [l10n.referenceTip1, l10n.referenceTip2, l10n.referenceTip3])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [const Icon(Icons.check, size: 20), const SizedBox(width: Space.s1), Expanded(child: Text(tip))]),
            ),
          if (_problem != null) ...[
            const SizedBox(height: Space.s2),
            Semantics(liveRegion: true, child: Text(_problem!, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.error))),
          ],
          const SizedBox(height: Space.s2),
          Text(l10n.referenceStorageNote, style: theme.textTheme.bodySmall),
        ],
      ),
      actions: [
        PrimaryButton(label: l10n.takePhoto, busy: _busy, onPressed: () => _pick(ImageSource.camera)),
        SecondaryButton(label: l10n.upload, onPressed: _busy ? null : () => _pick(ImageSource.gallery)),
      ],
    );
  }
}

// ----------------------------------------------------------------- garment

/// Rear camera: tap the item on a rack, hanger or mannequin. The on-device
/// tap segmenter cuts it out; nothing leaves the phone until "Use it".
class GarmentScreen extends ConsumerStatefulWidget {
  const GarmentScreen({this.gallery = false, this.windowId, super.key});

  final bool gallery;
  final String? windowId;

  @override
  ConsumerState<GarmentScreen> createState() => _GarmentScreenState();
}

class _GarmentScreenState extends ConsumerState<GarmentScreen> {
  CameraController? _camera;
  Size _screen = Size.zero;
  bool _working = false;
  Uint8List? _garmentPng;
  ui.Image? _garmentPreview;

  @override
  void initState() {
    super.initState();
    if (widget.gallery) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fromGallery());
    } else {
      _initCamera();
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    _garmentPreview?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      final back = cams.where((c) => c.lensDirection == CameraLensDirection.back).firstOrNull ?? cams.first;
      final c = CameraController(back, ResolutionPreset.veryHigh, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _camera = c);
    } on Object {
      if (mounted) unawaited(_fromGallery());
    }
  }

  Future<void> _onTap(TapUpDetails d) async {
    final c = _camera;
    if (c == null || _working || _garmentPng != null) return;
    setState(() => _working = true);
    try {
      final preview = c.value.previewSize!;
      final crop = coverCrop(Size(preview.height, preview.width), _screen);
      final nx = (crop.left + d.localPosition.dx / _screen.width * crop.width) / preview.height;
      final ny = (crop.top + d.localPosition.dy / _screen.height * crop.height) / preview.width;
      final shot = await c.takePicture();
      final mask = await NativeChannels.tapSegment(imagePath: shot.path, x: nx.clamp(0, 1), y: ny.clamp(0, 1));
      final bytes = await File(shot.path).readAsBytes();
      unawaited(File(shot.path).delete().catchError((_) => File(shot.path)));
      if (mask == null) {
        if (mounted) showSnack(context, context.l10n.garmentNotFound);
        return;
      }
      await _setGarment(await composeGarment(bytes, mask));
    } on Object {
      if (mounted) showSnack(context, context.l10n.garmentNotFound);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _fromGallery() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 92, requestFullMetadata: false);
    if (picked == null) {
      if (mounted && _camera == null) context.pop();
      return;
    }
    final bytes = await picked.readAsBytes();
    unawaited(File(picked.path).delete().catchError((_) => File(picked.path)));
    final decoded = await ImageUtils.decode(bytes, maxSide: 1024);
    final png = await ImageUtils.encodePng(decoded.image);
    decoded.dispose();
    await _setGarment(png);
  }

  Future<void> _setGarment(Uint8List png) async {
    final img = (await ImageUtils.decode(png, maxSide: 1024)).image;
    if (!mounted) return;
    setState(() {
      _garmentPng = png;
      _garmentPreview?.dispose();
      _garmentPreview = img;
    });
  }

  Future<void> _useIt() async {
    final png = _garmentPng;
    if (png == null) return;
    setState(() => _working = true);
    final l10n = context.l10n;
    try {
      await ref.read(analyticsProvider).track(AnalyticsEvents.aiTryonRequested, {AnalyticsProps.mode: ref.read(modeProvider).name});
      final id = await ref.read(tryOnRepositoryProvider).submit(garmentPng: png, mode: ref.read(modeProvider));
      if (mounted) context.go('/ai/progress/$id${widget.windowId == null ? '' : '?window=${widget.windowId}'}');
    } on TryOnRejected catch (e) {
      if (!mounted) return;
      showSnack(context, switch (e.reason) {
        TryOnRejection.noCredits => l10n.aiNeedsCreditsTitle,
        TryOnRejection.rateLimited => l10n.aiRateLimited,
        TryOnRejection.dailyCap => l10n.aiBusy,
        TryOnRejection.suspended => l10n.aiSuspendedTitle,
        TryOnRejection.notAdult => l10n.aiAdultsOnlyTitle,
        TryOnRejection.consent => l10n.aiConsentTitle,
        _ => l10n.aiUnavailableTitle,
      });
    } on Object {
      if (mounted) showSnack(context, l10n.genericError);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_garmentPreview != null) {
      return StepScaffold(
        onBack: () => setState(() {
          _garmentPng = null;
          _garmentPreview?.dispose();
          _garmentPreview = null;
        }),
        backLabel: l10n.retake,
        scrollable: false,
        body: Column(
          children: [
            Text(l10n.isThisTheItem, style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: Space.s2),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.card),
                child: ColoredBox(color: Colors.white, child: RawImage(image: _garmentPreview, fit: BoxFit.contain)),
              ),
            ),
          ],
        ),
        actions: [
          PrimaryButton(label: l10n.useIt, busy: _working, onPressed: _useIt),
          SecondaryButton(
            label: l10n.retake,
            onPressed: () => setState(() {
              _garmentPng = null;
              _garmentPreview?.dispose();
              _garmentPreview = null;
              if (widget.gallery) _fromGallery();
            }),
          ),
        ],
      );
    }
    final c = _camera;
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          _screen = constraints.biggest;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (c != null && c.value.isInitialized)
                GestureDetector(
                  onTapUp: _onTap,
                  child: ClipRect(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(width: c.value.previewSize!.height, height: c.value.previewSize!.width, child: CameraPreview(c)),
                    ),
                  ),
                ),
              if (_working) const Center(child: SnipSpinner()),
              SafeArea(
                child: Column(
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: Space.s1),
                        CameraControlButton(icon: Icons.close, semanticLabel: l10n.close, onPressed: () => context.pop()),
                      ],
                    ),
                    const SizedBox(height: Space.s1),
                    CameraHint(l10n.tapGarmentHint),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.s3),
                      child: CameraControlButton(
                        icon: Icons.photo_library_outlined,
                        semanticLabel: l10n.chooseGarmentFromGallery,
                        label: l10n.upload,
                        onPressed: _fromGallery,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Garment on a plain white background, cropped to the mask with a margin.
Future<Uint8List> composeGarment(Uint8List photoBytes, Uint8List maskPng) async {
  final photo = await ImageUtils.decode(photoBytes, maxSide: 2048);
  final mask = await ImageUtils.decode(maskPng, maxSide: 2048);
  final w = photo.width, h = photo.height;
  final mrgba = mask.width == w && mask.height == h ? mask.rgba : await ImageUtils.toRgba(await ImageUtils.resize(mask.image, w, h));
  var x0 = w, y0 = h, x1 = 0, y1 = 0;
  final out = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    final a = mrgba[i * 4];
    final x = i % w, y = i ~/ w;
    if (a > 127) {
      if (x < x0) x0 = x;
      if (x > x1) x1 = x;
      if (y < y0) y0 = y;
      if (y > y1) y1 = y;
    }
    for (var c = 0; c < 3; c++) {
      out[i * 4 + c] = (photo.rgba[i * 4 + c] * a + 255 * (255 - a)) ~/ 255;
    }
    out[i * 4 + 3] = 255;
  }
  photo.dispose();
  mask.dispose();
  if (x1 <= x0 || y1 <= y0) throw StateError('empty mask');
  final mx = ((x1 - x0) * 0.06).round(), my = ((y1 - y0) * 0.06).round();
  final crop = Rect.fromLTRB(
    (x0 - mx).clamp(0, w - 1).toDouble(),
    (y0 - my).clamp(0, h - 1).toDouble(),
    (x1 + mx).clamp(0, w - 1).toDouble(),
    (y1 + my).clamp(0, h - 1).toDouble(),
  );
  final full = await ImageUtils.fromRgba(out, w, h);
  final rec = ui.PictureRecorder();
  final cw = crop.width.round(), ch = crop.height.round();
  Canvas(rec).drawImageRect(full, crop, Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()), Paint());
  final cropped = await rec.endRecording().toImage(cw, ch);
  full.dispose();
  final png = await ImageUtils.encodePng(cropped);
  cropped.dispose();
  return png;
}

// ---------------------------------------------------------------- progress

class TryOnProgressScreen extends ConsumerStatefulWidget {
  const TryOnProgressScreen({required this.requestId, this.windowId, super.key});

  final String requestId;
  final String? windowId;

  @override
  ConsumerState<TryOnProgressScreen> createState() => _TryOnProgressScreenState();
}

class _TryOnProgressScreenState extends ConsumerState<TryOnProgressScreen> {
  StreamSubscription<TryOnStatus>? _sub;
  TryOnStatus? _status;
  bool _notifyRequested = false;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(tryOnRepositoryProvider).watch(widget.requestId).listen(_onStatus);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onStatus(TryOnStatus s) {
    setState(() => _status = s);
    final analytics = ref.read(analyticsProvider);
    switch (s.phase) {
      case TryOnPhase.succeeded:
        analytics.track(AnalyticsEvents.aiTryonSucceeded);
        context.go('/ai/result/${widget.requestId}${widget.windowId == null ? '' : '?window=${widget.windowId}'}');
      case TryOnPhase.blocked:
        analytics.track(AnalyticsEvents.aiTryonBlocked);
      case TryOnPhase.failed:
        analytics.track(AnalyticsEvents.aiTryonFailed, {AnalyticsProps.reason: s.errorCode ?? 'unknown'});
      default:
        break;
    }
  }

  Future<void> _notifyMe() async {
    final granted = await ref.read(notificationsProvider).requestPermission();
    final user = ref.read(authServiceProvider).currentUser;
    if (granted && user != null) await ref.read(notificationsProvider).registerDevice(user.uid);
    if (!mounted) return;
    setState(() => _notifyRequested = true);
    showSnack(context, granted ? context.l10n.notifyOn : context.l10n.notifyOff);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final s = _status;
    final phase = s?.phase ?? TryOnPhase.queued;
    if (phase == TryOnPhase.blocked || phase == TryOnPhase.failed) {
      return StepScaffold(
        body: StepHeader(
          title: phase == TryOnPhase.blocked ? l10n.aiBlockedTitle : l10n.aiFailedTitle,
          subtitle: phase == TryOnPhase.blocked ? l10n.aiBlockedBody : l10n.aiFailedBody,
        ),
        actions: [PrimaryButton(label: l10n.done, onPressed: () => context.go('/'))],
      );
    }
    final label = switch (phase) {
      TryOnPhase.queued => l10n.aiPhaseQueued,
      TryOnPhase.checking => l10n.aiPhaseChecking,
      TryOnPhase.generating => l10n.aiPhaseGenerating,
      _ => l10n.aiPhaseFinishing,
    };
    return StepScaffold(
      body: Column(
        children: [
          const SizedBox(height: Space.s5),
          const SnipSpinner(size: 96),
          const SizedBox(height: Space.s3),
          Semantics(liveRegion: true, child: Text(label, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center)),
          const SizedBox(height: Space.s1),
          Text(l10n.aiTakesAMinute, textAlign: TextAlign.center),
        ],
      ),
      actions: [
        if (!_notifyRequested) PrimaryButton(label: l10n.notifyWhenReady, onPressed: _notifyMe),
        SecondaryButton(label: l10n.keepBrowsing, onPressed: () => context.go('/')),
      ],
    );
  }
}

// ------------------------------------------------------------------ result

class TryOnResultScreen extends ConsumerStatefulWidget {
  const TryOnResultScreen({required this.requestId, this.windowId, super.key});

  final String requestId;
  final String? windowId;

  @override
  ConsumerState<TryOnResultScreen> createState() => _TryOnResultScreenState();
}

class _TryOnResultScreenState extends ConsumerState<TryOnResultScreen> {
  List<File>? _results;
  File? _trueColor;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(tryOnRepositoryProvider);
    final status = await repo.watch(widget.requestId).firstWhere((s) => s.done);
    final files = await repo.download(status);
    File? trueColor;
    if (widget.windowId != null) {
      final store = ref.read(mediaStoreProvider);
      final captures = await store.listCaptures(widget.windowId!);
      final pick = captures.where((c) => c.favorite).firstOrNull ?? captures.firstOrNull;
      if (pick != null) trueColor = store.compositeFile(pick.id);
    }
    if (mounted) {
      setState(() {
        _results = files;
        _trueColor = trueColor;
      });
    }
  }

  Future<void> _report() async {
    final l10n = context.l10n;
    final reason = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(padding: const EdgeInsets.all(Space.s2), child: Text(l10n.reportTitle, style: Theme.of(context).textTheme.titleLarge)),
            for (final r in [
              ('inappropriate', l10n.reportInappropriate),
              ('not_permitted', l10n.reportNotPermitted),
              ('poor_quality', l10n.reportPoorQuality),
              ('other', l10n.reportOther),
            ])
              ListTile(title: Text(r.$2), onTap: () => Navigator.pop(context, r.$1)),
          ],
        ),
      ),
    );
    if (reason == null) return;
    try {
      await ref.read(tryOnRepositoryProvider).report(widget.requestId, reason);
      await ref.read(analyticsProvider).track(AnalyticsEvents.reportSubmitted, {AnalyticsProps.reason: reason});
      if (mounted) showSnack(context, l10n.reportThanks);
    } on Object {
      if (mounted) showSnack(context, l10n.genericError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final results = _results;
    if (results == null) return const Scaffold(body: Center(child: SnipSpinner()));
    if (results.isEmpty) {
      return _Message(title: l10n.aiFailedTitle, body: l10n.aiFailedBody, onClose: () => context.go('/'));
    }
    final current = results[_index.clamp(0, results.length - 1)];
    Widget panel(String label, Widget child, {bool ai = false}) => Expanded(
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: Space.xs),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.card),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  child,
                  if (ai)
                    PositionedDirectional(
                      top: Space.s1,
                      start: Space.s1,
                      child: PillBadge(label: l10n.aiGeneratedLabel, icon: Icons.auto_awesome, emphasized: true),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: l10n.close, icon: const Icon(Icons.close), onPressed: () => context.go('/')),
        title: Text(l10n.aiResultTitle),
        actions: [IconButton(tooltip: l10n.report, icon: const Icon(Icons.flag_outlined), onPressed: _report)],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.s2),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    if (_trueColor != null) ...[
                      panel(l10n.trueColor, Image.file(_trueColor!, fit: BoxFit.cover)),
                      const SizedBox(width: Space.s1),
                    ],
                    panel(l10n.aiLook, GestureDetector(
                      onTap: results.length > 1 ? () => setState(() => _index = (_index + 1) % results.length) : null,
                      child: Image.file(current, fit: BoxFit.cover),
                    ), ai: true),
                  ],
                ),
              ),
              const SizedBox(height: Space.s1),
              Text(l10n.aiApproximation, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
              const SizedBox(height: Space.s2),
              PrimaryButton(
                label: l10n.share,
                icon: Icons.ios_share,
                onPressed: () async {
                  final file = await ref.read(exportServiceProvider).exportAi(current, l10n.aiGeneratedLabel);
                  await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'image/jpeg')]));
                },
              ),
              const SizedBox(height: Space.s1),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: l10n.saveToPhotos,
                      onPressed: () => ref.read(exportServiceProvider).saveAiToPhotos(context, current),
                    ),
                  ),
                  const SizedBox(width: Space.s1),
                  Expanded(child: SecondaryButton(label: l10n.report, icon: Icons.flag_outlined, onPressed: _report)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
