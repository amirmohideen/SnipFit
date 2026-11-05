import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../design/tokens.dart';
import '../../design/widgets/buttons.dart';
import '../../design/widgets/camera_controls.dart';
import '../../design/widgets/common.dart';
import '../../l10n/l10n.dart';
import '../cutout/cutout_controller.dart';
import '../cutout/engine/segmentation_engine.dart';
import '../modes/app_mode.dart';
import 'face_guide.dart';

/// Front camera with a face-and-shoulders guide, or a gallery upload.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({this.guided = false, this.editWindowId, super.key});

  /// First-run: shows coach marks on the face guide.
  final bool guided;
  final String? editWindowId;

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  bool _denied = false;
  bool _busy = false;
  bool _someoneElse = false;
  bool _coachVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    // Load the models while the person frames the photo.
    unawaited(ref.read(segmentationEngineProvider).warmUp().catchError((Object _) {}));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (state == AppLifecycleState.inactive) {
      _controller = null;
      c?.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && c == null) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
        final front = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
        _cameraIndex = front < 0 ? 0 : front;
      }
      if (_cameras.isEmpty) {
        setState(() => _denied = true);
        return;
      }
      final controller = CameraController(
        _cameras[_cameraIndex],
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _denied = false;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() => _denied = e.code.contains('Denied') || e.code.contains('denied') || e.code == 'CameraAccessRestricted');
    }
  }

  Future<void> _flip() async {
    if (_cameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    final old = _controller;
    setState(() => _controller = null);
    await old?.dispose();
    await _initCamera();
  }

  Future<void> _shoot() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      HapticFeedback.lightImpact();
      final file = await c.takePicture();
      final bytes = await File(file.path).readAsBytes();
      unawaited(File(file.path).delete().catchError((_) => File(file.path)));
      await _process(bytes, CaptureSource.camera);
    } on CameraException {
      if (mounted) showSnack(context, context.l10n.genericError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    if (_busy) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 92,
      requestFullMetadata: false,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    unawaited(File(picked.path).delete().catchError((_) => File(picked.path)));
    await _process(bytes, CaptureSource.upload);
  }

  Future<void> _process(List<int> bytes, CaptureSource source) async {
    if (_someoneElse) {
      final ok = await confirmSomeoneElse(context);
      if (!ok || !mounted) return;
    }
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    unawaited(
      ref.read(cutoutControllerProvider.notifier).start(
        data,
        source: source,
        someoneElse: _someoneElse,
        editingWindowId: widget.editWindowId,
      ),
    );
    if (!mounted) return;
    await context.push('/refine${widget.guided ? '?guided=1' : ''}');
  }

  String _tip(AppMode mode) => switch (mode) {
    AppMode.hijab => context.l10n.tipHijabPhoto,
    _ => context.l10n.tipTopPhoto,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final mode = ref.watch(modeProvider);
    if (_denied) return _CameraDenied(onUpload: _upload);
    final c = _controller;
    final ready = c != null && c.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: c.value.previewSize!.height,
                  height: c.value.previewSize!.width,
                  child: CameraPreview(c),
                ),
              ),
            ),
          const IgnorePointer(child: CustomPaint(painter: FaceGuidePainter())),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: Space.s1),
                    CameraControlButton(
                      icon: Icons.close,
                      semanticLabel: l10n.close,
                      onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                    ),
                    const Spacer(),
                    _SubjectToggle(
                      someoneElse: _someoneElse,
                      onChanged: (v) => setState(() => _someoneElse = v),
                    ),
                    const SizedBox(width: Space.s1),
                  ],
                ),
                const SizedBox(height: Space.s2),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.s2),
                  child: widget.guided && _coachVisible
                      ? CameraHint(
                          l10n.coachFaceGuide,
                          onClose: () => setState(() => _coachVisible = false),
                          closeLabel: l10n.close,
                        )
                      : CameraHint(_tip(mode)),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      CameraControlButton(
                        icon: Icons.photo_library_outlined,
                        semanticLabel: l10n.uploadPhoto,
                        label: l10n.upload,
                        onPressed: _upload,
                      ),
                      ShutterButton(
                        semanticLabel: l10n.takePhoto,
                        busy: _busy,
                        onPressed: ready ? _shoot : null,
                      ),
                      CameraControlButton(
                        icon: Icons.flip_camera_ios_outlined,
                        semanticLabel: l10n.flipCamera,
                        label: l10n.flip,
                        onPressed: _cameras.length > 1 ? _flip : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubjectToggle extends StatelessWidget {
  const _SubjectToggle({required this.someoneElse, required this.onChanged});

  final bool someoneElse;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      toggled: someoneElse,
      label: l10n.trySomeoneElse,
      excludeSemantics: true,
      child: Material(
        color: someoneElse ? SnipColors.cameraOnScrim : SnipColors.cameraScrim,
        borderRadius: BorderRadius.circular(Radii.button),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.button),
          onTap: () => onChanged(!someoneElse),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Sizes.minTap),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    someoneElse ? Icons.people_alt : Icons.person_outline,
                    size: 20,
                    color: someoneElse ? SnipColors.ink : SnipColors.cameraOnScrim,
                  ),
                  const SizedBox(width: Space.s1),
                  Text(
                    someoneElse ? l10n.subjectSomeoneElse : l10n.subjectMe,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: someoneElse ? SnipColors.ink : SnipColors.cameraOnScrim,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asked every time a photo of someone else is used.
Future<bool> confirmSomeoneElse(BuildContext context) async {
  var checked = false;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final l10n = context.l10n;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.s3, 0, Space.s3, Space.s3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.someoneElseTitle, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: Space.s1),
                Text(l10n.someoneElseBody, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: Space.s2),
                ConsentCheckbox(
                  value: checked,
                  onChanged: (v) => setState(() => checked = v),
                  label: l10n.someoneElseCheckbox,
                ),
                const SizedBox(height: Space.s2),
                PrimaryButton(
                  label: l10n.continueLabel,
                  onPressed: checked ? () => Navigator.of(context).pop(true) : null,
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  return result ?? false;
}

class _CameraDenied extends StatelessWidget {
  const _CameraDenied({required this.onUpload});

  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: l10n.close,
          icon: const Icon(Icons.close),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.no_photography_outlined, size: 48, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: Space.s2),
              Text(l10n.cameraDeniedTitle, style: theme.textTheme.displaySmall),
              const SizedBox(height: Space.s1),
              Text(l10n.cameraDeniedBody, style: theme.textTheme.bodyLarge),
              const Spacer(),
              PrimaryButton(label: l10n.openSettings, onPressed: openAppSettings),
              const SizedBox(height: Space.s1),
              SecondaryButton(label: l10n.uploadInstead, onPressed: onUpload),
            ],
          ),
        ),
      ),
    );
  }
}
