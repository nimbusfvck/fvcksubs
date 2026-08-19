import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../theme/tokens.dart';
import 'start_time_label.dart';
import 'generated_banner.dart';
import 'participant_avatar.dart';

class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.item,
    required this.onTap,
    this.showSubtitle = true,
  });

  final MediaItem item;

  final VoidCallback onTap;

  final bool showSubtitle;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(onTap: onTap, child: _layoutFor(item, showSubtitle)),
  );

  static Widget _layoutFor(MediaItem item, bool showSubtitle) {
    if (item.poster != null) return _PosterLayout(item: item);
    if (item.participants.length == 2) {
      return _GeneratedBannerLayout(item: item, showSubtitle: showSubtitle);
    }
    return _EventLayout(item: item, showSubtitle: showSubtitle);
  }
}

class _PosterLayout extends StatelessWidget {
  const _PosterLayout({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Expanded(
        child: CachedNetworkImage(
          imageUrl: item.poster!.url,
          fit: BoxFit.cover,
          width: double.infinity,
          fadeInDuration: Duration.zero,
          placeholder: (context, url) =>
              const ColoredBox(color: AppColors.surfaceDarkElevated),
          errorWidget: (context, url, error) => const ColoredBox(
            color: AppColors.surfaceDarkElevated,
            child: Icon(Icons.movie_outlined, color: AppColors.onDarkSoft),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.titleSm.copyWith(color: AppColors.onDark),
            ),
            if (item.subtitle != null)
              Text(
                item.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onDarkSoft,
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class _GeneratedBannerLayout extends StatelessWidget {
  const _GeneratedBannerLayout({required this.item, this.showSubtitle = true});

  final MediaItem item;
  final bool showSubtitle;

  static const int _fixtureLines = 2;

  String get _fixture {
    final home = item.participants[0];
    final away = item.participants[1];
    if (home.shortName == null && away.shortName == null) return item.title;
    return '${home.shortName ?? home.name} vs ${away.shortName ?? away.name}';
  }

  String? get _meta {
    final parts = [
      if (item.subtitle != null && showSubtitle) item.subtitle!,
      ?_clock,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String? get _clock => item.statusLabel ?? startTimeLabel(item.startsAt);

  @override
  Widget build(BuildContext context) {
    final meta = _meta;
    final titleStyle = AppTypography.titleSm.copyWith(color: AppColors.onDark);
    final metaStyle = AppTypography.bodySm.copyWith(
      color: AppColors.onDarkSoft,
    );
    final scaler = MediaQuery.textScalerOf(context);
    double lineOf(TextStyle style) =>
        (scaler.scale(style.fontSize!) * style.height!).ceilToDouble();
    final textBlockHeight =
        lineOf(titleStyle) * _fixtureLines + lineOf(metaStyle);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: GeneratedBanner(
            participants: item.participants,
            status: item.status,
            patternKey: item.subtitle ?? item.group,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: SizedBox(
            height: textBlockHeight,
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _fixture,
                  maxLines: _fixtureLines,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
                if (meta != null)
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: metaStyle,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EventLayout extends StatelessWidget {
  const _EventLayout({required this.item, this.showSubtitle = true});

  final MediaItem item;
  final bool showSubtitle;

  String? get _clock => item.statusLabel ?? startTimeLabel(item.startsAt);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.sm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (item.status == LiveStatus.live)
              const LiveBadge()
            else if (item.status == LiveStatus.scheduled)
              const UpcomingBadge(),
            if (_clock != null) ...[
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  _clock!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.onDarkSoft,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.titleSm.copyWith(color: AppColors.onDark),
        ),
        if (item.subtitle != null && showSubtitle) ...[
          const SizedBox(height: 2),
          Text(
            item.subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySm.copyWith(color: AppColors.onDarkSoft),
          ),
        ],
      ],
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.text,
    required this.color,
    this.foregroundColor = AppColors.onDark,
  });

  final String text;
  final Color color;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
    decoration: BoxDecoration(color: color, borderRadius: AppRadius.sm),
    child: Text(
      text,
      style: AppTypography.liveBadge.copyWith(color: foregroundColor),
    ),
  );
}

class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key});

  @override
  Widget build(BuildContext context) => const _StatusPill(
    text: 'LIVE',
    color: AppColors.liveAccent,
    foregroundColor: AppColors.primary,
  );
}

class UpcomingBadge extends StatelessWidget {
  const UpcomingBadge({super.key});

  @override
  Widget build(BuildContext context) =>
      const _StatusPill(text: 'UPCOMING', color: AppColors.brandAccent);
}

class ParticipantsRow extends StatelessWidget {
  const ParticipantsRow(this.participants, {super.key, this.avatarSize = 28});

  final List<Participant> participants;

  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    final home = participants[0];
    final away = participants[1];

    return Row(
      children: [
        Expanded(
          child: _Side(participant: home, avatarSize: avatarSize),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Text(
            'vs',
            style: AppTypography.bodySm.copyWith(color: AppColors.onDarkSoft),
          ),
        ),
        Expanded(
          child: _Side(
            participant: away,
            avatarSize: avatarSize,
            trailingAvatar: true,
          ),
        ),
      ],
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({
    required this.participant,
    required this.avatarSize,
    this.trailingAvatar = false,
  });

  final Participant participant;
  final double avatarSize;

  final bool trailingAvatar;

  @override
  Widget build(BuildContext context) {
    final avatar = ParticipantAvatar(
      imageUrl: participant.logo?.url,
      size: avatarSize,
    );
    final name = Text(
      participant.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: trailingAvatar ? TextAlign.right : TextAlign.left,
      style: AppTypography.titleSm.copyWith(color: AppColors.onDark),
    );

    final children = trailingAvatar
        ? [Expanded(child: name), const SizedBox(width: AppSpacing.xs), avatar]
        : [avatar, const SizedBox(width: AppSpacing.xs), Expanded(child: name)];

    return Row(children: children);
  }
}
