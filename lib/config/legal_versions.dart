/// The legal documents shown in the app and hosted on the website.
///
/// Bump a version whenever a document changes materially. The app compares
/// the stored acceptance with these versions and asks again on a mismatch.
enum LegalDoc {
  terms('terms', '2026-11-05-draft'),
  privacy('privacy', '2026-11-05-draft'),
  biometric('biometric-notice', '2026-11-05-draft'),
  aiDisclosure('ai-disclosure', '2026-11-05-draft');

  const LegalDoc(this.slug, this.version);

  final String slug;
  final String version;

  String get assetPath => 'assets/legal/$slug.md';
  String webPath() => '/legal/$slug';
}

/// Versions of the consent texts (the checkbox wording and the summary shown
/// next to it). Changing a consent text changes its version, which re-prompts.
abstract final class ConsentVersions {
  static const terms = '2026-11-05-draft+t1';
  static const biometric = '2026-11-05-draft+b1';
  static const ai = '2026-11-05-draft+a1';
}
