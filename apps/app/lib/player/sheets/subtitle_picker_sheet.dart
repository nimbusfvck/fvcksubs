import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../../app_scope.dart';
import '../../theme/tokens.dart';
import '../data/online_subtitle_service.dart';
import '../mappers/stream_player_mapping.dart'
    show subtitleLanguageLabel, subtitlesForPicker;
import '../models/app_player_controller.dart';
import '../models/playback_media.dart';
import '../state/subtitle_preference_controller.dart';
import '../data/subtitle_translate_service.dart';

class PlayerSubtitlePickerSheet extends StatefulWidget {
  const PlayerSubtitlePickerSheet({
    super.key,
    required this.media,
    required this.tracks,
    required this.current,
    required this.filterTracks,
    this.initialExternalTracks = const [],
    this.onExternalTracksFetched,
    this.subtitleSearchService,
    this.initialOnlineResults = const [],
    this.selectedOnlineResultKey,
    this.onOnlineResultsFetched,
    this.translationSourceTracks = const [],
    this.subtitleTranslateService,
  });

  final PlaybackMedia media;
  final List<SubtitleTrack> tracks;
  final SubtitleTrack? current;
  final List<SubtitleTrack> Function(List<SubtitleTrack> tracks) filterTracks;
  final List<SubtitleTrack> initialExternalTracks;
  final void Function(List<SubtitleTrack> tracks)? onExternalTracksFetched;
  final OnlineSubtitleSearchService? subtitleSearchService;
  final List<OnlineSubtitleSearchResult> initialOnlineResults;
  final String? selectedOnlineResultKey;
  final void Function(List<OnlineSubtitleSearchResult> results)?
  onOnlineResultsFetched;
  final List<SubtitleTrack> translationSourceTracks;
  final SubtitleTranslateService? subtitleTranslateService;

  @override
  State<PlayerSubtitlePickerSheet> createState() =>
      _PlayerSubtitlePickerSheetState();
}

enum _ExternalFetchState { idle, loading, foundNone }

enum _OnlineSearchState { idle, loading, foundNone }

class _PlayerSubtitlePickerSheetState extends State<PlayerSubtitlePickerSheet> {
  _SubtitleGroup? _expanded;
  List<SubtitleTrack> _externalTracks = const [];
  _ExternalFetchState _externalState = _ExternalFetchState.idle;
  _OnlineSearchState _onlineState = _OnlineSearchState.idle;
  List<OnlineSubtitleSearchResult> _onlineResults = const [];
  String? _materializingId;
  String? _translatingSourceUrl;
  late final OnlineSubtitleSearchService _searchService;
  late final SubtitleTranslateService _translateService;
  bool _ownsSearchService = false;

  @override
  void initState() {
    super.initState();
    _externalTracks = subtitlesForPicker(widget.initialExternalTracks);
    _onlineResults = widget.initialOnlineResults;
    _searchService =
        widget.subtitleSearchService ?? OnlineSubtitleSearchService();
    _translateService =
        widget.subtitleTranslateService ?? SubtitleTranslateService.instance;
    _ownsSearchService = widget.subtitleSearchService == null;
  }

  @override
  void dispose() {
    if (_ownsSearchService) _searchService.dispose();
    super.dispose();
  }

  List<_SubtitleGroup> get _groups {
    final merged = subtitlesForPicker([
      ...widget.tracks,
      ..._externalTracks,
      if (widget.current != null &&
          !widget.tracks.any((track) => track.url == widget.current!.url) &&
          !_externalTracks.any((track) => track.url == widget.current!.url))
        widget.current!,
    ]);
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
    final current = widget.current;
    final currentIsExternal =
        current != null &&
        !widget.tracks.any((track) => track.url == current.url);
    final merged = subtitlesForPicker([
      ..._externalTracks,
      if (currentIsExternal) current,
      ...visibleTracks,
    ]);
    widget.onExternalTracksFetched?.call(merged);
    setState(() {
      _externalTracks = merged;
      _externalState = merged.isEmpty
          ? _ExternalFetchState.foundNone
          : _ExternalFetchState.idle;
    });
  }

  Future<void> _searchOnline() async {
    final preference = AppScope.of(context).subtitlePreferenceController;
    final language = preference.languageCode;
    if (language == null || language.isEmpty) return;
    setState(() {
      _onlineState = _OnlineSearchState.loading;
      _onlineResults = const [];
    });
    try {
      final item = widget.media.item;
      final identity = item is EpisodeItemV2 ? item.episode : null;
      final episode = identity?.position;
      final season = identity == null
          ? null
          : _seasonFromGroup(identity.groupId);
      final query = (item.subtitle?.trim().isNotEmpty ?? false)
          ? item.subtitle!.trim()
          : item.title.trim();
      final results = await _searchService.search(
        query: query,
        language: language,
        season: season,
        episode: episode,
        year: item.releaseYear,
      );
      if (!mounted) return;
      setState(() {
        _onlineResults = results;
        _onlineState = results.isEmpty
            ? _OnlineSearchState.foundNone
            : _OnlineSearchState.idle;
      });
      if (results.isNotEmpty) widget.onOnlineResultsFetched?.call(results);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _onlineResults = const [];
        _onlineState = _OnlineSearchState.foundNone;
      });
    }
  }

  Future<void> _selectOnline(OnlineSubtitleSearchResult result) async {
    setState(() => _materializingId = result.id);
    try {
      final path = await _searchService.materialize(result);
      if (!mounted) return;
      final track = SubtitleTrack(
        language: result.language,
        // The native video_player backend accepts a local filesystem path for
        // captions; keep the materialized path rather than a file:// URI.
        url: path,
        label: '${result.source} · ${result.name}',
      );
      Navigator.of(context).pop(
        PlayerSubtitleSelection.track(
          track,
          isExternal: true,
          onlineSearchResultKey: _onlineResultKey(result),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _materializingId = null);
    }
  }

  List<SubtitleTrack> get _translationSources {
    final target = preferenceLanguageCode;
    if (target == null || target.isEmpty) return const [];
    final targetKey = subtitleLanguageKey(target);
    final visibleTracks = subtitlesForPicker([
      ...widget.tracks,
      ..._externalTracks,
    ]);
    if (visibleTracks.any(
      (track) => subtitleLanguageKey(track.language) == targetKey,
    )) {
      return const [];
    }
    final availableSourceTracks = [
      ...widget.translationSourceTracks,
      ...widget.tracks,
      ..._externalTracks,
    ];
    final seenUrls = <String>{};
    return [
      for (final track in availableSourceTracks)
        if (track.url.isNotEmpty &&
            subtitleLanguageKey(track.language) != targetKey &&
            seenUrls.add(track.url))
          track,
    ];
  }

  Future<void> _translateSource(SubtitleTrack source) async {
    final target = preferenceLanguageCode;
    if (target == null || target.isEmpty) return;
    setState(() => _translatingSourceUrl = source.url);
    try {
      final translated = await _translateService.translateTrack(
        source,
        targetIso: target,
      );
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop(PlayerSubtitleSelection.track(translated, isExternal: true));
    } catch (_) {
      if (!mounted) return;
      setState(() => _translatingSourceUrl = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subtitle translation failed')),
      );
    }
  }

  PlayerSubtitleSelection _sourceFor(SubtitleTrack track) =>
      PlayerSubtitleSelection.track(
        track,
        isExternal: !widget.tracks.any((item) => item.url == track.url),
      );

  PlayerSubtitleSelection _offSource() => const PlayerSubtitleSelection.off();

  bool get _offSelected => widget.current == null;

  bool _isSelected(SubtitleTrack track) {
    final current = widget.current;
    return current?.url == track.url;
  }

  bool _isOnlineResultSelected(OnlineSubtitleSearchResult result) =>
      widget.selectedOnlineResultKey == _onlineResultKey(result);

  static String _onlineResultKey(OnlineSubtitleSearchResult result) =>
      '${result.provider}\u0000${result.id}';

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
                        if (_translationSources.isNotEmpty)
                          ListTile(
                            leading: const Icon(
                              Icons.translate_rounded,
                              color: AppColors.brandAccent,
                            ),
                            title: Text(
                              'Translate to $preferenceLanguageLabel',
                              style: AppTypography.bodyMd.copyWith(
                                color: AppColors.onDark,
                              ),
                            ),
                            subtitle: Text(
                              'Choose which available subtitle to translate',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.onDarkSoft,
                              ),
                            ),
                            enabled: _materializingId == null,
                            onTap: () => setState(
                              () => _expanded = _SubtitleGroup(
                                label: 'Choose subtitle to translate',
                                tracks: _translationSources,
                                isTranslation: true,
                              ),
                            ),
                          ),
                        const Divider(color: AppColors.hairlineDark, height: 1),
                        ListTile(
                          leading: _onlineState == _OnlineSearchState.loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.onDarkSoft,
                                  ),
                                )
                              : const Icon(
                                  Icons.search_rounded,
                                  color: AppColors.onDarkSoft,
                                ),
                          title: Text(
                            _onlineState == _OnlineSearchState.foundNone
                                ? 'No $preferenceLanguageLabel subtitles found'
                                : preferenceLanguageCode == null
                                ? 'Set a subtitle language to search'
                                : 'Search $preferenceLanguageLabel',
                            style: AppTypography.bodyMd.copyWith(
                              color: AppColors.onDarkSoft,
                            ),
                          ),
                          subtitle: Text(
                            'Search OpenSubtitles and SubSource using your preference',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.onDarkSoft,
                            ),
                          ),
                          enabled:
                              preferenceLanguageCode != null &&
                              _onlineState != _OnlineSearchState.loading,
                          onTap: _searchOnline,
                        ),
                        for (final result in _onlineResults)
                          ListTile(
                            leading: _materializingId == result.id
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.brandAccent,
                                    ),
                                  )
                                : const Icon(
                                    Icons.subtitles_rounded,
                                    color: AppColors.brandAccent,
                                  ),
                            title: Text(
                              result.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodyMd.copyWith(
                                color: AppColors.onDark,
                              ),
                            ),
                            subtitle: Text(
                              '${result.source}${result.hearingImpaired ? ' · HI' : ''}',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.onDarkSoft,
                              ),
                            ),
                            trailing: _isOnlineResultSelected(result)
                                ? const Icon(
                                    Icons.check,
                                    color: AppColors.brandAccent,
                                  )
                                : null,
                            enabled: _materializingId == null,
                            onTap: () => _selectOnline(result),
                          ),
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
                            leading: _translatingSourceUrl == track.url
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.brandAccent,
                                    ),
                                  )
                                : null,
                            title: Text(
                              _variantName(track, index),
                              style: AppTypography.bodyMd.copyWith(
                                color: AppColors.onDark,
                              ),
                            ),
                            subtitle: expanded.isTranslation
                                ? Text(
                                    subtitleLanguageLabel(track.language),
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.onDarkSoft,
                                    ),
                                  )
                                : null,
                            trailing: _isSelected(track)
                                ? const Icon(
                                    Icons.check,
                                    color: AppColors.brandAccent,
                                  )
                                : null,
                            enabled: _translatingSourceUrl == null,
                            onTap: () {
                              if (expanded.isTranslation) {
                                _translateSource(track);
                              } else {
                                Navigator.of(context).pop(_sourceFor(track));
                              }
                            },
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

  String? get preferenceLanguageCode =>
      AppScope.of(context).subtitlePreferenceController.languageCode;

  String get preferenceLanguageLabel => preferenceLanguageCode == null
      ? 'your preference'
      : subtitleLanguageLabel(preferenceLanguageCode!);

  static int? _seasonFromGroup(String groupId) {
    final match = RegExp(
      r'^(?:season|s)[-_ ]?(\d+)$',
      caseSensitive: false,
    ).firstMatch(groupId.trim());
    return match == null ? null : int.tryParse(match.group(1)!);
  }
}

class _SubtitleGroup {
  const _SubtitleGroup({
    required this.label,
    required this.tracks,
    this.isTranslation = false,
  });

  final String label;
  final List<SubtitleTrack> tracks;
  final bool isTranslation;
}
