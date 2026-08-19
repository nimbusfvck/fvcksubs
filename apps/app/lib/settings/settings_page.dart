import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../player/subtitle_preference_controller.dart';
import '../theme/tokens.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context).subtitlePreferenceController;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.xxl,
        ),
        children: [
          Semantics(
            header: true,
            child: Text(
              'Settings',
              style: AppTypography.displaySm.copyWith(color: AppColors.onDark),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Playback and application preferences.',
            style: AppTypography.bodyMd.copyWith(color: AppColors.onDarkSoft),
          ),
          const SizedBox(height: AppSpacing.lg),
          _SubtitlePreference(controller: controller),
        ],
      ),
    );
  }
}

class _SubtitlePreference extends StatelessWidget {
  const _SubtitlePreference({required this.controller});

  final SubtitlePreferenceController controller;

  static const options = <(String?, String, String)>[
    (null, 'No preference', 'Keep the order provided by the source.'),
    ('id', 'Indonesia', 'Prefer Indonesian subtitles when available.'),
    ('en', 'English', 'Prefer English subtitles when available.'),
  ];

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceDarkElevated,
    borderRadius: AppRadius.lg,
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const Icon(Icons.subtitles_outlined, color: AppColors.onDarkSoft),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Preferred subtitles',
                      style: AppTypography.titleMd.copyWith(
                        color: AppColors.onDark,
                      ),
                    ),
                    Text(
                      'Selected automatically when playback starts.',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onDarkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.hairlineDark),
        RadioGroup<String?>(
          groupValue: controller.languageCode,
          onChanged: controller.select,
          child: Column(
            children: [
              for (final (code, title, description) in options)
                RadioListTile<String?>(
                  value: code,
                  title: Text(
                    title,
                    style: AppTypography.bodyMd.copyWith(
                      color: AppColors.onDark,
                    ),
                  ),
                  subtitle: Text(
                    description,
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onDarkSoft,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
