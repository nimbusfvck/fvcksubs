import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import '../app_scope.dart';
import '../player/state/source_priority_controller.dart';
import '../player/state/subtitle_preference_controller.dart';
import 'nsfw_controller.dart';
import '../theme/tokens.dart';
import '../widgets/app_page_bar.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context).subtitlePreferenceController;
    final nsfwController = AppScope.of(context).nsfwController;
    return Scaffold(
      appBar: const AppPageBar(title: 'Settings'),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xxl,
          ),
          children: [
            Text(
              'Playback and application preferences.',
              style: AppTypography.bodyMd.copyWith(color: AppColors.onDarkSoft),
            ),
            const SizedBox(height: AppSpacing.lg),
            const _SourcePriorityEntry(),
            const SizedBox(height: AppSpacing.md),
            _SubtitlePreference(controller: controller),
            const SizedBox(height: AppSpacing.md),
            BlocBuilder<NsfwController, NsfwState>(
              bloc: nsfwController,
              builder: (context, state) => _NsfwPreference(
                controller: nsfwController,
                showNsfw: state.showNsfw,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NsfwPreference extends StatelessWidget {
  const _NsfwPreference({required this.controller, required this.showNsfw});

  final NsfwController controller;
  final bool showNsfw;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceDarkElevated,
    borderRadius: AppRadius.lg,
    clipBehavior: Clip.antiAlias,
    child: SwitchListTile(
      value: showNsfw,
      onChanged: (enabled) => _onChanged(context, enabled),
      title: const Text('Show NSFW content'),
      subtitle: const Text(
        'Allow catalogs marked as mature or NSFW to appear in the app.',
      ),
      secondary: const Icon(Icons.visibility_outlined),
    ),
  );

  Future<void> _onChanged(BuildContext context, bool enabled) async {
    if (!enabled) {
      controller.setShowNsfw(false);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        var isAdult = false;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Show NSFW content?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This will show catalogs marked as mature or NSFW. You can '
                  'turn this setting off again at any time.',
                ),
                const SizedBox(height: AppSpacing.sm),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isAdult,
                  onChanged: (value) => setState(() {
                    isAdult = value ?? false;
                  }),
                  title: const Text('I confirm that I am 18 or older.'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: isAdult
                    ? () => Navigator.of(context).pop(true)
                    : null,
                child: const Text('Enable'),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed == true && context.mounted) {
      controller.setShowNsfw(true);
    }
  }
}

class _SourcePriorityEntry extends StatelessWidget {
  const _SourcePriorityEntry();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final count = scope.sourcePriorityController.availableProviders.length;
    return Material(
      color: AppColors.surfaceDarkElevated,
      borderRadius: AppRadius.lg,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.format_list_numbered),
        title: const Text('Source priority'),
        subtitle: Text(
          count == 0
              ? 'No stream providers installed.'
              : 'Choose which provider is tried first.',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: count == 0
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SourcePriorityPage(
                    controller: scope.sourcePriorityController,
                    registry: scope.registry,
                  ),
                ),
              ),
      ),
    );
  }
}

class SourcePriorityPage extends StatelessWidget {
  const SourcePriorityPage({
    super.key,
    required this.controller,
    required this.registry,
  });

  final SourcePriorityController controller;
  final ExtensionRegistry registry;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Source priority'),
      actions: [
        TextButton(onPressed: controller.reset, child: const Text('Reset')),
      ],
    ),
    body: BlocBuilder<SourcePriorityController, SourcePriorityState>(
      bloc: controller,
      builder: (context, _) {
        final providers = controller.availableProviders;
        return ReorderableListView.builder(
          padding: const EdgeInsets.all(AppSpacing.md),
          buildDefaultDragHandles: false,
          header: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              'Drag providers into the order they should be tried. Disabled '
              'providers stay in the list but are skipped during playback.',
              style: AppTypography.bodyMd.copyWith(color: AppColors.onDarkSoft),
            ),
          ),
          itemCount: providers.length,
          onReorderItem: controller.reorder,
          itemBuilder: (context, index) {
            final provider = providers[index];
            final enabled = registry.isProviderEnabled(provider.id);
            return Card(
              key: ValueKey(provider.id),
              margin: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.surfaceDarkHighest,
                  foregroundColor: enabled
                      ? AppColors.brandAccent
                      : AppColors.onDarkSoft,
                  child: Text('${index + 1}'),
                ),
                title: Text(provider.name ?? _providerLabel(provider)),
                subtitle: Text(_extensionName(provider.id)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!enabled)
                      Text(
                        'Disabled',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.onDarkSoft,
                        ),
                      ),
                    const SizedBox(width: AppSpacing.xs),
                    ReorderableDelayedDragStartListener(
                      index: index,
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Semantics(
                          button: true,
                          label:
                              'Reorder ${provider.name ?? _providerLabel(provider)}',
                          child: const Icon(Icons.drag_handle),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );

  String _extensionName(String providerId) {
    for (final manifest in registry.installed) {
      if (manifest.providers.any((provider) => provider.id == providerId)) {
        return manifest.name;
      }
    }
    return providerId;
  }

  static String _providerLabel(ProviderDecl provider) {
    final value = provider.id.split('.').last;
    return value.isEmpty
        ? provider.id
        : '${value[0].toUpperCase()}${value.substring(1)}';
  }
}

class _SubtitlePreference extends StatelessWidget {
  const _SubtitlePreference({required this.controller});

  final SubtitlePreferenceController controller;

  static const (String?, String, String) noPreference = (
    null,
    'No preference',
    'Keep the order provided by the source.',
  );

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
              for (final (code, title, description)
                  in <(String?, String, String)>[
                    noPreference,
                    ...supportedSubtitleLanguages,
                  ])
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
