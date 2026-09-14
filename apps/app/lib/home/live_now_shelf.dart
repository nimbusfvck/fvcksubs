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

/// Returns whether an event occupies the current local-clock window.
bool isEventLiveNow(EventItemV2 event, DateTime now) {
  final startsAt = event.schedule.startsAt.toLocal();
  if (now.isBefore(startsAt)) return false;
  final endsAt = event.schedule.endsAt?.toLocal();
  if (endsAt != null) return now.isBefore(endsAt);
  return event.schedule.state == ScheduleState.live;
}

/// App-owned Home projection of events that are live at the current time.
class LiveNowShelf extends StatefulWidget {
  const LiveNowShelf({
    super.key,
    required this.catalogCache,
    required this.registry,
    this.refreshToken = 0,
  });

  final CatalogCache catalogCache;
  final ExtensionRegistry registry;
  final int refreshToken;

  @override
  State<LiveNowShelf> createState() => _LiveNowShelfState();
}

class _LiveNowShelfState extends State<LiveNowShelf> {
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
  void didUpdateWidget(covariant LiveNowShelf oldWidget) {
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

  String? _liveCategory() {
    for (final category in widget.registry.categories) {
      if (category.toLowerCase() == 'live') return category;
    }
    return null;
  }

  List<CatalogBinding> _bindings() {
    final category = _liveCategory();
    if (category == null) return const [];
    return [
      for (final binding in widget.registry.catalogsFor(category))
        if (binding.catalog.display == CatalogDisplay.timeline) binding,
    ];
  }

  Future<void> _load({bool refresh = false}) async {
    final category = _liveCategory();
    final bindings = _bindings();
    _bindingSignature = _signature(bindings);
    await _cubit.load(bindings, category: category ?? 'live', refresh: refresh);
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
        final events = [
          for (final event in state.events)
            if (isEventLiveNow(event, DateTime.now())) event,
        ];
        if (events.isEmpty) return const SizedBox.shrink();
        return _LiveNowContent(events: events);
      },
    );
  }

  static String _signature(List<CatalogBinding> bindings) => [
    for (final binding in bindings)
      '${binding.extensionId}/${binding.extension.manifest.version}/'
          '${binding.catalog.id}',
  ].join('|');
}

class _LiveNowContent extends StatelessWidget {
  const _LiveNowContent({required this.events})
    : super(key: const Key('home-live-now-shelf'));

  final List<EventItemV2> events;

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
        child: Text(
          'Live Now',
          style: AppTypography.titleMd.copyWith(color: AppColors.onDark),
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
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDarkContainer,
                    border: Border.all(color: AppColors.outlineDark),
                    borderRadius: AppRadius.lg,
                  ),
                  child: MediaCardV2(
                    item: item,
                    heroTag: heroTag,
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
