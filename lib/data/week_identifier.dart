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

String currentIsoWeekIdentifier([DateTime? date]) {
  final now = (date ?? DateTime.now()).toUtc();
  final day = DateTime.utc(now.year, now.month, now.day);
  final monday = day.subtract(Duration(days: day.weekday - DateTime.monday));
  return _weekIdentifierFor(monday);
}

String previousIsoWeekIdentifier(String weekIdentifier) {
  final monday = isoWeekMonday(weekIdentifier)
      .subtract(const Duration(days: 7));
  return _weekIdentifierFor(monday);
}

/// ISO-8601 week-year labels belong to the year containing the week's
/// Thursday, so Dec 29 2025 - Jan 4 2026 is `2026-W01`, not `2025-W53`.
String _weekIdentifierFor(DateTime monday) {
  final thursday = monday.add(const Duration(days: 3));
  final year = thursday.year;
  final januaryFourth = DateTime.utc(year, 1, 4);
  final firstThursday = januaryFourth.add(
    Duration(days: DateTime.thursday - januaryFourth.weekday),
  );
  final week = (thursday.difference(firstThursday).inDays ~/ 7) + 1;
  return '$year-W${week.toString().padLeft(2, '0')}';
}
