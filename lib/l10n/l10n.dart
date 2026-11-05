import 'package:flutter/widgets.dart';

import 'gen/app_localizations.dart';

export 'gen/app_localizations.dart';

extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Supported launch languages. Arabic gets a full right-to-left layout.
const supportedLocales = [
  Locale('en'),
  Locale('ar'),
  Locale('tr'),
  Locale('ms'),
  Locale('id'),
];
