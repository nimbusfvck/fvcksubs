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

/// Formats a hero event as its date and kickoff time, without its end time.
/// Events today only need the clock because the hero already implies the date.
String? eventStartLabel(DateTime? startsAt, {DateTime? now}) {
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

  return '${local.day} ${_months[local.month - 1]} - $time';
}

/// Formats a compact event start for cards, without the end time.
String? eventCardStartLabel(DateTime? startsAt, {DateTime? now}) {
  if (startsAt == null) return null;

  final local = startsAt.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  final time =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  final todayDate = DateTime(today.year, today.month, today.day);
  final eventDate = DateTime(local.year, local.month, local.day);
  final tomorrowDate = DateTime(today.year, today.month, today.day + 1);

  if (eventDate == todayDate) return 'Today $time';
  if (eventDate == tomorrowDate) return 'Tomorrow $time';
  return '${local.day} ${_months[local.month - 1]} $time';
}

String? eventTimeRangeLabel(
  DateTime? startsAt,
  DateTime? endsAt, {
  DateTime? now,
}) {
  final start = startTimeLabel(startsAt, now: now);
  if (start == null || endsAt == null) return start;

  final localStart = startsAt!.toLocal();
  final localEnd = endsAt.toLocal();
  final endTime =
      '${localEnd.hour.toString().padLeft(2, '0')}:'
      '${localEnd.minute.toString().padLeft(2, '0')}';
  final sameDay =
      localStart.year == localEnd.year &&
      localStart.month == localEnd.month &&
      localStart.day == localEnd.day;
  return sameDay
      ? '$start–$endTime'
      : '$start–${startTimeLabel(endsAt, now: now)}';
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
