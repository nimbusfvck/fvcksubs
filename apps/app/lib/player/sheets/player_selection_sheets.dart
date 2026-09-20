import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../theme/tokens.dart';
import '../models/resolved_source.dart';
import '../models/app_player_controller.dart';

const double _refreshControlSize = 40;

const playerPlaybackSpeeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

String playerPlaybackSpeedLabel(double speed) =>
    speed == speed.roundToDouble() ? '${speed.toInt()}x' : '${speed}x';

class PlayerSourcePickerSheet extends StatefulWidget {
  const PlayerSourcePickerSheet({
    super.key,
    required this.resolvedSources,
    required this.current,
    this.providerNames = const {},
    this.onRefresh,
    this.backgroundSourceLoading,
    this.resolvedSourcesListenable,
  });

  final List<ResolvedSource> resolvedSources;
  final ResolvedSource current;
  final Map<String, String> providerNames;

  /// Runs discovery again and returns the merged list, or null to hide the
  /// control. Discovery covers every provider on one shared budget, so a
  /// provider that was slow when playback started contributes nothing and
  /// gets no second chance on its own — this is how the user asks for one.
  final Future<List<ResolvedSource>> Function()? onRefresh;

  /// Tracks source discovery that started before this sheet was opened.
  ///
  /// This is separate from [onRefresh]: background discovery must not expose
  /// a second fan-out while the player is still collecting its first result.
  final ValueListenable<bool>? backgroundSourceLoading;

  /// Publishes sources that resolve while this sheet is already visible.
  final ValueListenable<List<ResolvedSource>>? resolvedSourcesListenable;

  @override
  State<PlayerSourcePickerSheet> createState() =>
      _PlayerSourcePickerSheetState();
}

class _PlayerSourcePickerSheetState extends State<PlayerSourcePickerSheet> {
  late List<ResolvedSource> _sources;
  bool _refreshing = false;
  _SourceGroup? _expanded;

  @override
  void initState() {
    super.initState();
    final listenable = widget.resolvedSourcesListenable;
    _sources = listenable?.value ?? widget.resolvedSources;
    listenable?.addListener(_handleResolvedSourcesChanged);
  }

  @override
  void dispose() {
    widget.resolvedSourcesListenable?.removeListener(
      _handleResolvedSourcesChanged,
    );
    super.dispose();
  }

  void _handleResolvedSourcesChanged() {
    final listenable = widget.resolvedSourcesListenable;
    if (!mounted || listenable == null) return;
    final expandedKey = _expanded?.key;
    setState(() {
      _sources = List<ResolvedSource>.of(listenable.value);
      _expanded = expandedKey == null ? null : _groupForKey(expandedKey);
    });
  }

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

  List<_SourceGroup> _groupedSources() {
    final providerNames = widget.providerNames;
    final groups = <String, _SourceGroup>{};
    for (final source in _sources) {
      final providerId = source.source.providerId;
      final label =
          providerNames[providerId] ??
          (source.source.provider.isNotEmpty
              ? source.source.provider
              : providerId.isNotEmpty
              ? providerId.split('.').last
              : source.source.label);
      // Sources without provider metadata cannot be safely grouped together:
      // keep each one directly selectable instead of hiding it under a
      // generic "Unknown provider" row.
      final key = providerId.isNotEmpty
          ? providerId
          : source.source.provider.isNotEmpty
          ? source.source.provider
          : source.source.id;
      groups.putIfAbsent(
        key,
        () => _SourceGroup(key: key, label: label, sources: []),
      );
      groups[key]!.sources.add(source);
    }
    return groups.values.toList();
  }

  _SourceGroup? _groupForKey(String key) {
    for (final group in _groupedSources()) {
      if (group.key == key) return group;
    }
    return null;
  }

  Widget _refreshControl(_SourceGroup? expanded) {
    if (expanded != null) {
      return const SizedBox(
        width: _refreshControlSize,
        height: _refreshControlSize,
      );
    }

    final loading = widget.backgroundSourceLoading;
    if (loading == null) {
      return _refreshControlForState(backgroundLoading: false);
    }
    return ValueListenableBuilder<bool>(
      valueListenable: loading,
      builder: (context, backgroundLoading, child) =>
          _refreshControlForState(backgroundLoading: backgroundLoading),
    );
  }

  Widget _refreshControlForState({required bool backgroundLoading}) {
    return SizedBox(
      width: _refreshControlSize,
      height: _refreshControlSize,
      child: backgroundLoading || _refreshing
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
          : widget.onRefresh == null
          ? null
          : IconButton(
              icon: const Icon(Icons.refresh),
              color: AppColors.onDark,
              iconSize: 20,
              tooltip: 'Look for more sources',
              onPressed: _refresh,
            ),
    );
  }

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
                  width: _refreshControlSize,
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
                    expanded?.label ?? 'Video Sources',
                    textAlign: TextAlign.center,
                    style: AppTypography.titleMd.copyWith(
                      color: AppColors.onDark,
                    ),
                  ),
                ),
                _refreshControl(expanded),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: expanded == null
                    ? [
                        for (final group in _groupedSources())
                          ListTile(
                            title: Text(
                              group.sources.length > 1
                                  ? '${group.label} (${group.sources.length})'
                                  : group.label,
                              style: AppTypography.bodyMd.copyWith(
                                color: AppColors.onDark,
                              ),
                            ),
                            trailing:
                                group.sources.any(
                                  (item) =>
                                      item.source.id ==
                                      widget.current.source.id,
                                )
                                ? const Icon(
                                    Icons.check,
                                    color: AppColors.brandAccent,
                                  )
                                : group.sources.length > 1
                                ? const Icon(
                                    Icons.chevron_right_rounded,
                                    color: AppColors.onDarkSoft,
                                  )
                                : null,
                            onTap: () {
                              if (group.sources.length == 1) {
                                Navigator.of(context).pop(group.sources.first);
                              } else {
                                setState(() => _expanded = group);
                              }
                            },
                          ),
                      ]
                    : [
                        for (final item in expanded.sources)
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
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

class _SourceGroup {
  const _SourceGroup({
    required this.key,
    required this.label,
    required this.sources,
  });

  final String key;
  final String label;
  final List<ResolvedSource> sources;
}

class PlayerQualityPickerSheet extends StatefulWidget {
  const PlayerQualityPickerSheet({
    super.key,
    required this.tracks,
    required this.current,
    this.playing,
    this.onSelect,
  });

  final List<AppQualityTrack> tracks;

  /// The rendition the viewer pinned, or `null` while the choice is Auto.
  final AppQualityTrack? current;

  /// The rendition actually playing, retained for callers that want to expose
  /// that detail separately from the Auto choice.
  final AppQualityTrack? playing;

  /// Applies a choice without closing the sheet until the native player
  /// confirms the requested rendition is active.
  final Future<bool> Function(AppQualityTrack track)? onSelect;

  @override
  State<PlayerQualityPickerSheet> createState() =>
      _PlayerQualityPickerSheetState();
}

class _PlayerQualityPickerSheetState extends State<PlayerQualityPickerSheet> {
  String? _pendingId;
  String? _error;

  bool get _autoSelected => widget.current == null;

  String get _autoLabel => 'Auto';

  Future<void> _select(AppQualityTrack track) async {
    if (_pendingId != null) return;
    final apply = widget.onSelect;
    if (apply == null) {
      Navigator.of(context).pop(track);
      return;
    }
    setState(() {
      _pendingId = track.id;
      _error = null;
    });
    final applied = await apply(track);
    if (!mounted) return;
    if (applied) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _pendingId = null;
      _error = 'Variant belum aktif. Video tetap memakai kualitas sebelumnya.';
    });
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
              'Quality',
              style: AppTypography.titleMd.copyWith(color: AppColors.onDark),
            ),
            const SizedBox(height: AppSpacing.xs),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySm.copyWith(color: AppColors.error),
                ),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    title: Text(
                      _autoLabel,
                      style: AppTypography.bodyMd.copyWith(
                        color: AppColors.onDark,
                      ),
                    ),
                    trailing: _pendingId == 'auto'
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.brandAccent,
                            ),
                          )
                        : _autoSelected
                        ? const Icon(Icons.check, color: AppColors.brandAccent)
                        : null,
                    onTap: () =>
                        _select(const AppQualityTrack(id: 'auto', height: 0)),
                  ),
                  for (final track in widget.tracks)
                    ListTile(
                      title: Text(
                        qualityRungLabel(
                              width: track.width,
                              height: track.height,
                            ) ??
                            '${track.height}p',
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.onDark,
                        ),
                      ),
                      trailing: _pendingId == track.id
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.brandAccent,
                              ),
                            )
                          : !_autoSelected && widget.current?.id == track.id
                          ? const Icon(
                              Icons.check,
                              color: AppColors.brandAccent,
                            )
                          : null,
                      onTap: () => _select(track),
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
    final labels = audioTrackPickerLabels(tracks);
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
                        labels[index],
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

class PlayerPlaybackSettingsDialog extends StatelessWidget {
  const PlayerPlaybackSettingsDialog({super.key, required this.currentSpeed});

  final double currentSpeed;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.5;
    return AlertDialog(
      backgroundColor: AppColors.surfaceDark,
      title: Text(
        'Playback speed',
        style: AppTypography.titleMd.copyWith(color: AppColors.onDark),
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final speed in playerPlaybackSpeeds)
                ListTile(
                  title: Text(
                    playerPlaybackSpeedLabel(speed),
                    style: AppTypography.bodyMd.copyWith(
                      color: AppColors.onDark,
                    ),
                  ),
                  trailing: speed == currentSpeed
                      ? const Icon(Icons.check, color: AppColors.brandAccent)
                      : null,
                  onTap: () => Navigator.of(context).pop(speed),
                ),
            ],
          ),
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
