import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'tokens.dart';

/// Builds the light or dark theme. Arabic gets IBM Plex Sans Arabic as the
/// primary family; everything else uses Plus Jakarta Sans.
abstract final class SnipTheme {
  static const latinFamily = 'PlusJakartaSans';
  static const arabicFamily = 'IBMPlexSansArabic';

  static ThemeData light(Locale? locale) => _build(Brightness.light, locale);
  static ThemeData dark(Locale? locale) => _build(Brightness.dark, locale);

  /// Five-step type scale: display, title, lead, body, caption.
  static TextTheme _textTheme(Color ink, Color muted) {
    const display = TextStyle(
      fontSize: 30,
      height: 36 / 30,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
    );
    const title = TextStyle(
      fontSize: 22,
      height: 28 / 22,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
    );
    const lead = TextStyle(
      fontSize: 17,
      height: 24 / 17,
      fontWeight: FontWeight.w500,
    );
    const body = TextStyle(
      fontSize: 15,
      height: 22 / 15,
      fontWeight: FontWeight.w400,
    );
    const caption = TextStyle(
      fontSize: 13,
      height: 18 / 13,
      fontWeight: FontWeight.w500,
    );
    return TextTheme(
      displaySmall: display.copyWith(color: ink),
      headlineSmall: title.copyWith(color: ink),
      titleLarge: title.copyWith(color: ink),
      titleMedium: lead.copyWith(color: ink, fontWeight: FontWeight.w600),
      bodyLarge: lead.copyWith(color: ink),
      bodyMedium: body.copyWith(color: ink),
      bodySmall: caption.copyWith(color: muted),
      labelLarge: lead.copyWith(color: ink, fontWeight: FontWeight.w600),
      labelMedium: caption.copyWith(color: ink),
      labelSmall: caption.copyWith(color: muted, fontSize: 12),
    );
  }

  static ThemeData _build(Brightness brightness, Locale? locale) {
    final dark = brightness == Brightness.dark;
    final isArabic = locale?.languageCode == 'ar';
    final family = isArabic ? arabicFamily : latinFamily;
    final fallback = isArabic ? [latinFamily] : [arabicFamily];

    final bg = dark ? SnipColors.night : SnipColors.paper;
    final surface = dark ? SnipColors.nightSurface : SnipColors.surface;
    final surfaceAlt = dark ? SnipColors.nightSurfaceAlt : SnipColors.surfaceAlt;
    final ink = dark ? SnipColors.chalk : SnipColors.ink;
    final muted = dark ? SnipColors.chalkMuted : SnipColors.inkMuted;
    final outline = dark ? SnipColors.nightOutline : SnipColors.outline;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: SnipColors.accent,
      onPrimary: SnipColors.onAccent,
      secondary: ink,
      onSecondary: bg,
      tertiary: dark ? SnipColors.accentOnDark : SnipColors.accent,
      onTertiary: SnipColors.onAccent,
      error: dark ? SnipColors.dangerOnDark : SnipColors.danger,
      onError: dark ? SnipColors.night : SnipColors.surface,
      surface: surface,
      onSurface: ink,
      onSurfaceVariant: muted,
      surfaceContainerLowest: bg,
      surfaceContainerLow: bg,
      surfaceContainer: surface,
      surfaceContainerHigh: surfaceAlt,
      surfaceContainerHighest: surfaceAlt,
      outline: outline,
      outlineVariant: outline,
    );

    final text = _textTheme(ink, muted).apply(
      fontFamily: family,
      fontFamilyFallback: fallback,
    );

    final pill = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.button),
    );
    const buttonSize = Size(Sizes.minTap, Sizes.buttonHeight);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamily: family,
      fontFamilyFallback: fallback,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: text.titleMedium,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          shape: pill,
          backgroundColor: SnipColors.accent,
          foregroundColor: SnipColors.onAccent,
          disabledBackgroundColor: surfaceAlt,
          disabledForegroundColor: muted,
          textStyle: text.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: Space.s3),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          shape: pill,
          foregroundColor: ink,
          side: BorderSide(color: outline, width: 1.5),
          textStyle: text.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: Space.s3),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(Sizes.minTap, Sizes.minTap),
          foregroundColor: ink,
          textStyle: text.labelLarge?.copyWith(fontSize: 15),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(Sizes.minTap, Sizes.minTap),
          foregroundColor: ink,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: BorderSide(color: outline),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: muted, width: 2),
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? SnipColors.accent : null,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: ink,
        inactiveTrackColor: outline,
        thumbColor: ink,
        overlayColor: ink.withValues(alpha: 0.08),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? SnipColors.onAccent : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? SnipColors.accent : null,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          minimumSize: const Size(Sizes.minTap, Sizes.minTap),
          selectedBackgroundColor: ink,
          selectedForegroundColor: bg,
          foregroundColor: ink,
          side: BorderSide(color: outline),
          textStyle: text.labelLarge?.copyWith(fontSize: 15),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: bg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.chip),
        ),
      ),
      dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: Space.s1 + 4,
        iconColor: ink,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodySmall,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
