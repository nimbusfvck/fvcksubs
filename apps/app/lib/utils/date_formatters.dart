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

String formatReleaseDate(DateTime date) =>
    '${_months[date.month - 1]} ${date.day}, ${date.year}';

/// Compact form for tight spaces, such as a badge overlaid on a poster.
String formatShortReleaseDate(DateTime date) =>
    '${_months[date.month - 1]} ${date.day}';
