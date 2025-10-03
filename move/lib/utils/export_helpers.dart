import 'dart:io';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ExportHelpers {
  /// Format file size for display
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  
  /// Generate filename with timestamp
  static String generateFilename(String prefix, String dateLabel, String extension) {
    return '${prefix}_export_${dateLabel}.$extension';
  }
  
  /// Create CSV from data
  static String createCSV(List<List<String>> data) {
    return const ListToCsvConverter().convert(data);
  }
  
  /// Save and share file
  static Future<ShareResult> saveAndShare(
    String content, 
    String filename, 
    String description,
  ) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$filename');
    await file.writeAsString(content);
    
    return await Share.shareXFiles(
      [XFile(file.path)],
      text: description,
    );
  }
  
  /// Get date range label
  static String getDateRangeLabel(DateTime? start, DateTime? end) {
    if (start == null || end == null) return 'all_time';
    
    final format = DateFormat('yyyy-MM-dd');
    return '${format.format(start)}_to_${format.format(end)}';
  }
  
  /// Get current date label
  static String getCurrentDateLabel(String range) {
    final now = DateTime.now();
    switch (range) {
      case 'today':
        return DateFormat('yyyy-MM-dd').format(now);
      case 'week':
        return 'week_${DateFormat('yyyy-MM-dd').format(now)}';
      case 'month':
        return 'month_${DateFormat('yyyy-MM').format(now)}';
      case 'all':
        return 'all_data';
      default:
        return DateFormat('yyyy-MM-dd').format(now);
    }
  }
}
