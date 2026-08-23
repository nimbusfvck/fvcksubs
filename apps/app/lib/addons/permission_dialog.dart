import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../theme/tokens.dart';
import 'installer_controller.dart';

Future<bool> showPermissionDialog(
  BuildContext context,
  PermissionRequest request,
) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => _PermissionDialog(request: request),
  );
  return accepted ?? false;
}

class _PermissionDialog extends StatelessWidget {
  const _PermissionDialog({required this.request});

  final PermissionRequest request;

  @override
  Widget build(BuildContext context) {
    final entry = request.entry;
    return AlertDialog(
      scrollable: true,
      backgroundColor: AppColors.surfaceDarkElevated,
      title: Text(
        request.isUpdate ? 'Update ${entry.name}?' : 'Install ${entry.name}?',
        style: AppTypography.titleMd.copyWith(color: AppColors.onDark),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              if (request.isUpdate && request.installedVersion != null)
                'Version ${request.installedVersion} → ${entry.version}'
              else
                'Version ${entry.version}',
              if (entry.author != null) 'by ${entry.author}',
              if (entry.contentRating == ContentRating.mature)
                'Content rating: Mature / NSFW'
              else if (entry.contentRating == ContentRating.general)
                'Content rating: General',
            ].join(' · '),
            style: AppTypography.bodySm.copyWith(color: AppColors.onDarkSoft),
          ),
          if (!request.isUpdate && entry.description != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              entry.description!,
              style: AppTypography.bodyMd.copyWith(color: AppColors.onDark),
            ),
          ],
          if (entry.releaseNotes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              request.isUpdate ? "What's new" : 'Release notes',
              style: AppTypography.titleSm.copyWith(color: AppColors.onDark),
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final note
                in (request.isUpdate
                    ? entry.releaseNotes.take(1)
                    : entry.releaseNotes))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  '• $note',
                  style: AppTypography.bodyMd.copyWith(
                    color: AppColors.onDarkSoft,
                  ),
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (request.isUpdate && request.newHosts.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                'Network access',
                style: AppTypography.bodyMd.copyWith(color: AppColors.onDark),
              ),
              collapsedIconColor: AppColors.onDarkSoft,
              collapsedTextColor: AppColors.onDark,
              iconColor: AppColors.onDark,
              textColor: AppColors.onDark,
              children: [_NetworkAccessDetails(request: request)],
            )
          else if (!request.isUpdate)
            _NetworkAccessDetails(request: request),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(request.isUpdate ? 'Update' : 'Install'),
        ),
      ],
    );
  }
}

class _NetworkAccessDetails extends StatelessWidget {
  const _NetworkAccessDetails({required this.request});

  final PermissionRequest request;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (request.newHosts.isEmpty)
        Text(
          request.isUpdate
              ? 'This update requests no new network access.'
              : 'This extension requests no network access.',
          style: AppTypography.bodyMd.copyWith(color: AppColors.onDark),
        )
      else ...[
        Text(
          request.isUpdate
              ? 'This update wants access to new sites:'
              : 'This extension will be able to reach:',
          style: AppTypography.bodyMd.copyWith(color: AppColors.onDark),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final host in request.newHosts)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              '• ${describeHostPattern(host)}',
              style: AppTypography.bodyMd.copyWith(color: AppColors.liveAccent),
            ),
          ),
      ],
      if (request.alreadyGrantedHosts.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        Text(
          'Already allowed:',
          style: AppTypography.bodySm.copyWith(color: AppColors.onDarkSoft),
        ),
        const SizedBox(height: 2),
        for (final host in request.alreadyGrantedHosts)
          Text(
            '• ${describeHostPattern(host)}',
            style: AppTypography.bodySm.copyWith(color: AppColors.onDarkSoft),
          ),
      ],
    ],
  );
}

/// A host pattern as the person approving it needs to read it.
///
/// `*` is an allowlist opt-out rather than a host, and rendering it verbatim
/// would show a bullet saying nothing. Spell out what is actually granted so
/// consent is informed.
String describeHostPattern(String host) =>
    host.trim() == '*' ? 'Any site (unrestricted network access)' : host;
