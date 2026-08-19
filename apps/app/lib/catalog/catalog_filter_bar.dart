import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class CatalogFilterBar extends StatelessWidget {
  const CatalogFilterBar({
    super.key,
    required this.filterKeys,
    required this.values,
    required this.onChanged,
  });

  final List<String> filterKeys;

  final Map<String, String> values;

  final void Function(String key, String value) onChanged;

  @override
  Widget build(BuildContext context) {
    final controls = [
      for (final key in filterKeys)
        if (key == 'date')
          _DateFilterChip(value: values['date'], onChanged: onChanged),
    ];
    if (controls.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(children: controls),
    );
  }
}

class _DateFilterChip extends StatelessWidget {
  const _DateFilterChip({required this.value, required this.onChanged});

  final String? value;
  final void Function(String key, String value) onChanged;

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _fmt(DateTime d) {
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$month-$day';
  }

  static DateTime? _parse(String? raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  String _label(DateTime date, DateTime today) {
    if (date.year == today.year &&
        date.month == today.month &&
        date.day == today.day) {
      return 'Today';
    }
    return '${date.day} ${_months[date.month - 1]} ${date.year}';
  }

  Future<void> _pick(BuildContext context, DateTime initial) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 1),
      lastDate: DateTime(initial.year + 1),
    );
    if (picked != null) onChanged('date', _fmt(picked));
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final selected = _parse(value) ?? today;

    return ActionChip(
      avatar: const Icon(
        Icons.calendar_today_outlined,
        size: 16,
        color: AppColors.onDark,
      ),
      label: Text(_label(selected, today)),
      labelStyle: AppTypography.titleSm.copyWith(color: AppColors.onDark),
      backgroundColor: AppColors.surfaceDarkElevated,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.pill),
      onPressed: () => _pick(context, selected),
    );
  }
}
