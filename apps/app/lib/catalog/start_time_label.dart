String? startTimeLabel(DateTime? startsAt, {DateTime? now}) {
  if (startsAt == null) return null;

  final local = startsAt.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  final time =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';

  final sameDay =
      local.year == today.year &&
      local.month == today.month &&
      local.day == today.day;
  if (sameDay) return time;

  return '${local.day} ${_months[local.month - 1]} $time';
}

const List<String> _months = [
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
