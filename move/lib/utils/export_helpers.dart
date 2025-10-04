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
  
  /// Save file to device Downloads/Documents folder
  static Future<Map<String, dynamic>> saveToDevice(
    String content,
    String filename,
  ) async {
    try {
      Directory directory;
      String displayLocation;
      
      if (Platform.isAndroid) {
        // For Android 10 (API 29) and above, use scoped storage
        // Get the app's external storage directory which is accessible
        final List<Directory>? externalDirs = await getExternalStorageDirectories();
        if (externalDirs != null && externalDirs.isNotEmpty) {
          // Use the primary external storage
          directory = externalDirs.first;
          
          // Create a Downloads subfolder in the app's storage
          final downloadsDir = Directory('${directory.path}/Downloads');
          if (!await downloadsDir.exists()) {
            await downloadsDir.create(recursive: true);
          }
          directory = downloadsDir;
          displayLocation = 'Internal Storage/Android/data/com.protocentral.move/files/Downloads';
        } else {
          // Fallback to app's document directory
          directory = await getApplicationDocumentsDirectory();
          displayLocation = 'App Documents';
        }
      } else if (Platform.isIOS) {
        // On iOS, use Documents directory (accessible via Files app)
        directory = await getApplicationDocumentsDirectory();
        displayLocation = 'Files App → HealthyPi Move';
      } else {
        throw Exception('Unsupported platform');
      }
      
      final file = File('${directory.path}/$filename');
      await file.writeAsString(content);
      
      return {
        'success': true,
        'path': file.path,
        'directory': displayLocation,
        'filename': filename,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
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
