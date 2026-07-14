// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

/// Plain trend/series value types shared by the legacy trend screens and
/// `TrendsDataManager`. Split out of `globals.dart`, which mixed these data
/// models with GATT constants, TextStyles and two widgets in one 554-line file.


class HourlyTrend {
  final DateTime hour;
  final double min;
  final double max;
  final double avg;

  HourlyTrend({
    required this.hour,
    required this.min,
    required this.max,
    required this.avg,
  });
}

class WeeklyTrend {
  final DateTime date;
  final double min;
  final double max;
  final double avg;

  WeeklyTrend({
    required this.date,
    required this.min,
    required this.max,
    required this.avg,
  });
}

class MonthlyTrend {
  final DateTime date;
  final double min;
  final double max;
  final double avg;

  MonthlyTrend({
    required this.date,
    required this.min,
    required this.max,
    required this.avg,
  });
}

class ActivityDailyTrend {
  final DateTime date;
  final int steps;

  ActivityDailyTrend({required this.date, required this.steps});
}

class ActivityWeeklyTrend {
  final DateTime date;
  final int steps;

  ActivityWeeklyTrend({required this.date, required this.steps});
}

class ActivityMonthlyTrend {
  final DateTime date;
  final int steps;

  ActivityMonthlyTrend({required this.date, required this.steps});
}

class SpO2DailyTrend {
  final DateTime date;
  final double min;
  final double max;
  final double avg;

  SpO2DailyTrend({
    required this.date,
    required this.min,
    required this.max,
    required this.avg,
  });
}

class SpO2WeeklyTrend {
  final DateTime date;
  final double min;
  final double max;
  final double avg;

  SpO2WeeklyTrend({
    required this.date,
    required this.min,
    required this.max,
    required this.avg,
  });
}

/// Represents a monthly SpO2 trend with min, max, and average values.
class SpO2MonthlyTrend {
  final DateTime date;
  final double min;
  final double max;
  final double avg;

  SpO2MonthlyTrend({
    required this.date,
    required this.min,
    required this.max,
    required this.avg,
  });
}

/// Sample time series data type.
class HRSeries {
  final DateTime time;
  final int hr;

  HRSeries(this.time, this.hr);
}

/// Sample linear data type.
class ECGPoint {
  final int time;
  final double voltage;
  //final String labelValue;
  ECGPoint(this.time, this.voltage);
}
