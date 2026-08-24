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

const double _refreshControlSize = 40;

class PlayerSourcePickerSheet extends StatefulWidget {
  const PlayerSourcePickerSheet({
    super.key,
    required this.resolvedSources,
    required this.current,
    this.providerNames = const {},
    this.onRefresh,
  });

  final List<ResolvedSource> resolvedSources;
  final ResolvedSource current;
  final Map<String, String> providerNames;

  /// Runs discovery again and returns the merged list, or null to hide the
  /// control. Discovery covers every provider on one shared budget, so a
  /// provider that was slow when playback started contributes nothing and
  /// gets no second chance on its own — this is how the user asks for one.
  final Future<List<ResolvedSource>> Function()? onRefresh;

  @override
  State<PlayerSourcePickerSheet> createState() =>
      _PlayerSourcePickerSheetState();
}

class _PlayerSourcePickerSheetState extends State<PlayerSourcePickerSheet> {
  late List<ResolvedSource> _sources = widget.resolvedSources;
  bool _refreshing = false;

  Future<void> _refresh() async {
    final onRefresh = widget.onRefresh;
    // The page holds the real guard; this one keeps the control from looking
    // tappable while its own request is still out.
    if (onRefresh == null || _refreshing) return;
    setState(() => _refreshing = true);
    try {
      final merged = await onRefresh();
      if (mounted) setState(() => _sources = merged);
    } catch (_) {
      // Discovery is already failure-tolerant and answers with an empty list,
      // so reaching here means something unexpected. Keep the list that is
      // playing and hand the control back rather than taking the sheet down.
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Map<String, List<ResolvedSource>> _groupedSources() {
    final providerNames = widget.providerNames;
    final groups = <String, List<ResolvedSource>>{};
    for (final source in _sources) {
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: [
                  // Balances the control so the title stays optically centred.
                  const SizedBox(width: _refreshControlSize),
                  Expanded(
                    child: Text(
                      'Video Sources',
                      textAlign: TextAlign.center,
                      style: AppTypography.titleMd.copyWith(
                        color: AppColors.onDark,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _refreshControlSize,
                    height: _refreshControlSize,
                    child: widget.onRefresh == null
                        ? null
                        : _refreshing
                        ? const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.onDarkSoft,
                              ),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.refresh),
                            color: AppColors.onDark,
                            iconSize: 20,
                            tooltip: 'Look for more sources',
                            onPressed: _refresh,
                          ),
                  ),
                ],
              ),
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
                        trailing: item.source.id == widget.current.source.id
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
                        audioTrackPickerLabel(track, index),
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
