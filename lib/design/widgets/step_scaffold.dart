import 'package:flutter/material.dart';

import '../tokens.dart';

/// Layout for onboarding and flow screens: content on top, actions in the
/// bottom third for one-handed use, optional Skip in the corner.
class StepScaffold extends StatelessWidget {
  const StepScaffold({
    required this.body,
    required this.actions,
    this.onSkip,
    this.skipLabel,
    this.onBack,
    this.backLabel,
    this.scrollable = true,
    super.key,
  });

  final Widget body;
  final List<Widget> actions;
  final VoidCallback? onSkip;
  final String? skipLabel;
  final VoidCallback? onBack;
  final String? backLabel;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s3),
      child: body,
    );
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: Sizes.minTap + Space.s1,
              child: Row(
                children: [
                  if (onBack != null)
                    IconButton(
                      onPressed: onBack,
                      tooltip: backLabel,
                      icon: const BackButtonIcon(),
                    ),
                  const Spacer(),
                  if (onSkip != null)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: Space.s1),
                      child: TextButton(onPressed: onSkip, child: Text(skipLabel ?? '')),
                    ),
                ],
              ),
            ),
            Expanded(
              child: scrollable
                  ? SingleChildScrollView(child: content)
                  : content,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.s3, Space.s1, Space.s3, Space.s2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(height: Space.s1),
                    actions[i],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Large title + supporting line used across flow screens.
class StepHeader extends StatelessWidget {
  const StepHeader({required this.title, this.subtitle, super.key});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: theme.textTheme.displaySmall),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: Space.s1),
          Text(
            subtitle!,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
