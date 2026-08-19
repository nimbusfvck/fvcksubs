import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import '../app_scope.dart';
import '../player/subtitle_preference_controller.dart';
import '../theme/tokens.dart';
import 'addons_controller.dart';
import 'installer_controller.dart';

class AddonsPage extends StatelessWidget {
  const AddonsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        scope.addonsController,
        scope.installerController,
        scope.subtitlePreferenceController,
      ]),
      builder: (context, _) {
        final installed = scope.registry.installed;
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            _SubtitlePreferenceSection(
              controller: scope.subtitlePreferenceController,
            ),
            const SizedBox(height: AppSpacing.md),
            _RepoSection(controller: scope.installerController),
            const SizedBox(height: AppSpacing.md),
            if (installed.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Text(
                  'No extensions installed.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMd.copyWith(
                    color: AppColors.onDarkSoft,
                  ),
                ),
              )
            else
              for (final manifest in installed) ...[
                _ExtensionTile(
                  manifest: manifest,
                  registry: scope.registry,
                  controller: scope.addonsController,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
          ],
        );
      },
    );
  }
}

class _RepoSection extends StatefulWidget {
  const _RepoSection({required this.controller});

  final InstallerController controller;

  @override
  State<_RepoSection> createState() => _RepoSectionState();
}

class _RepoSectionState extends State<_RepoSection> {
  late final TextEditingController _urlField = TextEditingController(
    text: widget.controller.repoUrl ?? '',
  );

  @override
  void dispose() {
    _urlField.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await widget.controller.setRepoUrl(_urlField.text);
    await widget.controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Material(
      color: AppColors.surfaceDarkElevated,
      borderRadius: AppRadius.lg,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Extension repo',
              style: AppTypography.titleMd.copyWith(color: AppColors.onDark),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlField,
                    enabled: !controller.busy,
                    autocorrect: false,
                    keyboardType: TextInputType.url,
                    style: AppTypography.bodyMd.copyWith(
                      color: AppColors.onDark,
                    ),
                    decoration: InputDecoration(
                      hintText: 'https://…/repo.json',
                      hintStyle: AppTypography.bodyMd.copyWith(
                        color: AppColors.onDarkSoft,
                      ),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _refresh(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: controller.busy ? null : _refresh,
                  child: const Text('Check'),
                ),
              ],
            ),
            if (controller.busy) ...[
              const SizedBox(height: AppSpacing.md),
              const LinearProgressIndicator(),
            ],
            if (controller.error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                controller.error!,
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.liveAccent,
                ),
              ),
            ],
            for (final listing in controller.listings) ...[
              const SizedBox(height: AppSpacing.sm),
              _ListingRow(listing: listing, controller: controller),
            ],
          ],
        ),
      ),
    );
  }
}

class _ListingRow extends StatelessWidget {
  const _ListingRow({required this.listing, required this.controller});

  final RepoListing listing;
  final InstallerController controller;

  @override
  Widget build(BuildContext context) {
    final entry = listing.entry;
    final upToDate =
        listing.isUpdate && listing.installedVersion == entry.version;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.name,
                style: AppTypography.bodyMd.copyWith(color: AppColors.onDark),
              ),
              Text(
                [
                  listing.isUpdate
                      ? 'installed ${listing.installedVersion} · repo ${entry.version}'
                      : 'v${entry.version}',
                  if (entry.author != null) 'by ${entry.author}',
                ].join(' · '),
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onDarkSoft,
                ),
              ),
              if (entry.description != null)
                Text(
                  entry.description!,
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.onDarkSoft,
                  ),
                ),
            ],
          ),
        ),
        if (upToDate)
          Text(
            'Up to date',
            style: AppTypography.bodySm.copyWith(color: AppColors.onDarkSoft),
          )
        else
          FilledButton.tonal(
            onPressed: controller.busy ? null : () => controller.install(entry),
            child: Text(listing.isUpdate ? 'Update' : 'Install'),
          ),
      ],
    );
  }
}

class _ExtensionTile extends StatelessWidget {
  const _ExtensionTile({
    required this.manifest,
    required this.registry,
    required this.controller,
  });

  final Manifest manifest;
  final ExtensionRegistry registry;
  final AddonsController controller;

  @override
  Widget build(BuildContext context) {
    final enabled = registry.isExtensionEnabled(manifest.id);
    final streamProviders = [
      for (final provider in manifest.providers)
        if (provider.roles.contains(ProviderRole.stream)) provider,
    ];

    return Material(
      color: AppColors.surfaceDarkElevated,
      borderRadius: AppRadius.lg,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            title: Text(
              manifest.name,
              style: AppTypography.titleMd.copyWith(color: AppColors.onDark),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (manifest.description != null)
                  Text(
                    manifest.description!,
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onDarkSoft,
                    ),
                  ),
                Text(
                  [
                    manifest.categories.join(', '),
                    if (manifest.author != null) 'by ${manifest.author}',
                  ].join(' · '),
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.onDarkSoft,
                  ),
                ),
              ],
            ),
            value: enabled,
            onChanged: (value) =>
                controller.setExtensionEnabled(manifest.id, value),
          ),
          for (final provider in streamProviders)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.md),
              child: SwitchListTile(
                dense: true,
                title: Text(
                  _sourceLabel(provider.id),
                  style: AppTypography.bodyMd.copyWith(
                    color: enabled ? AppColors.onDark : AppColors.onDarkSoft,
                  ),
                ),
                value: enabled && registry.isProviderEnabled(provider.id),
                onChanged: enabled
                    ? (value) =>
                          controller.setProviderEnabled(provider.id, value)
                    : null,
              ),
            ),
        ],
      ),
    );
  }

  static String _sourceLabel(String providerId) {
    final name = providerId.split('.').last;
    if (name.isEmpty) return providerId;
    return name[0].toUpperCase() + name.substring(1);
  }
}

class _SubtitlePreferenceSection extends StatelessWidget {
  const _SubtitlePreferenceSection({required this.controller});

  final SubtitlePreferenceController controller;

  static const List<(String?, String)> _options = [
    (null, 'No preference'),
    ('id', 'Indonesia'),
    ('en', 'English'),
  ];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Preferred subtitles',
        style: AppTypography.titleMd.copyWith(color: AppColors.onDark),
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'Played first when a source has it.',
        style: AppTypography.bodySm.copyWith(color: AppColors.onDarkSoft),
      ),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        spacing: AppSpacing.xs,
        children: [
          for (final (code, label) in _options)
            ChoiceChip(
              label: Text(label),
              selected: controller.languageCode == code,
              onSelected: (_) => controller.select(code),
              showCheckmark: false,
              labelStyle: AppTypography.bodySm.copyWith(
                color: controller.languageCode == code
                    ? AppColors.surfaceDark
                    : AppColors.onDark,
              ),
              backgroundColor: AppColors.surfaceDarkContainer,
              selectedColor: AppColors.onDark,
              side: BorderSide.none,
              shape: RoundedRectangleBorder(borderRadius: AppRadius.pill),
            ),
        ],
      ),
    ],
  );
}
