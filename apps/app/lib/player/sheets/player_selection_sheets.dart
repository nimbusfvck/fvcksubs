import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../models/resolved_source.dart';
import '../models/app_player_controller.dart';

List<AppQualityTrack> dedupedQualityTracks(List<AppQualityTrack> tracks) {
  final byHeight = <int, AppQualityTrack>{};
  for (final track in tracks) {
    final height = track.height;
    if (height <= 0) continue;
    final existing = byHeight[height];
    if (existing == null || (track.bitrate ?? 0) > (existing.bitrate ?? 0)) {
      byHeight[height] = track;
    }
  }
  return byHeight.values.toList()..sort((a, b) => b.height.compareTo(a.height));
}

class PlayerSourcePickerSheet extends StatelessWidget {
  const PlayerSourcePickerSheet({
    super.key,
    required this.resolvedSources,
    required this.current,
    this.providerNames = const {},
  });

  final List<ResolvedSource> resolvedSources;
  final ResolvedSource current;
  final Map<String, String> providerNames;

  Map<String, List<ResolvedSource>> _groupedSources() {
    final groups = <String, List<ResolvedSource>>{};
    for (final source in resolvedSources) {
      final providerId = source.source.providerId;
      final providerName =
          providerNames[providerId] ??
          (source.source.provider.isNotEmpty
              ? source.source.provider
              : providerId.isNotEmpty
              ? providerId.split('.').last
              : 'Unknown provider');
      groups.putIfAbsent(providerName, () => []).add(source);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.6;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.hairlineDark,
                borderRadius: AppRadius.pill,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Video Sources',
              style: AppTypography.titleMd.copyWith(color: AppColors.onDark),
            ),
            const SizedBox(height: AppSpacing.xs),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final group in _groupedSources().entries) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.sm,
                        AppSpacing.md,
                        AppSpacing.xs,
                      ),
                      child: Text(
                        group.key,
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.onDarkSoft,
                        ),
                      ),
                    ),
                    for (final item in group.value)
                      ListTile(
                        title: Text(
                          item.source.label,
                          style: AppTypography.bodyMd.copyWith(
                            color: AppColors.onDark,
                          ),
                        ),
                        subtitle: _subtitleSummary(item),
                        trailing: item.source.id == current.source.id
                            ? const Icon(
                                Icons.check,
                                color: AppColors.brandAccent,
                              )
                            : null,
                        onTap: () => Navigator.of(context).pop(item),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

class PlayerQualityPickerSheet extends StatelessWidget {
  const PlayerQualityPickerSheet({
    super.key,
    required this.tracks,
    required this.current,
  });

  final List<AppQualityTrack> tracks;
  final AppQualityTrack? current;

  bool get _autoSelected => current == null;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.6;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.hairlineDark,
                borderRadius: AppRadius.pill,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Quality',
              style: AppTypography.titleMd.copyWith(color: AppColors.onDark),
            ),
            const SizedBox(height: AppSpacing.xs),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    title: Text(
                      'Auto',
                      style: AppTypography.bodyMd.copyWith(
                        color: AppColors.onDark,
                      ),
                    ),
                    trailing: _autoSelected
                        ? const Icon(Icons.check, color: AppColors.brandAccent)
                        : null,
                    onTap: () => Navigator.of(
                      context,
                    ).pop(const AppQualityTrack(id: 'auto', height: 0)),
                  ),
                  for (final track in tracks)
                    ListTile(
                      title: Text(
                        '${track.height}p',
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.onDark,
                        ),
                      ),
                      trailing: !_autoSelected && current?.id == track.id
                          ? const Icon(
                              Icons.check,
                              color: AppColors.brandAccent,
                            )
                          : null,
                      onTap: () => Navigator.of(context).pop(track),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

class PlayerAudioPickerSheet extends StatelessWidget {
  const PlayerAudioPickerSheet({
    super.key,
    required this.tracks,
    required this.current,
  });

  final List<AppAudioTrack> tracks;
  final AppAudioTrack? current;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.6;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.hairlineDark,
                borderRadius: AppRadius.pill,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Audio',
              style: AppTypography.titleMd.copyWith(color: AppColors.onDark),
            ),
            const SizedBox(height: AppSpacing.xs),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (index, track) in tracks.indexed)
                    ListTile(
                      title: Text(
                        track.label == 'Audio'
                            ? 'Audio ${index + 1}'
                            : track.label,
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.onDark,
                        ),
                      ),
                      subtitle:
                          track.language == null || track.language!.isEmpty
                          ? null
                          : Text(
                              track.language!,
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.onDarkSoft,
                              ),
                            ),
                      trailing: current?.id == track.id
                          ? const Icon(
                              Icons.check,
                              color: AppColors.brandAccent,
                            )
                          : null,
                      onTap: () => Navigator.of(context).pop(track),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

Widget? _subtitleSummary(ResolvedSource source) {
  final languages = <String>{
    for (final track in source.stream.subtitles)
      if (track.language.isNotEmpty) track.language.split(RegExp('[-_]')).first,
  };
  if (languages.isEmpty) return null;
  final ordered = languages.toList()..sort();
  return Text(
    'Subtitles: ${ordered.join(', ')}',
    style: AppTypography.bodySm.copyWith(color: AppColors.onDarkSoft),
  );
}
