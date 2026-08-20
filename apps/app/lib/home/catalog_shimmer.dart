import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../theme/tokens.dart';
import '../widgets/shimmer_placeholder.dart';

class CatalogShimmer extends StatelessWidget {
  const CatalogShimmer({super.key, required this.display, this.sections = 2});

  final CatalogDisplay display;
  final int sections;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < sections; i++)
        _CatalogShimmerSection(display: display),
    ],
  );
}

class _CatalogShimmerSection extends StatelessWidget {
  const _CatalogShimmerSection({required this.display});

  final CatalogDisplay display;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xs,
        ),
        child: Row(
          children: [
            ShimmerPlaceholder(
              width: 116,
              height: 20,
              borderRadius: BorderRadius.all(Radius.circular(4)),
            ),
            Spacer(),
            ShimmerPlaceholder(
              width: 62,
              height: 16,
              borderRadius: BorderRadius.all(Radius.circular(4)),
            ),
          ],
        ),
      ),
      switch (display) {
        CatalogDisplay.row => const _RowShimmer(),
        CatalogDisplay.grid => const _GridShimmer(),
        CatalogDisplay.list => const _ListShimmer(),
      },
    ],
  );
}

class _RowShimmer extends StatelessWidget {
  const _RowShimmer();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 260,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      itemCount: 4,
      separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
      itemBuilder: (_, _) =>
          const SizedBox(width: 140, child: _ShimmerCard(height: 260)),
    ),
  );
}

class _GridShimmer extends StatelessWidget {
  const _GridShimmer();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = (constraints.maxWidth ~/ 300).clamp(2, 6);
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.md,
          mainAxisExtent: 172,
        ),
        itemCount: columns * 2,
        itemBuilder: (_, _) => const _ShimmerCard(height: 172),
      );
    },
  );
}

class _ListShimmer extends StatelessWidget {
  const _ListShimmer();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
    child: Column(
      children: [
        _ShimmerCard(height: 172),
        SizedBox(height: AppSpacing.md),
        _ShimmerCard(height: 172),
        SizedBox(height: AppSpacing.md),
        _ShimmerCard(height: 172),
      ],
    ),
  );
}

class _ShimmerCard extends StatelessWidget {
  const _ShimmerCard({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: const Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: ShimmerPlaceholder(height: null)),
          Padding(
            padding: EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerPlaceholder(
                  width: double.infinity,
                  height: 14,
                  borderRadius: BorderRadius.all(Radius.circular(3)),
                ),
                SizedBox(height: AppSpacing.xs),
                ShimmerPlaceholder(
                  width: 72,
                  height: 11,
                  borderRadius: BorderRadius.all(Radius.circular(3)),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
