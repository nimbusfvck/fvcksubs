import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../../app_scope.dart';
import '../../theme/tokens.dart';
import '../mappers/stream_player_mapping.dart'
    show subtitleLanguageLabel, subtitlesForPicker;
import '../models/app_player_controller.dart';
import '../models/playback_media.dart';

class PlayerSubtitlePickerSheet extends StatefulWidget {
  const PlayerSubtitlePickerSheet({
    super.key,
    required this.media,
    required this.tracks,
    required this.current,
    required this.filterTracks,
  });

  final PlaybackMedia media;
  final List<SubtitleTrack> tracks;
  final SubtitleTrack? current;
  final List<SubtitleTrack> Function(List<SubtitleTrack> tracks) filterTracks;

  @override
  State<PlayerSubtitlePickerSheet> createState() =>
      _PlayerSubtitlePickerSheetState();
}

enum _ExternalFetchState { idle, loading, foundNone }

class _PlayerSubtitlePickerSheetState extends State<PlayerSubtitlePickerSheet> {
  _SubtitleGroup? _expanded;
  List<SubtitleTrack> _externalTracks = const [];
  _ExternalFetchState _externalState = _ExternalFetchState.idle;

  List<_SubtitleGroup> get _groups {
    final merged = subtitlesForPicker([...widget.tracks, ..._externalTracks]);
    final byLabel = <String, List<SubtitleTrack>>{};
    for (final track in merged) {
      (byLabel[subtitleLanguageLabel(track.language)] ??= []).add(track);
    }
    return [
      for (final entry in byLabel.entries)
        _SubtitleGroup(label: entry.key, tracks: entry.value),
    ];
  }

  Future<void> _fetchExternal() async {
    setState(() => _externalState = _ExternalFetchState.loading);
    final registry = AppScope.of(context).registry;
    final fetched = await registry.externalSubtitles(widget.media.item);
    if (!mounted) return;
    final visibleTracks = widget.filterTracks(fetched);
    setState(() {
      _externalTracks = visibleTracks;
      _externalState = visibleTracks.isEmpty
          ? _ExternalFetchState.foundNone
          : _ExternalFetchState.idle;
    });
  }

  PlayerSubtitleSelection _sourceFor(SubtitleTrack track) =>
      PlayerSubtitleSelection.track(track);

  PlayerSubtitleSelection _offSource() => const PlayerSubtitleSelection.off();

  bool get _offSelected => widget.current == null;

  bool _isSelected(SubtitleTrack track) {
    final current = widget.current;
    return current?.url == track.url;
  }

  String _variantName(SubtitleTrack track, int index) =>
      track.label.isNotEmpty ? track.label : 'Option ${index + 1}';

  @override
  Widget build(BuildContext context) {
    final expanded = _expanded;
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
            Row(
              children: [
                SizedBox(
                  width: 40,
                  child: expanded == null
                      ? null
                      : IconButton(
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 18,
                          ),
                          color: AppColors.onDark,
                          onPressed: () => setState(() => _expanded = null),
                        ),
                ),
                Expanded(
                  child: Text(
                    expanded?.label ?? 'Subtitles (CC)',
                    textAlign: TextAlign.center,
                    style: AppTypography.titleMd.copyWith(
                      color: AppColors.onDark,
                    ),
                  ),
                ),
                const SizedBox(width: 40),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: expanded == null
                    ? [
                        ListTile(
                          title: Text(
                            'Off',
                            style: AppTypography.bodyMd.copyWith(
                              color: AppColors.onDark,
                            ),
                          ),
                          trailing: _offSelected
                              ? const Icon(
                                  Icons.check,
                                  color: AppColors.brandAccent,
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(_offSource()),
                        ),
                        for (final group in _groups)
                          ListTile(
                            title: Text(
                              group.tracks.length > 1
                                  ? '${group.label} (${group.tracks.length})'
                                  : group.label,
                              style: AppTypography.bodyMd.copyWith(
                                color: AppColors.onDark,
                              ),
                            ),
                            trailing: group.tracks.any(_isSelected)
                                ? const Icon(
                                    Icons.check,
                                    color: AppColors.brandAccent,
                                  )
                                : group.tracks.length > 1
                                ? const Icon(
                                    Icons.chevron_right_rounded,
                                    color: AppColors.onDarkSoft,
                                  )
                                : null,
                            onTap: () {
                              if (group.tracks.length == 1) {
                                Navigator.of(
                                  context,
                                ).pop(_sourceFor(group.tracks.first));
                              } else {
                                setState(() => _expanded = group);
                              }
                            },
                          ),
                        const Divider(color: AppColors.hairlineDark, height: 1),
                        ListTile(
                          leading: _externalState == _ExternalFetchState.loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.onDarkSoft,
                                  ),
                                )
                              : const Icon(
                                  Icons.cloud_download_rounded,
                                  color: AppColors.onDarkSoft,
                                ),
                          title: Text(
                            _externalState == _ExternalFetchState.foundNone
                                ? 'No supported external subtitles found'
                                : 'Fetch external subtitles',
                            style: AppTypography.bodyMd.copyWith(
                              color: AppColors.onDarkSoft,
                            ),
                          ),
                          subtitle: Text(
                            'A fallback if the ones above are missing, out of sync, or erroring',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.onDarkSoft,
                            ),
                          ),
                          enabled:
                              _externalState != _ExternalFetchState.loading,
                          onTap: _fetchExternal,
                        ),
                      ]
                    : [
                        for (final (index, track) in expanded.tracks.indexed)
                          ListTile(
                            title: Text(
                              _variantName(track, index),
                              style: AppTypography.bodyMd.copyWith(
                                color: AppColors.onDark,
                              ),
                            ),
                            trailing: _isSelected(track)
                                ? const Icon(
                                    Icons.check,
                                    color: AppColors.brandAccent,
                                  )
                                : null,
                            onTap: () =>
                                Navigator.of(context).pop(_sourceFor(track)),
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

class _SubtitleGroup {
  const _SubtitleGroup({required this.label, required this.tracks});

  final String label;
  final List<SubtitleTrack> tracks;
}
