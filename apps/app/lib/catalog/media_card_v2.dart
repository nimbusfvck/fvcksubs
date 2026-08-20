import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../theme/tokens.dart';
import '../utils/media_item_metadata.dart';
import 'generated_banner.dart';
import 'media_card.dart' show LiveBadge, UpcomingBadge;
import 'start_time_label.dart';

class MediaCardV2 extends StatelessWidget {
  const MediaCardV2({
    super.key,
    required this.item,
    required this.onTap,
    this.showSubtitle = true,
  });

  final MediaItemV2 item;
  final VoidCallback onTap;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(onTap: onTap, child: _content()),
  );

  Widget _content() {
    final value = item;
    final portrait = value.artwork?.portrait;
    if (portrait != null) return _Poster(item: value, image: portrait);
    if (value case EventItemV2(
      :final participants,
    ) when participants.length == 2) {
      return _Match(item: value, showSubtitle: showSubtitle);
    }
    return _Summary(item: value, showSubtitle: showSubtitle);
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.item, required this.image});

  final MediaItemV2 item;
  final ImageRef image;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: CachedNetworkImage(
          imageUrl: image.url,
          fit: BoxFit.cover,
          width: double.infinity,
          fadeInDuration: Duration.zero,
          placeholder: (_, _) =>
              const ColoredBox(color: AppColors.surfaceDarkElevated),
          errorWidget: (_, _, _) => const ColoredBox(
            color: AppColors.surfaceDarkElevated,
            child: Icon(Icons.play_circle_outline, color: AppColors.onDarkSoft),
          ),
        ),
      ),
      _Text(item: item),
    ],
  );
}

class _Match extends StatelessWidget {
  const _Match({required this.item, required this.showSubtitle});

  final EventItemV2 item;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: GeneratedBanner(
          participants: item.participants,
          status: switch (item.schedule.state) {
            ScheduleState.scheduled => LiveStatus.scheduled,
            ScheduleState.live => LiveStatus.live,
            ScheduleState.ended => LiveStatus.ended,
            ScheduleState.unknown => LiveStatus.unknown,
          },
          patternKey: item.subtitle,
        ),
      ),
      _Text(
        item: item,
        secondary: _eventMeta(item, showSubtitle: showSubtitle),
      ),
    ],
  );
}

class _Summary extends StatelessWidget {
  const _Summary({required this.item, required this.showSubtitle});

  final MediaItemV2 item;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) {
    final event = item is EventItemV2 ? item as EventItemV2 : null;
    final detail = showSubtitle ? mediaItemSecondaryText(item) : null;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (event != null) _ScheduleStatus(schedule: event.schedule),
          const SizedBox(height: AppSpacing.xs),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.titleSm.copyWith(color: AppColors.onDark),
          ),
          if (detail != null)
            Text.rich(
              mediaItemSecondarySpan(
                item,
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onDarkSoft,
                ),
                ratingColor: AppColors.ratingAccent,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

class _Text extends StatelessWidget {
  const _Text({required this.item, this.secondary});

  final MediaItemV2 item;
  final String? secondary;

  @override
  Widget build(BuildContext context) {
    final detail = secondary ?? mediaItemSecondaryText(item);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.titleSm.copyWith(color: AppColors.onDark),
          ),
          if (detail != null)
            secondary != null
                ? Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onDarkSoft,
                    ),
                  )
                : Text.rich(
                    mediaItemSecondarySpan(
                      item,
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onDarkSoft,
                      ),
                      ratingColor: AppColors.ratingAccent,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
        ],
      ),
    );
  }
}

class _ScheduleStatus extends StatelessWidget {
  const _ScheduleStatus({required this.schedule});

  final Schedule schedule;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (schedule.state == ScheduleState.live)
        const LiveBadge()
      else if (schedule.state == ScheduleState.scheduled)
        const UpcomingBadge(),
      if (_label != null) ...[
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            _label!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(color: AppColors.onDarkSoft),
          ),
        ),
      ],
    ],
  );

  String? get _label => schedule.label ?? startTimeLabel(schedule.startsAt);
}

String? _eventMeta(EventItemV2 item, {required bool showSubtitle}) {
  final clock = item.schedule.label ?? startTimeLabel(item.schedule.startsAt);
  final detail = showSubtitle ? mediaItemSecondaryText(item) : null;
  final values = [?detail, ?clock];
  return values.isEmpty ? null : values.join(' · ');
}
