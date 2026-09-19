import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import '../catalog/catalog_cache.dart';
import '../catalog/live_timeline_cubit.dart';
import '../catalog/media_card_actions.dart';
import '../catalog/media_card_v2.dart';
import '../detail/open_versioned_item.dart';
import '../theme/tokens.dart';
import '../widgets/clickable.dart';

/// Returns whether an event starts on [now]'s local calendar day.
bool isEventToday(EventItemV2 event, DateTime now) {
  final startsAt = event.schedule.startsAt.toLocal();
  final localNow = now.toLocal();
  return startsAt.year == localNow.year &&
      startsAt.month == localNow.month &&
      startsAt.day == localNow.day;
}

/// Uses an extension-provided editorial rating as the popularity signal.
bool isPopularSportEvent(EventItemV2 event) {
  return event.rating != null;
}

/// Returns at most ten rated events that start on [now]'s local day.
List<EventItemV2> popularSportEventsForToday(
  Iterable<EventItemV2> events,
  DateTime now,
) => [
  for (final event in events)
    if (isEventToday(event, now) && isPopularSportEvent(event)) event,
].take(10).toList(growable: false);

/// Resolves an event's visible status from its schedule and the local clock.
ScheduleState eventScheduleStateAt(EventItemV2 event, DateTime now) {
  final schedule = event.schedule;
  if (schedule.state == ScheduleState.ended) return ScheduleState.ended;

  final localNow = now.toLocal();
  final endsAt = schedule.endsAt?.toLocal();
  if (endsAt != null && !localNow.isBefore(endsAt)) {
    return ScheduleState.ended;
  }
  if (!localNow.isBefore(schedule.startsAt.toLocal())) {
    return ScheduleState.live;
  }
  return ScheduleState.scheduled;
}

/// App-owned Home projection of sport events scheduled for today.
class TodaysMatchesShelf extends StatefulWidget {
  const TodaysMatchesShelf({
    super.key,
    required this.catalogCache,
    required this.registry,
    required this.onSeeMore,
    this.refreshToken = 0,
  });

  final CatalogCache catalogCache;
  final ExtensionRegistry registry;
  final VoidCallback onSeeMore;
  final int refreshToken;

  @override
  State<TodaysMatchesShelf> createState() => _TodaysMatchesShelfState();
}

class _TodaysMatchesShelfState extends State<TodaysMatchesShelf> {
  late final CatalogTimelineCubit _cubit;
  Timer? _clock;
  String? _bindingSignature;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bindingSignature != null) return;
    _cubit = CatalogTimelineCubit(
      catalogCache: widget.catalogCache,
      registry: widget.registry,
    );
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void didUpdateWidget(covariant TodaysMatchesShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      unawaited(_load(refresh: true));
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    unawaited(_cubit.close());
    super.dispose();
  }

  String? _sportCategory() {
    for (final category in widget.registry.categories) {
      if (category.toLowerCase() == 'sport') return category;
    }
    return null;
  }

  List<CatalogBinding> _bindings() {
    final category = _sportCategory();
    if (category == null) return const [];
    // This shelf is a Home projection of sport events, not a timeline layout.
    // Sport catalogs may declare `row` (as the current Sports catalog does)
    // while still returning EventItemV2 records with kickoff times.
    return widget.registry.catalogsFor(category);
  }

  Future<void> _load({bool refresh = false}) async {
    final category = _sportCategory();
    final bindings = _bindings();
    _bindingSignature = _signature(bindings);
    await _cubit.load(
      bindings,
      category: category ?? 'sport',
      refresh: refresh,
    );
  }

  @override
  Widget build(BuildContext context) {
    final signature = _signature(_bindings());
    if (signature != _bindingSignature) {
      _bindingSignature = signature;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_load());
      });
    }
    return BlocBuilder<CatalogTimelineCubit, CatalogTimelineState>(
      bloc: _cubit,
      builder: (context, state) {
        final now = DateTime.now();
        final events = popularSportEventsForToday(state.events, now);
        if (events.isEmpty) return const SizedBox.shrink();
        return _TodaysMatchesContent(
          events: events,
          now: now,
          onSeeMore: widget.onSeeMore,
        );
      },
    );
  }

  static String _signature(List<CatalogBinding> bindings) => [
    for (final binding in bindings)
      '${binding.extensionId}/${binding.extension.manifest.version}/'
          '${binding.catalog.id}',
  ].join('|');
}

class _TodaysMatchesContent extends StatelessWidget {
  const _TodaysMatchesContent({
    required this.events,
    required this.now,
    required this.onSeeMore,
  }) : super(key: const Key('home-todays-matches-shelf'));

  final List<EventItemV2> events;
  final DateTime now;
  final VoidCallback onSeeMore;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xs,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Today\'s Sporting Events',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.titleMd.copyWith(color: AppColors.onDark),
              ),
            ),
            TextButton(
              key: const Key('home-todays-matches-see-more'),
              onPressed: onSeeMore,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              ),
              child: Text(
                'See more',
                style: AppTypography.titleSm.copyWith(
                  color: AppColors.brandAccent,
                ),
              ),
            ),
          ],
        ),
      ),
      SizedBox(
        height: 174 + Clickable.ringBleed * 2,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          itemCount: events.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
          itemBuilder: (context, index) {
            final item = events[index];
            final heroTag = Object();
            return Padding(
              padding: const EdgeInsets.symmetric(
                vertical: Clickable.ringBleed,
              ),
              child: SizedBox(
                width: 280,
                child: Container(
                  key: const Key('home-todays-event-card'),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDarkContainer,
                    border: Border.all(
                      color: AppColors.outlineDark,
                      width: 0.6,
                    ),
                    borderRadius: AppRadius.lg,
                  ),
                  child: MediaCardV2(
                    item: item,
                    heroTag: heroTag,
                    compactEventFooter: true,
                    scheduleStateOverride: eventScheduleStateAt(item, now),
                    onTap: () => openVersionedItem(
                      context,
                      VersionedMediaItem(item: item),
                      heroTag: heroTag,
                    ),
                    onLongPress: () => showMediaCardActions(
                      context,
                      item,
                      onViewDetails: () => openDetails(context, item),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}
