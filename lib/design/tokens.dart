import 'package:flutter/material.dart';

/// Neutral chrome so the UI never tints how a fabric color is judged.
/// One accent, used only for primary actions and never around the live window.
abstract final class SnipColors {
  // Light
  static const paper = Color(0xFFF7F5F2);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFEFECE7);
  static const ink = Color(0xFF1B1A19);
  static const inkMuted = Color(0xFF615D58);
  static const outline = Color(0xFFDAD5CE);

  // Dark
  static const night = Color(0xFF121110);
  static const nightSurface = Color(0xFF1C1B1A);
  static const nightSurfaceAlt = Color(0xFF282624);
  static const chalk = Color(0xFFF2EFEA);
  static const chalkMuted = Color(0xFFA9A49D);
  static const nightOutline = Color(0xFF3A3734);

  /// Clay accent. White text on it is 5.4:1.
  static const accent = Color(0xFFB04A33);
  static const accentOnDark = Color(0xFFE8846B);
  static const onAccent = Color(0xFFFFFFFF);

  /// Camera chrome: translucent black and mid-gray, never colored.
  static const cameraScrim = Color(0x8C000000);
  static const cameraControl = Color(0xFF8E8A85);
  static const cameraOnScrim = Color(0xFFFFFFFF);

  static const success = Color(0xFF2F7D4F);
  static const danger = Color(0xFFB3261E);
  static const dangerOnDark = Color(0xFFF2B8B5);
}

/// 8-point spacing grid.
abstract final class Space {
  static const xs = 4.0;
  static const s1 = 8.0;
  static const s2 = 16.0;
  static const s3 = 24.0;
  static const s4 = 32.0;
  static const s5 = 40.0;
  static const s6 = 48.0;
  static const s8 = 64.0;
}

abstract final class Radii {
  static const card = 16.0;
  static const sheet = 16.0;
  static const button = 28.0;
  static const chip = 12.0;
}

abstract final class Sizes {
  static const buttonHeight = 56.0;
  static const minTap = 48.0;
  static const shutter = 76.0;
  static const cameraControl = 56.0;
}

/// Short, purposeful motion. Everything returns zero under reduce-motion.
abstract final class Motion {
  static const fast = Duration(milliseconds: 200);
  static const base = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 300);
  static const curve = Curves.easeOutCubic;

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration of(BuildContext context, [Duration d = base]) =>
      reduced(context) ? Duration.zero : d;
}
