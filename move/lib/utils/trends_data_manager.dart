import 'database_helper.dart';
import '../globals.dart';

/// Data access layer for health trend data
/// Provides clean API for trend screens to query SQLite database
class TrendsDataManager {
  final String trendType;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  TrendsDataManager(this.trendType);

  /// Get hourly trends for today
  Future<List<HourlyTrend>> getHourlyTrendForToday() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    final results = await _dbHelper.getHourlyTrends(trendType, today);
    
    return results.map((row) {
      return HourlyTrend(
        hour: DateTime.fromMillisecondsSinceEpoch((row['hour_start'] as int) * 1000),
        min: (row['min_value'] as num).toDouble(),
        max: (row['max_value'] as num).toDouble(),
        avg: (row['avg_value'] as num).toDouble(),
      );
    }).toList();
  }

  /// Get daily trends for this week
  Future<List<WeeklyTrend>> getWeeklyTrends() async {
    final now = DateTime.now();
    // Start from 6 days ago to include today as the 7th day
    final sixDaysAgo = now.subtract(Duration(days: 6));
    final startOfWeek = DateTime(sixDaysAgo.year, sixDaysAgo.month, sixDaysAgo.day);
    
    final results = await _dbHelper.getWeeklyTrends(trendType, startOfWeek);
    
    return results.map((row) {
      return WeeklyTrend(
        date: DateTime.fromMillisecondsSinceEpoch((row['day_start'] as int) * 1000),
        min: (row['min_value'] as num).toDouble(),
        max: (row['max_value'] as num).toDouble(),
        avg: (row['avg_value'] as num).toDouble(),
      );
    }).toList();
  }

  /// Get daily trends for this month
  Future<List<MonthlyTrend>> getMonthlyTrends() async {
    final now = DateTime.now();
    
    final results = await _dbHelper.getMonthlyTrends(trendType, now.year, now.month);
    
    return results.map((row) {
      return MonthlyTrend(
        date: DateTime.fromMillisecondsSinceEpoch((row['day_start'] as int) * 1000),
        min: (row['min_value'] as num).toDouble(),
        max: (row['max_value'] as num).toDouble(),
        avg: (row['avg_value'] as num).toDouble(),
      );
    }).toList();
  }

  /// Get raw data points for a specific day (returns Map for flexibility)
  Future<List<Map<String, dynamic>>> getDataForDay(DateTime day) async {
    return await _dbHelper.getTrendsForDay(trendType, day);
  }
}
