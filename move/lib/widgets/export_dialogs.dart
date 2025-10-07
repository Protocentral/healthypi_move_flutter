import 'package:flutter/material.dart';
import '../globals.dart';

/// Returns 'share' action for export (Save to Device option removed)
Future<String?> showExportActionDialog(BuildContext context) async {
  // Directly return 'share' without showing a dialog
  return 'share';
}

/// Shows a success message for saved file (deprecated - no longer used)
void showSaveSuccessDialog(BuildContext context, String filename, String directory) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF2D2D2D),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.check_circle, color: Colors.green, size: 24),
          ),
          const SizedBox(width: 12),
          const Text(
            'File Saved!',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your data has been saved successfully.',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[800]!, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.folder, color: hPi4Global.hpi4Color, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Location:',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  directory,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.insert_drive_file, color: hPi4Global.hpi4Color, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Filename:',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  filename,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'OK',
            style: TextStyle(
              color: hPi4Global.hpi4Color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
