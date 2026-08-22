import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../models/resolved_source.dart';

List<BetterPlayerAsmsTrack> dedupedQualityTracks(
  List<BetterPlayerAsmsTrack> tracks,
) {
  final byHeight = <int, BetterPlayerAsmsTrack>{};
  for (final track in tracks) {
    final height = track.height ?? 0;
    if (height <= 0) continue;
    final existing = byHeight[height];
    if (existing == null || (track.bitrate ?? 0) > (existing.bitrate ?? 0)) {
      byHeight[height] = track;
    }
  }
  return byHeight.values.toList()
    ..sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));
}

class PlayerSourcePickerSheet extends StatelessWidget {
  const PlayerSourcePickerSheet({
    super.key,
    required this.resolvedSources,
    required this.current,
  });

  final List<ResolvedSource> resolvedSources;
  final ResolvedSource current;

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
                  for (final item in resolvedSources)
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

  final List<BetterPlayerAsmsTrack> tracks;
  final BetterPlayerAsmsTrack? current;

  bool get _autoSelected => (current?.height ?? 0) <= 0;

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
                    ).pop(BetterPlayerAsmsTrack.defaultTrack()),
                  ),
                  for (final track in tracks)
                    ListTile(
                      title: Text(
                        '${track.height}p',
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.onDark,
                        ),
                      ),
                      trailing: !_autoSelected && current == track
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
