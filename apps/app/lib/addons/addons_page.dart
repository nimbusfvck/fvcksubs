import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import '../app_scope.dart';
import '../theme/tokens.dart';
import 'addons_controller.dart';
import 'installer_controller.dart';

class AddonsPage extends StatelessWidget {
  const AddonsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return BlocBuilder<AddonsController, AddonsState>(
      bloc: scope.addonsController,
      builder: (context, _) => BlocBuilder<InstallerController, InstallerState>(
        bloc: scope.installerController,
        builder: (context, _) {
          final installed = scope.registry.installed;
          return ListView(
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
                  'Addons',
                  style: AppTypography.displaySm.copyWith(
                    color: AppColors.onDark,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Manage extensions, sources, and playback preferences.',
                style: AppTypography.bodyMd.copyWith(
                  color: AppColors.onDarkSoft,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _RepoSection(controller: scope.installerController),
              const SizedBox(height: AppSpacing.lg),
              _SectionHeader(
                title: 'Installed',
                trailing: installed.isEmpty
                    ? null
                    : '${installed.length} ${installed.length == 1 ? 'extension' : 'extensions'}',
              ),
              const SizedBox(height: AppSpacing.sm),
              if (installed.isEmpty)
                _Panel(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.lg,
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.extension_off_outlined,
                          color: AppColors.onDarkSoft,
                          size: 32,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'No extensions installed.',
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyMd.copyWith(
                            color: AppColors.onDarkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                for (final manifest in installed) ...[
                  _ExtensionTile(
                    manifest: manifest,
                    registry: scope.registry,
                    controller: scope.addonsController,
                    installerController: scope.installerController,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
            ],
          );
        },
      ),
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
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              title: 'Extension repo',
              icon: Icons.cloud_download_outlined,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Check a repository to install or update extensions.',
              style: AppTypography.bodySm.copyWith(color: AppColors.onDarkSoft),
            ),
            const SizedBox(height: AppSpacing.sm),
            LayoutBuilder(
              builder: (context, constraints) {
                final field = TextField(
                  controller: _urlField,
                  enabled: !controller.busy,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  style: AppTypography.bodyMd.copyWith(color: AppColors.onDark),
                  decoration: InputDecoration(
                    labelText: 'Repository URL',
                    hintText: 'https://…/repo.json',
                    prefixIcon: const Icon(Icons.link, size: 19),
                    hintStyle: AppTypography.bodyMd.copyWith(
                      color: AppColors.onDarkSoft,
                    ),
                    isDense: true,
                  ),
                  autofillHints: const [AutofillHints.url],
                  onSubmitted: (_) => _refresh(),
                );
                final button = FilledButton.icon(
                  onPressed: controller.busy ? null : _refresh,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Check'),
                );
                if (constraints.maxWidth < 440) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      field,
                      const SizedBox(height: AppSpacing.sm),
                      button,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: field),
                    const SizedBox(width: AppSpacing.sm),
                    button,
                  ],
                );
              },
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
    final upToDate = listing.isUpToDate;
    final details = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.surfaceDarkHighest,
            borderRadius: AppRadius.md,
          ),
          child: const Icon(
            Icons.extension_outlined,
            color: AppColors.onDarkSoft,
            size: 19,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
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
                  listing.isInstalled
                      ? 'installed ${listing.installedVersion} · repo ${entry.version}'
                      : 'v${entry.version}',
                  if (entry.author != null) 'by ${entry.author}',
                ].join(' · '),
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onDarkSoft,
                ),
              ),
              if (entry.description != null)
                _ExpandableDescription(text: entry.description!, maxLines: 2),
            ],
          ),
        ),
      ],
    );
    final action = upToDate
        ? const _StatusPill(label: 'Up to date', positive: true)
        : !listing.isInstalled
        ? FilledButton(
            onPressed: controller.busy ? null : () => controller.install(entry),
            child: const Text('Install'),
          )
        : OutlinedButton(
            onPressed: controller.busy ? null : () => controller.install(entry),
            child: const Text('Update'),
          );
    return Container(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.hairlineDark)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 400) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                details,
                const SizedBox(height: AppSpacing.sm),
                Align(alignment: Alignment.centerRight, child: action),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: AppSpacing.sm),
              action,
            ],
          );
        },
      ),
    );
  }
}

class _ExtensionTile extends StatelessWidget {
  const _ExtensionTile({
    required this.manifest,
    required this.registry,
    required this.controller,
    required this.installerController,
  });

  final Manifest manifest;
  final ExtensionRegistry registry;
  final AddonsController controller;
  final InstallerController installerController;

  @override
  Widget build(BuildContext context) {
    final enabled = registry.isExtensionEnabled(manifest.id);
    final listing = installerController.listingFor(manifest.id);
    final streamProviders = [
      for (final provider in manifest.providers)
        if (provider.roles.contains(ProviderRole.stream)) provider,
    ];

    return _Panel(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: enabled
                ? AppColors.brandAccent.withValues(alpha: 0.16)
                : AppColors.surfaceDarkHighest,
            borderRadius: AppRadius.md,
          ),
          child: Icon(
            Icons.extension_outlined,
            color: enabled ? AppColors.brandAccent : AppColors.onDarkSoft,
          ),
        ),
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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onDarkSoft,
                ),
              ),
            if (manifest.categories.isNotEmpty)
              Text(
                manifest.categories.join(', '),
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onDarkSoft,
                ),
              ),
            Text(
              [
                'v${manifest.version}',
                if (manifest.author != null) 'by ${manifest.author}',
                '${streamProviders.length} sources',
              ].join(' · '),
              style: AppTypography.caption.copyWith(
                color: AppColors.onDarkSoft,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            if (listing?.isUpdate ?? false)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: installerController.busy
                      ? null
                      : () => installerController.install(listing!.entry),
                  icon: const Icon(Icons.download_outlined, size: 17),
                  label: Text('Update to v${listing!.entry.version}'),
                ),
              )
            else if (listing?.isUpToDate ?? false)
              const _StatusPill(label: 'Up to date', positive: true)
            else if (installerController.busy &&
                installerController.repoUrl != null)
              Text(
                'Checking for updates…',
                style: AppTypography.caption.copyWith(
                  color: AppColors.onDarkSoft,
                ),
              ),
          ],
        ),
        trailing: Switch(
          value: enabled,
          onChanged: (value) =>
              controller.setExtensionEnabled(manifest.id, value),
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _ExtensionDetailsPage(
              manifest: manifest,
              registry: registry,
              controller: controller,
              installerController: installerController,
            ),
          ),
        ),
      ),
    );
  }
}

class _ExtensionDetailsPage extends StatelessWidget {
  const _ExtensionDetailsPage({
    required this.manifest,
    required this.registry,
    required this.controller,
    required this.installerController,
  });

  final Manifest manifest;
  final ExtensionRegistry registry;
  final AddonsController controller;
  final InstallerController installerController;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(manifest.name)),
    body: BlocBuilder<AddonsController, AddonsState>(
      bloc: controller,
      builder: (context, _) {
        final enabled = registry.isExtensionEnabled(manifest.id);
        final providers = [
          for (final provider in manifest.providers)
            if (provider.roles.contains(ProviderRole.stream)) provider,
        ];
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (manifest.description != null) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.md,
                        AppSpacing.md,
                        AppSpacing.sm,
                      ),
                      child: Text(
                        manifest.description!,
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.onDarkSoft,
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.hairlineDark),
                  ],
                  SwitchListTile(
                    title: Text(manifest.name),
                    subtitle: const Text('Extension enabled'),
                    value: enabled,
                    onChanged: (value) =>
                        controller.setExtensionEnabled(manifest.id, value),
                  ),
                  for (final provider in providers)
                    SwitchListTile(
                      secondary: const Icon(Icons.play_circle_outline),
                      title: Text(provider.name ?? _providerLabel(provider.id)),
                      value: enabled && registry.isProviderEnabled(provider.id),
                      onChanged: enabled
                          ? (value) => controller.setProviderEnabled(
                              provider.id,
                              value,
                            )
                          : null,
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: installerController.busy
                  ? null
                  : () => _remove(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
              ),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove extension'),
            ),
          ],
        );
      },
    ),
  );

  Future<void> _remove(BuildContext context) async {
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${manifest.name}?'),
        content: const Text(
          'The extension and its downloaded code will be removed. Library '
          'items and watch history will stay available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.primary,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await installerController.uninstall(manifest.id);
    if (navigator.mounted) navigator.pop();
  }
}

String _providerLabel(String providerId) {
  final name = providerId.split('.').last;
  if (name.isEmpty) return providerId;
  return name[0].toUpperCase() + name.substring(1);
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceDarkElevated,
    borderRadius: AppRadius.lg,
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.icon, this.trailing});

  final String title;
  final IconData? icon;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 19, color: AppColors.onDarkSoft),
          const SizedBox(width: AppSpacing.xs),
        ],
        Expanded(
          child: Text(
            title,
            style: AppTypography.titleMd.copyWith(color: AppColors.onDark),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: AppTypography.caption.copyWith(color: AppColors.onDarkSoft),
          ),
      ],
    ),
  );
}

class _ExpandableDescription extends StatefulWidget {
  const _ExpandableDescription({required this.text, required this.maxLines});

  final String text;
  final int maxLines;

  @override
  State<_ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<_ExpandableDescription> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = AppTypography.bodySm.copyWith(color: AppColors.onDarkSoft);
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: style),
        maxLines: widget.maxLines,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: constraints.maxWidth);
      final overflows = painter.didExceedMaxLines;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.text,
            maxLines: _expanded ? null : widget.maxLines,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: style,
          ),
          if (overflows || _expanded)
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(48, 44),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              child: Text(_expanded ? 'Show less' : 'Show more'),
            ),
        ],
      );
    },
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, this.positive = false});

  final String label;
  final bool positive;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: positive
          ? AppColors.success.withValues(alpha: 0.14)
          : AppColors.surfaceDarkHighest,
      borderRadius: AppRadius.pill,
    ),
    child: Text(
      label,
      style: AppTypography.caption.copyWith(
        color: positive ? AppColors.success : AppColors.onDarkSoft,
      ),
    ),
  );
}
