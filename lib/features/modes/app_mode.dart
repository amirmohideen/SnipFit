import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/flags/remote_flags.dart';
import '../../core/storage/local_store.dart';
import '../cutout/mask/mask_builder.dart';

/// Who the app is set up for. Women's mode launches first with Hijab mode
/// alongside it; Men's mode stays behind a Remote Config flag until later.
enum AppMode {
  women,
  hijab,
  men;

  static AppMode? tryParse(String? raw) {
    for (final m in values) {
      if (m.name == raw) return m;
    }
    return null;
  }

  /// Default window strategy for a mode (Hijab may switch to the template).
  WindowStrategy get defaultStrategy => switch (this) {
    AppMode.hijab => WindowStrategy.hijabWorn,
    _ => WindowStrategy.garment,
  };
}

class ModeController extends Notifier<AppMode> {
  @override
  AppMode build() {
    final stored = AppMode.tryParse(ref.read(localStoreProvider).getString(Keys.mode));
    final menEnabled = ref.watch(remoteFlagsProvider.select((f) => f.menModeEnabled));
    final mode = stored ?? AppMode.women;
    return (mode == AppMode.men && !menEnabled) ? AppMode.women : mode;
  }

  Future<void> select(AppMode mode) async {
    state = mode;
    await ref.read(localStoreProvider).setString(Keys.mode, mode.name);
  }
}

final modeProvider = NotifierProvider<ModeController, AppMode>(ModeController.new);

/// Modes currently offered, respecting the Men's-mode flag.
final availableModesProvider = Provider<List<AppMode>>((ref) {
  final menEnabled = ref.watch(remoteFlagsProvider.select((f) => f.menModeEnabled));
  return [AppMode.women, AppMode.hijab, if (menEnabled) AppMode.men];
});
