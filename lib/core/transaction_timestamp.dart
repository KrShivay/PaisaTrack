import 'financial_calendar.dart';

typedef FormattedTransactionTimestamp = ({
  String date,
  String time,
  String utcOffset,
});

/// Formats an instant as the local date, clock, and offset used in CSV files.
FormattedTransactionTimestamp formatTransactionTimestamp(
  DateTime instant, {
  required FinancialCalendar calendar,
}) {
  final local = calendar.localDate(instant);
  final offset = calendar.timeZoneOffset;
  final totalMinutes = offset.inMinutes.abs();
  final offsetSign = offset.isNegative ? '-' : '+';
  final offsetHours = (totalMinutes ~/ 60).toString().padLeft(2, '0');
  final offsetMinutes = (totalMinutes % 60).toString().padLeft(2, '0');

  return (
    date: '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}',
    time: '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}',
    utcOffset: 'UTC$offsetSign$offsetHours:$offsetMinutes',
  );
}

/// Replaces the selected local date while keeping the selected clock fields.
DateTime replaceLocalDatePreservingTime(
  DateTime selectedDate,
  DateTime previousSelection,
) =>
    DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      previousSelection.hour,
      previousSelection.minute,
      previousSelection.second,
      previousSelection.millisecond,
      previousSelection.microsecond,
    );

/// Converts local wall-clock fields to the UTC instant stored by the app.
DateTime financialInstantFromLocalDateTime(
  DateTime localDateTime,
  FinancialCalendar calendar,
) =>
    DateTime.utc(
      localDateTime.year,
      localDateTime.month,
      localDateTime.day,
      localDateTime.hour,
      localDateTime.minute,
      localDateTime.second,
      localDateTime.millisecond,
      localDateTime.microsecond,
    ).subtract(calendar.timeZoneOffset);
