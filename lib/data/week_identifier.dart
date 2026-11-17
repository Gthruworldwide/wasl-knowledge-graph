DateTime isoWeekMonday(String weekIdentifier) {
  final match = RegExp(r'^(\d{4})-W(\d{2})$').firstMatch(weekIdentifier);
  if (match == null) {
    throw FormatException('Invalid ISO week identifier: $weekIdentifier');
  }
  final year = int.parse(match.group(1)!);
  final week = int.parse(match.group(2)!);
  if (year < 1 || week < 1) {
    throw FormatException('Invalid ISO week identifier: $weekIdentifier');
  }

  final januaryFourth = DateTime.utc(year, 1, 4);
  final firstMonday = januaryFourth.subtract(
    Duration(days: januaryFourth.weekday - DateTime.monday),
  );
  final monday = firstMonday.add(Duration(days: (week - 1) * 7));
  final nextYearFourth = DateTime.utc(year + 1, 1, 4);
  final nextYearMonday = nextYearFourth.subtract(
    Duration(days: nextYearFourth.weekday - DateTime.monday),
  );
  if (monday.compareTo(nextYearMonday) >= 0) {
    throw FormatException('Invalid ISO week identifier: $weekIdentifier');
  }
  return monday;
}

String previousIsoWeekIdentifier(String weekIdentifier) {
  final monday = isoWeekMonday(weekIdentifier)
      .subtract(const Duration(days: 7));
  final januaryFourth = DateTime.utc(monday.year, 1, 4);
  final firstMonday = januaryFourth.subtract(
    Duration(days: januaryFourth.weekday - DateTime.monday),
  );
  final week = ((monday.difference(firstMonday).inDays) ~/ 7) + 1;
  return '${monday.year}-W${week.toString().padLeft(2, '0')}';
}
