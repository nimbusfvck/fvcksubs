import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import '../addons/installer_controller.dart';
import '../app_scope.dart';
import '../detail/open_versioned_item.dart';
import '../settings/nsfw_controller.dart';
import '../theme/breakpoints.dart';
import '../theme/tokens.dart';
import '../widgets/app_page_bar.dart';
import 'artwork_cache.dart';
import 'live_timeline_cubit.dart';
import 'participant_avatar.dart';
import 'plugin_selector.dart';

class CatalogTimelinePage extends StatefulWidget {
  const CatalogTimelinePage({super.key, required this.category});

  final String category;

  @override
  State<CatalogTimelinePage> createState() => _CatalogTimelinePageState();
}

class _CatalogTimelinePageState extends State<CatalogTimelinePage> {
  CatalogTimelineCubit? _cubit;
  DateTime? _selectedDate;
  String? _bindingSignature;
  Timer? _clock;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cubit != null) return;
    final scope = AppScope.of(context);
    _cubit = CatalogTimelineCubit(
      catalogCache: scope.catalogCache,
      registry: scope.registry,
    );
    unawaited(_load(scope));
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    unawaited(_cubit?.close() ?? Future<void>.value());
    super.dispose();
  }

  List<CatalogBinding> _bindings(AppScope scope) {
    final plugins = scope.registry.pluginsFor(widget.category);
    final pluginId = scope.pluginController.resolve([
      for (final plugin in plugins) plugin.id,
    ]);
    return [
      for (final binding in scope.registry.catalogsFor(widget.category))
        if (binding.extensionId == pluginId &&
            (binding.catalog.display == CatalogDisplay.timeline ||
                binding.catalog.display == CatalogDisplay.channelSchedule))
          binding,
    ];
  }

  Future<void> _load(AppScope scope, {bool refresh = false}) async {
    final bindings = _bindings(scope);
    _bindingSignature = _signature(bindings);
    await _cubit?.load(bindings, category: widget.category, refresh: refresh);
  }

  void _selectPlugin(AppScope scope, String id) {
    scope.pluginController.select(id);
    unawaited(_load(scope));
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return BlocBuilder<InstallerController, InstallerState>(
      bloc: scope.installerController,
      builder: (context, _) => BlocBuilder<NsfwController, NsfwState>(
        bloc: scope.nsfwController,
        builder: (context, _) => ListenableBuilder(
          listenable: scope.pluginController,
          builder: (context, _) => _body(context, scope),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AppScope scope) {
    final plugins = scope.registry.pluginsFor(widget.category);
    final pluginId = scope.pluginController.resolve([
      for (final plugin in plugins) plugin.id,
    ]);
    final bindings = _bindings(scope);
    final channelSchedule = bindings.any(
      (binding) => binding.catalog.display == CatalogDisplay.channelSchedule,
    );
    final signature = _signature(bindings);
    if (signature != _bindingSignature) {
      _bindingSignature = signature;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(
            _cubit?.load(bindings, category: widget.category) ??
                Future<void>.value(),
          );
        }
      });
    }
    return BlocProvider<CatalogTimelineCubit>.value(
      value: _cubit!,
      child: BlocBuilder<CatalogTimelineCubit, CatalogTimelineState>(
        builder: (context, state) {
          final dates = _dates(state.events);
          final today = _dateOnly(DateTime.now());
          final selectedDate =
              _selectedDate != null && dates.contains(_selectedDate)
              ? _selectedDate!
              : dates.contains(today)
              ? today
              : dates.isEmpty
              ? today
              : dates.first;

          return Scaffold(
            key: const Key('catalog-timeline'),
            appBar: AppPageBar(
              title: widget.category.toLowerCase() == 'live'
                  ? 'Schedule'
                  : _categoryLabel(widget.category),
              actions: [
                if (plugins.length > 1 && pluginId != null)
                  PluginSelector(
                    plugins: plugins,
                    selectedId: pluginId,
                    onSelected: (id) => _selectPlugin(scope, id),
                  ),
              ],
            ),
            body: RefreshIndicator(
              onRefresh: () => _load(scope, refresh: true),
              child: _content(
                state,
                selectedDate,
                dates,
                channelSchedule: channelSchedule,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _content(
    CatalogTimelineState state,
    DateTime selectedDate,
    List<DateTime> dates, {
    required bool channelSchedule,
  }) {
    if (state.isLoading && state.events.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(
            height: 320,
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }
    if (state.events.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(
            height: 320,
            child: Center(
              child: Text(
                'No events available right now.',
                style: TextStyle(color: AppColors.onDarkSoft),
              ),
            ),
          ),
        ],
      );
    }

    final events = [
      for (final event in state.events)
        if (_sameDay(event.schedule.startsAt.toLocal(), selectedDate)) event,
    ];
    return CustomScrollView(
      key: const Key('catalog-timeline-scroll'),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (dates.length > 1)
          SliverPersistentHeader(
            pinned: true,
            delegate: _DatePickerHeaderDelegate(
              dates: dates,
              selected: selectedDate,
              onSelected: (date) => setState(() => _selectedDate = date),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          sliver: SliverToBoxAdapter(
            child: events.isEmpty
                ? const SizedBox(
                    height: 220,
                    child: Center(
                      child: Text(
                        'No events on this day.',
                        style: TextStyle(color: AppColors.onDarkSoft),
                      ),
                    ),
                  )
                : channelSchedule
                ? _ChannelScheduleTimeline(
                    events: events,
                    selectedDay: selectedDate,
                    now: DateTime.now(),
                  )
                : _Timeline(
                    events: events,
                    selectedDay: selectedDate,
                    now: DateTime.now(),
                  ),
          ),
        ),
      ],
    );
  }

  static List<DateTime> _dates(List<EventItemV2> events) {
    final dates = <DateTime>{
      for (final event in events) _dateOnly(event.schedule.startsAt.toLocal()),
    }.toList()..sort();
    return dates;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _signature(List<CatalogBinding> bindings) => [
    for (final binding in bindings)
      '${binding.extensionId}/${binding.extension.manifest.version}/'
          '${binding.catalog.id}',
  ].join('|');
}

class _DatePickerHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _DatePickerHeaderDelegate({
    required this.dates,
    required this.selected,
    required this.onSelected,
  });

  final List<DateTime> dates;
  final DateTime selected;
  final ValueChanged<DateTime> onSelected;

  @override
  double get minExtent => 68;

  @override
  double get maxExtent => 68;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Material(
    color: AppColors.surfaceDark,
    elevation: overlapsContent ? 2 : 0,
    child: SizedBox(
      height: maxExtent,
      child: _DatePicker(
        dates: dates,
        selected: selected,
        onSelected: onSelected,
      ),
    ),
  );

  @override
  bool shouldRebuild(covariant _DatePickerHeaderDelegate oldDelegate) =>
      dates != oldDelegate.dates ||
      selected != oldDelegate.selected ||
      onSelected != oldDelegate.onSelected;
}

class _DatePicker extends StatelessWidget {
  const _DatePicker({
    required this.dates,
    required this.selected,
    required this.onSelected,
  });

  final List<DateTime> dates;
  final DateTime selected;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.sm,
    ),
    child: Row(
      children: [
        for (final date in dates)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: TextButton(
              onPressed: () => onSelected(date),
              style: TextButton.styleFrom(
                foregroundColor: date == selected
                    ? AppColors.onDark
                    : AppColors.onDarkSoft,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xs,
                ),
                minimumSize: const Size(48, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                _label(date),
                style: AppTypography.bodyMd.copyWith(
                  color: date == selected
                      ? AppColors.onDark
                      : AppColors.onDarkSoft,
                  fontWeight: date == selected
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
            ),
          ),
      ],
    ),
  );

  static String _label(DateTime date) {
    final today = DateTime.now();
    final dateOnly = DateTime(date.year, date.month, date.day);
    final todayOnly = DateTime(today.year, today.month, today.day);
    final difference = dateOnly.difference(todayOnly).inDays;
    return switch (difference) {
      -1 => 'Yesterday',
      0 => 'Today',
      1 => 'Tomorrow',
      _ => '${_weekday(date.weekday)} ${date.day} ${_month(date.month)}',
    };
  }

  static String _weekday(int day) =>
      const ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][day];

  static String _month(int month) => const [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sept',
    'Oct',
    'Nov',
    'Dec',
  ][month];
}

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.events,
    required this.selectedDay,
    required this.now,
  });

  final List<EventItemV2> events;
  final DateTime selectedDay;
  final DateTime now;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final groups = _groupEvents(events);
      final timeline = constraints.maxWidth < AppBreakpoints.railWidth
          ? _MobileTimeline(groups: groups, selectedDay: selectedDay, now: now)
          : _WideTimeline(groups: groups, selectedDay: selectedDay, now: now);
      return timeline;
    },
  );

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _ChannelScheduleTimeline extends StatefulWidget {
  const _ChannelScheduleTimeline({
    required this.events,
    required this.selectedDay,
    required this.now,
  });

  static const double _timeGutter = 156;
  static const double _phoneTimeGutter = 120;
  static const double _minimumProgramWidth = 112;
  static const double _timeHeader = 48;
  static const double _pixelsPerHour = 224;
  static const double _rowHeight = 88;

  final List<EventItemV2> events;
  final DateTime selectedDay;
  final DateTime now;

  @override
  State<_ChannelScheduleTimeline> createState() =>
      _ChannelScheduleTimelineState();
}

class _ChannelScheduleTimelineState extends State<_ChannelScheduleTimeline> {
  final ScrollController _scrollController = ScrollController();
  bool _labelsVisible = true;

  @override
  void initState() {
    super.initState();
    _scheduleAutoScroll();
  }

  @override
  void didUpdateWidget(covariant _ChannelScheduleTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameTimelineDay(oldWidget.selectedDay, widget.selectedDay)) {
      _scheduleAutoScroll();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _channelRows(widget.events);
    final contentWidth =
        24 * _ChannelScheduleTimeline._pixelsPerHour + AppSpacing.md;
    final height =
        _ChannelScheduleTimeline._timeHeader +
        rows.length * _ChannelScheduleTimeline._rowHeight +
        AppSpacing.md;
    final showNow = _sameTimelineDay(widget.selectedDay, widget.now);
    final timeGutter = AppBreakpoints.isPhone(context)
        ? _ChannelScheduleTimeline._phoneTimeGutter
        : _ChannelScheduleTimeline._timeGutter;
    return SizedBox(
      key: const Key('catalog-channel-timeline'),
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRect(
            child: AnimatedContainer(
              key: const Key('catalog-channel-labels'),
              width: _labelsVisible ? timeGutter : 0,
              height: height,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOutCubic,
              child: SizedBox(
                width: timeGutter,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceDark,
                    border: Border(
                      right: BorderSide(color: AppColors.hairlineDark),
                    ),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(
                        height: _ChannelScheduleTimeline._timeHeader,
                      ),
                      for (final row in rows)
                        SizedBox(
                          height: _ChannelScheduleTimeline._rowHeight,
                          child: _ChannelScheduleRowLabel(row: row),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: ClipRect(
              child: NotificationListener<UserScrollNotification>(
                onNotification: _handleUserScroll,
                child: SingleChildScrollView(
                  key: const Key('catalog-channel-programs-scroll'),
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(right: AppSpacing.md),
                  child: SizedBox(
                    width: contentWidth,
                    height: height,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _ChannelScheduleGridPainter(
                              rowCount: rows.length,
                            ),
                          ),
                        ),
                        for (var index = 0; index < rows.length; index++)
                          for (final event in rows[index].events)
                            if (_channelEventRange(event, widget.selectedDay)
                                case final range?)
                              Positioned(
                                top:
                                    _ChannelScheduleTimeline._timeHeader +
                                    index *
                                        _ChannelScheduleTimeline._rowHeight +
                                    6,
                                left:
                                    range.startMinutes /
                                    60 *
                                    _ChannelScheduleTimeline._pixelsPerHour,
                                width: math.max(
                                  _ChannelScheduleTimeline._minimumProgramWidth,
                                  (range.endMinutes - range.startMinutes) /
                                      60 *
                                      _ChannelScheduleTimeline._pixelsPerHour,
                                ),
                                height:
                                    _ChannelScheduleTimeline._rowHeight - 12,
                                child: _ChannelProgramCard(
                                  event: event,
                                  now: widget.now,
                                ),
                              ),
                        if (showNow)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                key: const Key('catalog-now-line'),
                                painter: _ChannelScheduleNowPainter(
                                  nowMinutes:
                                      widget.now.hour * 60 + widget.now.minute,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _handleUserScroll(UserScrollNotification notification) {
    if (notification.metrics.axis != Axis.horizontal) return false;
    final visible = switch (notification.direction) {
      ScrollDirection.reverse => false,
      ScrollDirection.forward => true,
      ScrollDirection.idle => _labelsVisible,
    };
    if (visible != _labelsVisible && mounted) {
      setState(() => _labelsVisible = visible);
    }
    return false;
  }

  void _scheduleAutoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_sameTimelineDay(widget.selectedDay, widget.now)) {
        return;
      }
      if (!_scrollController.hasClients) return;
      final nowOffset = widget.now.hour * 60 + widget.now.minute;
      final target =
          nowOffset / 60 * _ChannelScheduleTimeline._pixelsPerHour -
          _scrollController.position.viewportDimension * 0.35;
      unawaited(
        _scrollController.animateTo(
          target.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }
}

class _ChannelScheduleRow {
  _ChannelScheduleRow(this.name, this.logoUrl);

  final String name;
  final String? logoUrl;
  final List<EventItemV2> events = [];
}

List<_ChannelScheduleRow> _channelRows(List<EventItemV2> events) {
  final rows = <String, _ChannelScheduleRow>{};
  for (final event in events) {
    final name = event.subtitle?.trim();
    final label = name == null || name.isEmpty ? 'TV Channel' : name;
    final logo = event.branding?.logo?.url.trim();
    final row = rows.putIfAbsent(label, () => _ChannelScheduleRow(label, logo));
    row.events.add(event);
  }
  final result = rows.values.toList();
  for (final row in result) {
    row.events.sort(
      (first, second) =>
          first.schedule.startsAt.compareTo(second.schedule.startsAt),
    );
    final merged = _mergeChannelEvents(row.events);
    row.events
      ..clear()
      ..addAll(merged);
  }
  return result;
}

List<EventItemV2> _mergeChannelEvents(List<EventItemV2> events) {
  final merged = <EventItemV2>[];
  for (final event in events) {
    final previous = merged.lastOrNull;
    final previousEnd = previous?.schedule.endsAt;
    final sameTitle =
        previous != null &&
        _scheduleTitleKey(previous.title) == _scheduleTitleKey(event.title);
    if (!sameTitle ||
        previousEnd == null ||
        event.schedule.startsAt.isAfter(previousEnd)) {
      merged.add(event);
      continue;
    }

    final eventEnd = event.schedule.endsAt;
    final end = eventEnd == null || eventEnd.isBefore(previousEnd)
        ? previousEnd
        : eventEnd;
    merged[merged.length - 1] = EventItemV2(
      ref: previous.ref,
      title: previous.title,
      subtitle: previous.subtitle,
      overview: previous.overview,
      originalTitle: previous.originalTitle,
      originalLanguage: previous.originalLanguage,
      genres: previous.genres,
      countries: previous.countries,
      tags: previous.tags,
      releaseYear: previous.releaseYear,
      releaseDate: previous.releaseDate,
      rating: previous.rating,
      ratingVotes: previous.ratingVotes,
      ratings: previous.ratings,
      imdbId: previous.imdbId,
      artwork: previous.artwork,
      schedule: Schedule(
        startsAt: previous.schedule.startsAt,
        state: previous.schedule.state,
        label: previous.schedule.label,
        endsAt: end,
      ),
      participants: previous.participants,
      branding: previous.branding,
    );
  }
  return merged;
}

String _scheduleTitleKey(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

class _ChannelScheduleRange {
  const _ChannelScheduleRange({
    required this.startMinutes,
    required this.endMinutes,
  });

  final double startMinutes;
  final double endMinutes;
}

_ChannelScheduleRange? _channelEventRange(
  EventItemV2 event,
  DateTime selectedDay,
) {
  final dayStart = DateTime(
    selectedDay.year,
    selectedDay.month,
    selectedDay.day,
  );
  final dayEnd = dayStart.add(const Duration(days: 1));
  final start = event.schedule.startsAt.toLocal();
  final end =
      event.schedule.endsAt?.toLocal() ?? start.add(const Duration(hours: 1));
  if (!start.isBefore(dayEnd) || !end.isAfter(dayStart)) return null;
  final clampedStart = start.isBefore(dayStart) ? dayStart : start;
  final clampedEnd = end.isAfter(dayEnd) ? dayEnd : end;
  return _ChannelScheduleRange(
    startMinutes: clampedStart.difference(dayStart).inSeconds / 60,
    endMinutes: math
        .max(
          clampedStart.difference(dayStart).inSeconds / 60 + 1,
          clampedEnd.difference(dayStart).inSeconds / 60,
        )
        .toDouble(),
  );
}

class _ChannelScheduleGridPainter extends CustomPainter {
  const _ChannelScheduleGridPainter({required this.rowCount});

  final int rowCount;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.hairlineDark
      ..strokeWidth = 1;
    final labelStyle = AppTypography.caption.copyWith(
      color: AppColors.onDarkSoft,
    );
    for (var halfHour = 0; halfHour <= 48; halfHour++) {
      final x = halfHour / 2 * _ChannelScheduleTimeline._pixelsPerHour;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      if (halfHour < 48) {
        final hour = halfHour ~/ 2;
        final minute = halfHour.isEven ? '00' : '30';
        final label = TextPainter(
          text: TextSpan(
            text: '${hour.toString().padLeft(2, '0')}:$minute',
            style: labelStyle,
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(canvas, Offset(x + 4, 8));
      }
    }
    final headerY = _ChannelScheduleTimeline._timeHeader;
    canvas.drawLine(Offset(0, headerY), Offset(size.width, headerY), gridPaint);
    for (var row = 0; row <= rowCount; row++) {
      final y = headerY + row * _ChannelScheduleTimeline._rowHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(_ChannelScheduleGridPainter oldDelegate) =>
      oldDelegate.rowCount != rowCount;
}

class _ChannelScheduleNowPainter extends CustomPainter {
  const _ChannelScheduleNowPainter({required this.nowMinutes});

  final int nowMinutes;

  @override
  void paint(Canvas canvas, Size size) {
    final x = nowMinutes / 60 * _ChannelScheduleTimeline._pixelsPerHour;
    final nowPaint = Paint()
      ..color = AppColors.liveAccent
      ..strokeWidth = 2;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), nowPaint);
    canvas.drawCircle(
      Offset(x, _ChannelScheduleTimeline._timeHeader),
      4,
      nowPaint,
    );
  }

  @override
  bool shouldRepaint(_ChannelScheduleNowPainter oldDelegate) =>
      oldDelegate.nowMinutes != nowMinutes;
}

class _ChannelScheduleRowLabel extends StatelessWidget {
  const _ChannelScheduleRowLabel({required this.row});

  final _ChannelScheduleRow row;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.xs,
      vertical: AppSpacing.xs,
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 44,
          height: 44,
          child: row.logoUrl == null
              ? const Icon(Icons.tv_outlined, color: AppColors.onDarkSoft)
              : CachedNetworkImage(
                  imageUrl: row.logoUrl!,
                  fit: BoxFit.contain,
                  fadeInDuration: Duration.zero,
                  memCacheWidth: artworkCacheDimension(context, 44),
                  errorWidget: (_, _, _) => const Icon(
                    Icons.tv_outlined,
                    color: AppColors.onDarkSoft,
                  ),
                ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          row.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTypography.caption.copyWith(color: AppColors.onDark),
        ),
      ],
    ),
  );
}

class _ChannelProgramCard extends StatelessWidget {
  const _ChannelProgramCard({required this.event, required this.now});

  final EventItemV2 event;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final start = event.schedule.startsAt.toLocal();
    final end = event.schedule.endsAt?.toLocal();
    final isLive = !now.isBefore(start) && (end == null || now.isBefore(end));
    return Material(
      color: isLive
          ? AppColors.liveAccent.withValues(alpha: 0.14)
          : AppColors.surfaceDarkElevated,
      borderRadius: AppRadius.sm,
      child: InkWell(
        borderRadius: AppRadius.sm,
        onTap: () => openVersionedItem(
          context,
          VersionedMediaItem(item: event),
          contentRating: AppScope.of(
            context,
          ).registry.contentRatingFor(event.ref),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 140;
              final timeLabel = end == null
                  ? _channelTime(start)
                  : '${_channelTime(start)} – ${_channelTime(end)}';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: compact ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        (compact ? AppTypography.bodySm : AppTypography.bodyMd)
                            .copyWith(
                              color: AppColors.onDark,
                              fontWeight: isLive ? FontWeight.w700 : null,
                            ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          timeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(
                            color: isLive
                                ? AppColors.liveAccent
                                : AppColors.onDarkSoft,
                          ),
                        ),
                      ),
                      if (isLive) ...[
                        const SizedBox(width: AppSpacing.xxs),
                        Text(
                          'LIVE',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.liveAccent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

bool _sameTimelineDay(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

String _channelTime(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

class _TimelineEventGroup {
  const _TimelineEventGroup(this.events);

  final List<EventItemV2> events;

  EventItemV2 get first => events.first;
}

Color? _parseTimelineHex(String? hex) {
  if (hex == null) return null;
  final normalized = hex.startsWith('#') ? hex.substring(1) : hex;
  if (normalized.length != 6) return null;
  final value = int.tryParse(normalized, radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}

Color _legibleTimelineBrand(Color raw) {
  final amount = (1 - raw.computeLuminance()).clamp(0.35, 0.85);
  return Color.lerp(AppColors.surfaceDark, raw, amount)!;
}

Color? _eventBrandColor(EventItemV2 event) =>
    _parseTimelineHex(event.branding?.primaryColor) ??
    _parseTimelineHex(event.branding?.secondaryColor);

Color? _groupBrandColor(_TimelineEventGroup group) {
  final primary = _eventBrandColor(group.first);
  if (primary == null) return null;
  for (final event in group.events.skip(1)) {
    if (_eventBrandColor(event) != primary) {
      return null;
    }
  }
  return primary;
}

Color _timelineCardColor(_TimelineEventGroup group) {
  final primary = _groupBrandColor(group);
  if (primary == null) return AppColors.surfaceDarkElevated;
  final brand = _legibleTimelineBrand(primary);
  return Color.lerp(AppColors.surfaceDarkElevated, brand, 0.72)!;
}

List<_TimelineEventGroup> _groupEvents(List<EventItemV2> events) {
  final grouped = <String, List<EventItemV2>>{};
  for (final event in events) {
    final start = event.schedule.startsAt.toLocal();
    final startKey = DateTime(
      start.year,
      start.month,
      start.day,
      start.hour,
      start.minute,
    ).millisecondsSinceEpoch;
    final label = _eventGroupingLabel(event);
    final groupingKey = label.isEmpty ? event.ref.id : _normalizeLabel(label);
    final key = '$startKey:$groupingKey';
    grouped.putIfAbsent(key, () => []).add(event);
  }
  return [
    for (final group in grouped.values)
      _TimelineEventGroup(List.unmodifiable(group)),
  ];
}

String _eventGroupingLabel(EventItemV2 event) {
  final subtitle = event.subtitle?.trim();
  if (subtitle != null && subtitle.isNotEmpty) return subtitle;
  if (event.tags.isNotEmpty) {
    return event.tags.join('|');
  }
  return '';
}

String _normalizeLabel(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

class _MobileTimeline extends StatefulWidget {
  const _MobileTimeline({
    required this.groups,
    required this.selectedDay,
    required this.now,
  });

  static const double _timeGutter = 60;
  static const double _pixelsPerHour = 88;
  static const double _dayHeight = 24 * _pixelsPerHour;
  static const double _cardHeight = 136;
  static const double _minimumLaneWidth = 280;

  final List<_TimelineEventGroup> groups;
  final DateTime selectedDay;
  final DateTime now;

  @override
  State<_MobileTimeline> createState() => _MobileTimelineState();
}

class _MobileTimelineState extends State<_MobileTimeline> {
  BuildContext? _nowMarkerContext;

  @override
  void initState() {
    super.initState();
    _scheduleAutoScroll();
  }

  @override
  void didUpdateWidget(covariant _MobileTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_Timeline._sameDay(oldWidget.selectedDay, widget.selectedDay)) {
      _scheduleAutoScroll();
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final placements = _placeEvents(widget.groups);
      final laneCount = placements.fold<int>(
        1,
        (count, placement) =>
            count > placement.lane + 1 ? count : placement.lane + 1,
      );
      final laneWidth = math
          .max(
            _MobileTimeline._minimumLaneWidth,
            (constraints.maxWidth - _MobileTimeline._timeGutter) / laneCount,
          )
          .toDouble();
      final canvasWidth = _MobileTimeline._timeGutter + laneCount * laneWidth;
      final lastBottom = placements.fold<double>(
        0,
        (bottom, placement) =>
            math.max(bottom, placement.top + placement.height).toDouble(),
      );
      final height = math
          .max(_MobileTimeline._dayHeight, lastBottom + AppSpacing.md)
          .toDouble();
      final showNow = _Timeline._sameDay(widget.selectedDay, widget.now);
      return SizedBox(
        key: const Key('catalog-mobile-timeline'),
        height: height,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: canvasWidth,
            child: Stack(
              children: [
                const Positioned.fill(
                  child: CustomPaint(painter: _MobileTimelineGridPainter()),
                ),
                for (final placement in placements)
                  Positioned(
                    top: placement.top + 5,
                    left:
                        _MobileTimeline._timeGutter +
                        placement.lane * laneWidth +
                        4,
                    width: math.max(1, laneWidth - 8),
                    height: placement.height - 10,
                    child: _TimelineEventCard(group: placement.group),
                  ),
                if (showNow)
                  Positioned(
                    top:
                        (widget.now.hour * 60 + widget.now.minute) /
                        60 *
                        _MobileTimeline._pixelsPerHour,
                    left: _MobileTimeline._timeGutter,
                    child: Builder(
                      builder: (context) {
                        _nowMarkerContext = context;
                        return const SizedBox(width: 1, height: 1);
                      },
                    ),
                  ),
                if (showNow)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        key: const Key('catalog-now-line'),
                        painter: _MobileNowLinePainter(
                          nowMinutes: widget.now.hour * 60 + widget.now.minute,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  void _scheduleAutoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_Timeline._sameDay(widget.selectedDay, widget.now)) {
        return;
      }
      final markerContext = _nowMarkerContext;
      if (markerContext == null || !markerContext.mounted) return;
      unawaited(
        Scrollable.ensureVisible(
          markerContext,
          alignment: 0.35,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  List<_TimelinePlacement> _placeEvents(
    List<_TimelineEventGroup> displayGroups,
  ) {
    final laneEnds = <int, double>{};
    final placements = <_TimelinePlacement>[];
    for (final group in displayGroups) {
      final range = _eventRange(group, widget.selectedDay);
      final baseTop = range.startMinutes / 60 * _MobileTimeline._pixelsPerHour;
      final height = group.events.length > 1
          ? _MobileTimeline._cardHeight
          : math
                .max(
                  _MobileTimeline._cardHeight,
                  (range.endMinutes - range.startMinutes) /
                      60 *
                      _MobileTimeline._pixelsPerHour,
                )
                .toDouble();
      var lane = 0;
      while ((laneEnds[lane] ?? 0) > baseTop) {
        lane++;
      }
      laneEnds[lane] = baseTop + height + AppSpacing.xs;
      placements.add(
        _TimelinePlacement(
          group: group,
          lane: lane,
          top: baseTop,
          height: height,
        ),
      );
    }
    return placements;
  }
}

class _WideTimeline extends StatefulWidget {
  const _WideTimeline({
    required this.groups,
    required this.selectedDay,
    required this.now,
  });

  static const double _timeGutter = 104;
  static const double _timeHeader = 42;
  static const double _pixelsPerHour = 112;
  static const double _rowHeight = 120;
  static const double _minimumEventWidth = 156;

  final List<_TimelineEventGroup> groups;
  final DateTime selectedDay;
  final DateTime now;

  @override
  State<_WideTimeline> createState() => _WideTimelineState();
}

class _WideTimelineState extends State<_WideTimeline> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scheduleAutoScroll();
  }

  @override
  void didUpdateWidget(covariant _WideTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_Timeline._sameDay(oldWidget.selectedDay, widget.selectedDay)) {
      _scheduleAutoScroll();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final placements = _placeEvents();
    final laneCount = _laneCount(placements);
    final width = _WideTimeline._timeGutter + 24 * _WideTimeline._pixelsPerHour;
    final height =
        _WideTimeline._timeHeader +
        laneCount * _WideTimeline._rowHeight +
        AppSpacing.md;
    final showNow = _Timeline._sameDay(widget.selectedDay, widget.now);
    return SizedBox(
      key: const Key('catalog-wide-timeline'),
      height: height,
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: SizedBox(
          width: width,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _WideTimelineGridPainter(laneCount: laneCount),
                ),
              ),
              for (final placement in placements)
                Positioned(
                  top:
                      _WideTimeline._timeHeader +
                      placement.lane * _WideTimeline._rowHeight +
                      6,
                  left: _WideTimeline._timeGutter + placement.left,
                  width: placement.width,
                  height: _WideTimeline._rowHeight - 12,
                  child: _TimelineEventCard(
                    group: placement.group,
                    compact: true,
                  ),
                ),
              if (showNow)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      key: const Key('catalog-now-line'),
                      painter: _WideNowLinePainter(
                        nowMinutes: widget.now.hour * 60 + widget.now.minute,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _scheduleAutoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_Timeline._sameDay(widget.selectedDay, widget.now)) {
        return;
      }
      if (!_scrollController.hasClients) return;
      final nowOffset = widget.now.hour * 60 + widget.now.minute;
      final target =
          nowOffset / 60 * _WideTimeline._pixelsPerHour +
          _WideTimeline._timeGutter -
          _scrollController.position.viewportDimension * 0.35;
      final clampedTarget = target.clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      unawaited(
        _scrollController.animateTo(
          clampedTarget,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  List<_WideTimelinePlacement> _placeEvents() {
    final laneEnds = <int, double>{};
    final placements = <_WideTimelinePlacement>[];
    for (final group in widget.groups) {
      final range = _eventRange(group, widget.selectedDay);
      final start = range.startMinutes / 60 * _WideTimeline._pixelsPerHour;
      final duration =
          (range.endMinutes - range.startMinutes) /
          60 *
          _WideTimeline._pixelsPerHour;
      final width = math
          .max(_WideTimeline._minimumEventWidth, duration)
          .toDouble();
      var lane = 0;
      while ((laneEnds[lane] ?? 0) > start) {
        lane++;
      }
      laneEnds[lane] = start + width;
      placements.add(
        _WideTimelinePlacement(
          group: group,
          lane: lane,
          left: start,
          width: width,
        ),
      );
    }
    return placements;
  }

  static int _laneCount(List<_WideTimelinePlacement> placements) =>
      placements.fold<int>(
        1,
        (count, placement) =>
            count > placement.lane + 1 ? count : placement.lane + 1,
      );
}

class _EventRange {
  const _EventRange({required this.startMinutes, required this.endMinutes});

  final double startMinutes;
  final double endMinutes;
}

_EventRange _eventRange(_TimelineEventGroup group, DateTime selectedDay) {
  final start = group.first.schedule.startsAt.toLocal();
  var end = start.add(const Duration(minutes: 90));
  for (final event in group.events) {
    final eventStart = event.schedule.startsAt.toLocal();
    final eventEnd =
        event.schedule.endsAt?.toLocal() ??
        eventStart.add(const Duration(minutes: 90));
    if (eventEnd.isAfter(end)) end = eventEnd;
  }
  final dayStart = DateTime(
    selectedDay.year,
    selectedDay.month,
    selectedDay.day,
  );
  final dayEnd = dayStart.add(const Duration(days: 1));
  final clampedStart = start.isBefore(dayStart) ? dayStart : start;
  final clampedEnd = end.isAfter(dayEnd) ? dayEnd : end;
  final startMinutes = clampedStart.difference(dayStart).inSeconds / 60;
  final endMinutes = clampedEnd.difference(dayStart).inSeconds / 60;
  return _EventRange(
    startMinutes: startMinutes.clamp(0, 1440).toDouble(),
    endMinutes: math
        .max(startMinutes + 1, endMinutes.clamp(0, 1440))
        .toDouble(),
  );
}

class _WideTimelinePlacement {
  const _WideTimelinePlacement({
    required this.group,
    required this.lane,
    required this.left,
    required this.width,
  });

  final _TimelineEventGroup group;
  final int lane;
  final double left;
  final double width;
}

class _TimelinePlacement {
  const _TimelinePlacement({
    required this.group,
    required this.lane,
    required this.top,
    required this.height,
  });

  final _TimelineEventGroup group;
  final int lane;
  final double top;
  final double height;
}

class _MobileTimelineGridPainter extends CustomPainter {
  const _MobileTimelineGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.hairlineDark
      ..strokeWidth = 1;
    final labelStyle = AppTypography.caption.copyWith(
      color: AppColors.onDarkSoft,
    );
    for (var hour = 0; hour <= 24; hour++) {
      final y = hour * _MobileTimeline._pixelsPerHour;
      canvas.drawLine(
        Offset(_MobileTimeline._timeGutter, y),
        Offset(size.width, y),
        gridPaint,
      );
      if (hour < 24) {
        final label = TextPainter(
          text: TextSpan(
            text: '${hour.toString().padLeft(2, '0')}:00',
            style: labelStyle,
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(canvas, Offset(AppSpacing.xs, y + 4));
      }
    }
  }

  @override
  bool shouldRepaint(_MobileTimelineGridPainter oldDelegate) => false;
}

class _MobileNowLinePainter extends CustomPainter {
  const _MobileNowLinePainter({required this.nowMinutes});

  final int nowMinutes;

  @override
  void paint(Canvas canvas, Size size) {
    final y = nowMinutes / 60 * _MobileTimeline._pixelsPerHour;
    final nowPaint = Paint()
      ..color = AppColors.liveAccent
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(_MobileTimeline._timeGutter, y),
      Offset(size.width, y),
      nowPaint,
    );
    canvas.drawCircle(Offset(_MobileTimeline._timeGutter, y), 4, nowPaint);
  }

  @override
  bool shouldRepaint(_MobileNowLinePainter oldDelegate) =>
      oldDelegate.nowMinutes != nowMinutes;
}

class _WideTimelineGridPainter extends CustomPainter {
  const _WideTimelineGridPainter({required this.laneCount});

  final int laneCount;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.hairlineDark
      ..strokeWidth = 1;
    final labelStyle = AppTypography.caption.copyWith(
      color: AppColors.onDarkSoft,
    );
    final headerPaint = Paint()
      ..color = AppColors.outlineDark
      ..strokeWidth = 1;

    for (var hour = 0; hour <= 24; hour++) {
      final x = _WideTimeline._timeGutter + hour * _WideTimeline._pixelsPerHour;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      if (hour < 24) {
        final label = TextPainter(
          text: TextSpan(
            text: '${hour.toString().padLeft(2, '0')}:00',
            style: labelStyle,
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(canvas, Offset(x + 4, 8));
      }
    }

    final headerY = _WideTimeline._timeHeader;
    canvas.drawLine(
      Offset(_WideTimeline._timeGutter, headerY),
      Offset(size.width, headerY),
      headerPaint,
    );
    for (var lane = 0; lane <= laneCount; lane++) {
      final y = headerY + lane * _WideTimeline._rowHeight;
      canvas.drawLine(
        Offset(_WideTimeline._timeGutter, y),
        Offset(size.width, y),
        gridPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_WideTimelineGridPainter oldDelegate) =>
      oldDelegate.laneCount != laneCount;
}

class _WideNowLinePainter extends CustomPainter {
  const _WideNowLinePainter({required this.nowMinutes});

  final int nowMinutes;

  @override
  void paint(Canvas canvas, Size size) {
    final x =
        _WideTimeline._timeGutter +
        nowMinutes / 60 * _WideTimeline._pixelsPerHour;
    final nowPaint = Paint()
      ..color = AppColors.liveAccent
      ..strokeWidth = 2;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), nowPaint);
    canvas.drawCircle(Offset(x, _WideTimeline._timeHeader), 4, nowPaint);
  }

  @override
  bool shouldRepaint(_WideNowLinePainter oldDelegate) =>
      oldDelegate.nowMinutes != nowMinutes;
}

class _TimelineTitle extends StatelessWidget {
  const _TimelineTitle({required this.title, required this.participants});

  final String title;
  final List<Participant> participants;

  @override
  Widget build(BuildContext context) {
    final showParticipants =
        participants.length == 2 && participants.any(_hasParticipantLogo);
    if (!showParticipants) {
      return Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.titleSm.copyWith(color: AppColors.onDark),
      );
    }

    final home = participants.first.shortName ?? participants.first.name;
    final away = participants.last.shortName ?? participants.last.name;
    return Row(
      children: [
        Flexible(
          child: Text(
            home,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.titleSm.copyWith(color: AppColors.onDark),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        _TimelineParticipantLogo(participant: participants.first),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          child: Text(
            'vs',
            style: AppTypography.caption.copyWith(color: AppColors.onDarkSoft),
          ),
        ),
        _TimelineParticipantLogo(participant: participants.last),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(
          child: Text(
            away,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.titleSm.copyWith(color: AppColors.onDark),
          ),
        ),
      ],
    );
  }
}

bool _hasParticipantLogo(Participant participant) =>
    participant.logo?.url.trim().isNotEmpty ?? false;

class _TimelineParticipantLogo extends StatelessWidget {
  const _TimelineParticipantLogo({required this.participant});

  final Participant participant;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '${participant.name} logo',
    child: ParticipantAvatar(imageUrl: participant.logo?.url.trim(), size: 20),
  );
}

class _TimelineLeagueLogo extends StatelessWidget {
  const _TimelineLeagueLogo({required this.imageUrl, required this.label});

  final String imageUrl;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label.isEmpty ? 'League logo' : '$label logo',
    child: SizedBox(
      width: 20,
      height: 20,
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.contain,
        fadeInDuration: Duration.zero,
        memCacheWidth: artworkCacheDimension(context, 20),
        placeholder: (_, _) => const Icon(
          Icons.emoji_events_outlined,
          size: 18,
          color: AppColors.onDarkSoft,
        ),
        errorWidget: (_, _, _) => const Icon(
          Icons.emoji_events_outlined,
          size: 18,
          color: AppColors.onDarkSoft,
        ),
      ),
    ),
  );
}

class _TimelinePickerLeading extends StatelessWidget {
  const _TimelinePickerLeading({required this.event});

  final EventItemV2 event;

  @override
  Widget build(BuildContext context) {
    final logoUrl = event.branding?.logo?.url.trim();
    if (logoUrl != null && logoUrl.isNotEmpty) {
      return _TimelineLeagueLogo(
        imageUrl: logoUrl,
        label: event.subtitle?.trim() ?? '',
      );
    }
    return Icon(
      event.schedule.state == ScheduleState.live
          ? Icons.circle
          : Icons.schedule_rounded,
      color: event.schedule.state == ScheduleState.live
          ? AppColors.liveAccent
          : AppColors.onDarkSoft,
      size: 16,
    );
  }
}

class _TimelineLiveIndicator extends StatefulWidget {
  const _TimelineLiveIndicator();

  @override
  State<_TimelineLiveIndicator> createState() => _TimelineLiveIndicatorState();
}

class _TimelineLiveIndicatorState extends State<_TimelineLiveIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);
  late final Animation<double> _pulse = Tween<double>(
    begin: 0.65,
    end: 1,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Live now',
    child: AnimatedBuilder(
      animation: _pulse,
      child: const SizedBox(
        width: 8,
        height: 8,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.liveAccent,
            shape: BoxShape.circle,
          ),
        ),
      ),
      builder: (context, child) => Opacity(
        opacity: 0.55 + _pulse.value * 0.45,
        child: Transform.scale(scale: 0.9 + _pulse.value * 0.2, child: child),
      ),
    ),
  );
}

class _TimelineEventCard extends StatelessWidget {
  const _TimelineEventCard({required this.group, this.compact = false});

  final _TimelineEventGroup group;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final event = group.first;
    final start = event.schedule.startsAt.toLocal();
    final end = event.schedule.endsAt?.toLocal();
    final isGroup = group.events.length > 1;
    final isLive = group.events.any(
      (value) => _isLiveNow(value, DateTime.now()),
    );
    final cardColor = _timelineCardColor(group);
    final time = end == null ? _time(start) : '${_time(start)} – ${_time(end)}';
    final title = isGroup ? '${group.events.length} events' : event.title;
    final description = isGroup
        ? _eventGroupingLabel(event).replaceAll('|', ' · ')
        : _eventDescription(event);
    final leagueLogoUrl = event.branding?.logo?.url.trim();
    final participants = event.participants.take(2).toList(growable: false);
    final showParticipants =
        !isGroup &&
        participants.length == 2 &&
        participants.any(_hasParticipantLogo);
    final cardPadding = compact
        ? const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          )
        : const EdgeInsets.all(AppSpacing.sm);
    final sectionGap = compact ? AppSpacing.xxs : AppSpacing.xs;

    return Material(
      color: cardColor,
      borderRadius: AppRadius.md,
      child: InkWell(
        borderRadius: AppRadius.md,
        onTap: () =>
            isGroup ? _showEventPicker(context) : _openEvent(context, event),
        child: Padding(
          padding: cardPadding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isLive) ...[
                          const _TimelineLiveIndicator(),
                          const SizedBox(width: AppSpacing.xs),
                        ],
                        Expanded(
                          child: _TimelineTitle(
                            title: title,
                            participants: showParticipants
                                ? participants
                                : const [],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: sectionGap),
                    Text(
                      time,
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onDarkSoft,
                      ),
                    ),
                    if (description.isNotEmpty ||
                        (leagueLogoUrl != null &&
                            leagueLogoUrl.isNotEmpty)) ...[
                      SizedBox(height: sectionGap),
                      Row(
                        children: [
                          if (leagueLogoUrl != null &&
                              leagueLogoUrl.isNotEmpty) ...[
                            _TimelineLeagueLogo(
                              imageUrl: leagueLogoUrl,
                              label: description,
                            ),
                            if (description.isNotEmpty)
                              const SizedBox(width: AppSpacing.xs),
                          ],
                          if (description.isNotEmpty)
                            Expanded(
                              child: Text(
                                description,
                                maxLines: compact ? 1 : 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.bodySm.copyWith(
                                  color: AppColors.onDarkSoft,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (isGroup) ...[
                const SizedBox(width: AppSpacing.xs),
                const Padding(
                  padding: EdgeInsets.only(right: AppSpacing.xs),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.onDarkSoft,
                    semanticLabel: 'Choose event',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static bool _isLiveNow(EventItemV2 event, DateTime now) {
    if (event.schedule.state != ScheduleState.live) return false;
    final start = event.schedule.startsAt.toLocal();
    final end = event.schedule.endsAt?.toLocal();
    return !now.isBefore(start) && (end == null || now.isBefore(end));
  }

  static String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  static String _eventDescription(EventItemV2 event) {
    final subtitle = event.subtitle?.trim();
    if (subtitle != null && subtitle.isNotEmpty) {
      return _sameText(subtitle, event.title) ? '' : subtitle;
    }
    final participants = event.participants
        .map((participant) => participant.shortName ?? participant.name)
        .join('  ·  ');
    return _sameText(participants, event.title) ? '' : participants;
  }

  static bool _sameText(String first, String second) =>
      first.trim().toLowerCase() == second.trim().toLowerCase();

  void _openEvent(BuildContext context, EventItemV2 event) {
    openVersionedItem(
      context,
      VersionedMediaItem(item: event),
      contentRating: AppScope.of(context).registry.contentRatingFor(event.ref),
    );
  }

  void _showEventPicker(BuildContext context) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.xs,
                  ),
                  child: Text(
                    'Choose an event',
                    style: AppTypography.titleLg.copyWith(
                      color: AppColors.onDark,
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.65,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: group.events.length,
                    itemBuilder: (context, index) {
                      final event = group.events[index];
                      return ListTile(
                        leading: _TimelinePickerLeading(event: event),
                        title: _TimelineTitle(
                          title: event.title,
                          participants: event.participants
                              .take(2)
                              .toList(growable: false),
                        ),
                        subtitle: Text(_eventDescription(event)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (context.mounted) _openEvent(context, event);
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _categoryLabel(String category) {
  if (category.toLowerCase() == 'tv') return 'Shows';
  if (category.toLowerCase() == 'movie') return 'Movies';
  if (category.toLowerCase() == 'sport') return 'Sports';
  return category.isEmpty
      ? category
      : '${category[0].toUpperCase()}${category.substring(1)}';
}
