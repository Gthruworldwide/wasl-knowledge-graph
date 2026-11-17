import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_app/data/week_identifier.dart';

void main() {
  test('labels week-year by the Thursday it contains', () {
    expect(currentIsoWeekIdentifier(DateTime.utc(2026, 1, 1)), '2026-W01');
    expect(currentIsoWeekIdentifier(DateTime.utc(2025, 12, 28)), '2025-W52');
    expect(currentIsoWeekIdentifier(DateTime.utc(2025, 12, 29)), '2026-W01');
    expect(currentIsoWeekIdentifier(DateTime.utc(2027, 1, 1)), '2026-W53');
    expect(currentIsoWeekIdentifier(DateTime.utc(2026, 11, 17)), '2026-W47');
  });

  test('previous week crosses the year boundary', () {
    expect(previousIsoWeekIdentifier('2026-W01'), '2025-W52');
    expect(previousIsoWeekIdentifier('2026-W47'), '2026-W46');
  });

  test('round-trips week identifiers through their Monday', () {
    for (final date in [
      DateTime.utc(2024, 12, 30),
      DateTime.utc(2025, 1, 1),
      DateTime.utc(2026, 1, 1),
      DateTime.utc(2026, 11, 17),
      DateTime.utc(2027, 1, 1),
    ]) {
      final identifier = currentIsoWeekIdentifier(date);
      final monday = isoWeekMonday(identifier);
      expect(currentIsoWeekIdentifier(monday), identifier);
      expect(monday.weekday, DateTime.monday);
    }
  });
}
