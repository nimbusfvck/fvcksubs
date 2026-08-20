import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import '../app_scope.dart';
import '../theme/tokens.dart';
import '../widgets/app_page_bar.dart';
import '../widgets/empty_state.dart';
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
          return Scaffold(
            appBar: const AppPageBar(title: 'Addons'),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    _AddExtensionDialog(controller: scope.installerController),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
              tooltip: 'Add extension',
            ),
            body: installed.isEmpty
                ? const Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: EmptyState(
                            title: 'No extensions installed.',
                            description:
                                'Tap Add to load a repository and install an extension.',
                            icon: Icons.extension_off_outlined,
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.xxl,
                    ),
                    children: [
                      _SectionHeader(
                        title: 'Installed',
                        trailing:
                            '${installed.length} ${installed.length == 1 ? 'extension' : 'extensions'}',
                      ),
                      const SizedBox(height: AppSpacing.sm),
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
                  ),
          );
        },
      ),
    );
  }
}

class _AddExtensionDialog extends StatefulWidget {
  const _AddExtensionDialog({required this.controller});

  final InstallerController controller;

  @override
  State<_AddExtensionDialog> createState() => _AddExtensionDialogState();
}

class _AddExtensionDialogState extends State<_AddExtensionDialog> {
  late final TextEditingController _urlField = TextEditingController(
    text: widget.controller.repoUrl ?? '',
  );

  @override
  void dispose() {
    _urlField.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    await widget.controller.setRepoUrl(_urlField.text);
    await widget.controller.refresh();
    if (!mounted || widget.controller.listings.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _ExtensionSelectionDialog(controller: widget.controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(560.0, screenSize.width - 80.0);
    return AlertDialog(
      title: const Text('Add extension'),
      content: SizedBox(
        width: dialogWidth,
        child: BlocBuilder<InstallerController, InstallerState>(
          bloc: controller,
          builder: (context, _) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Load a repository to install an extension.',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.onDarkSoft,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
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
                  onSubmitted: (_) => _check(),
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: controller.busy ? null : _check,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Check'),
                  ),
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
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _ExtensionSelectionDialog extends StatelessWidget {
  const _ExtensionSelectionDialog({required this.controller});

  final InstallerController controller;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(560.0, screenSize.width - 80.0);
    return AlertDialog(
      title: const Text('Available extensions'),
      content: SizedBox(
        width: dialogWidth,
        child: BlocBuilder<InstallerController, InstallerState>(
          bloc: controller,
          builder: (context, _) {
            final listings = controller.installableListings;
            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: screenSize.height * 0.68),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Choose which extensions to install.',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onDarkSoft,
                      ),
                    ),
                    if (controller.busy) ...[
                      const SizedBox(height: AppSpacing.sm),
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
                    if (!controller.busy && listings.isEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'All extensions from this repository are installed.',
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.onDarkSoft,
                        ),
                      ),
                    ],
                    for (final listing in listings) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _ListingRow(listing: listing, controller: controller),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
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
                  'v${entry.version}',
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
    final action = FilledButton(
      onPressed: controller.busy ? null : () => controller.install(entry),
      child: const Text('Install'),
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
            if (listing?.isUpdate ?? false)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.system_update_alt_outlined,
                      size: 14,
                      color: AppColors.brandAccent,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Flexible(
                      child: Text(
                        'Version ${listing!.entry.version} available',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.brandAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
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
    body: BlocBuilder<InstallerController, InstallerState>(
      bloc: installerController,
      builder: (context, _) => BlocBuilder<AddonsController, AddonsState>(
        bloc: controller,
        builder: (context, _) {
          final currentManifest = registry.installed.firstWhere(
            (value) => value.id == manifest.id,
            orElse: () => manifest,
          );
          final enabled = registry.isExtensionEnabled(currentManifest.id);
          final listing = installerController.listingFor(currentManifest.id);
          final providers = [
            for (final provider in currentManifest.providers)
              if (provider.roles.contains(ProviderRole.stream)) provider,
          ];
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (currentManifest.description != null) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.md,
                          AppSpacing.md,
                          AppSpacing.sm,
                        ),
                        child: Text(
                          currentManifest.description!,
                          style: AppTypography.bodyMd.copyWith(
                            color: AppColors.onDarkSoft,
                          ),
                        ),
                      ),
                      const Divider(height: 1, color: AppColors.hairlineDark),
                    ],
                    SwitchListTile(
                      title: Text(currentManifest.name),
                      subtitle: const Text('Extension enabled'),
                      value: enabled,
                      onChanged: (value) => controller.setExtensionEnabled(
                        currentManifest.id,
                        value,
                      ),
                    ),
                    for (final provider in providers)
                      SwitchListTile(
                        secondary: const Icon(Icons.play_circle_outline),
                        title: Text(
                          provider.name ?? _providerLabel(provider.id),
                        ),
                        value:
                            enabled && registry.isProviderEnabled(provider.id),
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
              const SizedBox(height: AppSpacing.md),
              _Panel(
                child: _ReleaseDetails(
                  manifest: currentManifest,
                  listing: listing,
                  checking:
                      installerController.busy &&
                      installerController.repoUrl != null,
                  onUpdate: listing?.isUpdate == true
                      ? () => installerController.install(listing!.entry)
                      : null,
                  onCheckUpdates: installerController.repoUrl == null
                      ? null
                      : () => installerController.refresh(),
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

class _ReleaseDetails extends StatelessWidget {
  const _ReleaseDetails({
    required this.manifest,
    required this.listing,
    required this.checking,
    required this.onUpdate,
    required this.onCheckUpdates,
  });

  final Manifest manifest;
  final RepoListing? listing;
  final bool checking;
  final VoidCallback? onUpdate;
  final VoidCallback? onCheckUpdates;

  @override
  Widget build(BuildContext context) {
    final entry = listing?.entry;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Release',
            style: AppTypography.titleMd.copyWith(color: AppColors.onDark),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            entry == null
                ? 'Installed v${manifest.version}'
                : 'Installed v${manifest.version} · latest v${entry.version}',
            style: AppTypography.bodySm.copyWith(color: AppColors.onDarkSoft),
          ),
          if (entry?.author != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Published by ${entry!.author}',
              style: AppTypography.bodySm.copyWith(color: AppColors.onDarkSoft),
            ),
          ],
          if (entry?.description != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              entry!.description!,
              style: AppTypography.bodyMd.copyWith(color: AppColors.onDarkSoft),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (checking)
            Text(
              'Checking for updates…',
              style: AppTypography.bodySm.copyWith(color: AppColors.onDarkSoft),
            )
          else if (onUpdate != null)
            OutlinedButton.icon(
              onPressed: onUpdate,
              icon: const Icon(Icons.download_outlined, size: 17),
              label: Text('Update to v${entry!.version}'),
            )
          else if (listing?.isUpToDate ?? false)
            const _StatusPill(label: 'Up to date', positive: true)
          else
            const _StatusPill(label: 'Update status unavailable'),
          if (onUpdate == null) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: checking ? null : onCheckUpdates,
              icon: checking
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 17),
              label: Text(
                checking ? 'Checking for updates…' : 'Check for updates',
              ),
            ),
          ],
          if (entry?.releaseNotes.isNotEmpty ?? false) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              'What’s new',
              style: AppTypography.titleSm.copyWith(color: AppColors.onDark),
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final note in entry!.releaseNotes)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 7),
                      child: Icon(
                        Icons.circle,
                        size: 5,
                        color: AppColors.onDarkSoft,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        note,
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.onDarkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
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
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Row(
      children: [
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
