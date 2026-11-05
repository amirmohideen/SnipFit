import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_config.dart';
import '../../config/legal_versions.dart';
import '../../design/tokens.dart';
import '../../l10n/l10n.dart';

/// Shows a legal document bundled in the app (readable without an account
/// or a connection), with a link to the hosted copy.
class LegalScreen extends ConsumerWidget {
  const LegalScreen({required this.slug, super.key});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final doc = LegalDoc.values.where((d) => d.slug == slug).firstOrNull ?? LegalDoc.terms;
    final config = ref.watch(appConfigProvider);
    final title = switch (doc) {
      LegalDoc.terms => l10n.termsOfUse,
      LegalDoc.privacy => l10n.privacyPolicy,
      LegalDoc.biometric => l10n.biometricNotice,
      LegalDoc.aiDisclosure => l10n.aiDisclosure,
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: l10n.openOnWeb,
            icon: const Icon(Icons.open_in_new),
            onPressed: () => launchUrl(Uri.https(config.webDomain, doc.webPath()), mode: LaunchMode.externalApplication),
          ),
        ],
      ),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(doc.assetPath),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return Markdown(
            data: snap.data!,
            padding: const EdgeInsets.all(Space.s2),
            selectable: true,
            onTapLink: (text, href, title) {
              if (href != null) launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
            },
          );
        },
      ),
    );
  }
}
