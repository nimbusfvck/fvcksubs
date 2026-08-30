import 'package:flutter/material.dart';

import '../player/state/quality_preference_controller.dart';
import '../theme/tokens.dart';

class QualityPreferenceEntry extends StatelessWidget {
  const QualityPreferenceEntry({super.key, required this.controller});

  final QualityPreferenceController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Material(
      color: AppColors.surfaceDarkElevated,
      borderRadius: AppRadius.lg,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.hd_outlined),
        title: const Text('Preferred quality'),
        subtitle: Text(
          controller.maxHeight == null
              ? 'Use the player\'s automatic quality selection.'
              : 'Use up to ${controller.maxHeight}p when available.',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => QualityPreferencePage(controller: controller),
          ),
        ),
      ),
    ),
  );
}

class QualityPreferencePage extends StatelessWidget {
  const QualityPreferencePage({super.key, required this.controller});

  final QualityPreferenceController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Preferred quality')),
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            'Choose the highest video quality the player should select '
            'automatically. You can still switch quality from the player.',
            style: AppTypography.bodyMd.copyWith(color: AppColors.onDarkSoft),
          ),
          const SizedBox(height: AppSpacing.md),
          Material(
            color: AppColors.surfaceDarkElevated,
            borderRadius: AppRadius.lg,
            clipBehavior: Clip.antiAlias,
            child: RadioGroup<int?>(
              groupValue: controller.maxHeight,
              onChanged: controller.select,
              child: Column(
                children: [
                  const RadioListTile<int?>(
                    value: null,
                    title: Text('Auto'),
                    subtitle: Text('Let the player adapt to the connection.'),
                  ),
                  for (final height in preferredQualityHeights)
                    RadioListTile<int?>(
                      value: height,
                      title: Text('${height}p'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
