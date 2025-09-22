import 'package:flutter/material.dart';
import 'package:mcumgr_flutter/mcumgr_flutter.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class FileDownloadScreen extends StatefulWidget {
  final BluetoothDevice device;

  const FileDownloadScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<FileDownloadScreen> createState() => _FileDownloadScreenState();
}

class _FileDownloadScreenState extends State<FileDownloadScreen> {
  late FsManager fsManager;
  String? fileContents;
  bool isLoading = false;
  String? error;
  String? statusMessage;
  int? fileSize;

  @override
  void initState() {
    super.initState();
    // Use device ID string, not the BluetoothDevice object.
    fsManager = FsManager(widget.device.remoteId.toString());
  }

  String _getMcuMgrErrorMessage(String errorString) {
    if (errorString.contains('McuMgrErrorException')) {
      // Extract error code and group from the error message
      final errorMatch = RegExp(r'McuMgr Error: (\d+) \(group: (\d+)\)').firstMatch(errorString);
      if (errorMatch != null) {
        final errorCode = int.parse(errorMatch.group(1)!);
        final groupCode = int.parse(errorMatch.group(2)!);

        // Group 8 is typically the file system group
        if (groupCode == 8) {
          switch (errorCode) {
            case 1:
              return "File system error: Unknown error";
            case 2:
              return "File not found or path does not exist";
            case 3:
              return "File system is not mounted";
            case 4:
              return "File already exists";
            case 5:
              return "Invalid file name or path";
            case 6:
              return "Not enough space on device";
            case 7:
              return "Permission denied";
            case 8:
              return "File is too large";
            case 9:
              return "Invalid file operation";
            default:
              return "File system error code: $errorCode";
          }
        } else {
          return "MCU Manager error: Code $errorCode (Group $groupCode)";
        }
      }
    }
    return errorString;
  }

  Future<void> checkFileStatus(String filePath) async {
    setState(() {
      isLoading = true;
      error = null;
      statusMessage = null;
      fileSize = null;
    });

    // Validate file path
    if (filePath.trim().isEmpty) {
      setState(() {
        error = "Please enter a file path";
        isLoading = false;
      });
      return;
    }

    try {
      setState(() {
        statusMessage = "Checking file status...";
      });

      final status = await fsManager.status(filePath);

      String statusText;
      switch (status) {
        case 0:
          statusText = "File exists and is accessible";
          break;
        case -2: // ENOENT - No such file or directory
          statusText = "File does not exist";
          break;
        case -13: // EACCES - Permission denied
          statusText = "Permission denied - cannot access file";
          break;
        case -21: // EISDIR - Is a directory
          statusText = "Path points to a directory, not a file";
          break;
        case -36: // ENAMETOOLONG - File name too long
          statusText = "File path is too long";
          break;
        default:
          statusText = "Status code: $status";
      }

      setState(() {
        statusMessage = statusText;
        fileSize = status; // You might want to get actual file size separately
      });

      // If file exists (status 0), show option to download
      if (status == 0) {
        setState(() {
          statusMessage = "$statusText - Ready to download";
        });
      }
    } catch (e) {
      setState(() {
        error = _getMcuMgrErrorMessage(e.toString());
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> downloadFile(String filePath) async {
    setState(() {
      isLoading = true;
      error = null;
      fileContents = null;
    });

    // Validate file path
    if (filePath.trim().isEmpty) {
      setState(() {
        error = "Please enter a file path";
        isLoading = false;
      });
      return;
    }

    try {
      setState(() {
        statusMessage = "Starting download...";
      });

      final data = await fsManager.download(filePath);

      /*if (data == null) throw Exception('No data returned from device');

      String contents;
      if (data is String) {
        contents = data;
      } else if (data is List<int> || data is Iterable<int>) {
        contents = utf8.decode(List<int>.from(data));
      } else if (data != null) {
        // Fallback to toString() for unexpected types
        contents = data.toString();
      } else {
        throw Exception('Received void data from device');
      }

      setState(() {
        fileContents = contents;
        statusMessage = "Download completed successfully! (${contents.length} characters)";
      });*/

    } catch (e) {
      setState(() {
        error = _getMcuMgrErrorMessage(e.toString());
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textController = TextEditingController();

    return Scaffold(
      appBar: AppBar(title: Text('Download File')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: textController,
              decoration: InputDecoration(
                labelText: 'File path on device (e.g. /fs/test.txt)',
                hintText: 'Enter file path...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.folder_open),
              ),
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: isLoading
                        ? null
                        : () => checkFileStatus(textController.text),
                    child: Text('Check File Status'),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: isLoading
                        ? null
                        : () => downloadFile(textController.text),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    child: Text('Download File'),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            if (isLoading)
              CircularProgressIndicator(),
            if (statusMessage != null)
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: statusMessage!.contains('exists')
                      ? Colors.green.withOpacity(0.1)
                      : Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: statusMessage!.contains('exists')
                        ? Colors.green
                        : Colors.blue,
                  ),
                ),
                child: Text(
                  'Status: $statusMessage',
                  style: TextStyle(
                    color: statusMessage!.contains('exists')
                        ? Colors.green.shade700
                        : Colors.blue.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            if (error != null)
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red),
                ),
                child: Text(
                  'Error: $error',
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            if (fileContents != null)
              Expanded(
                child: Container(
                  margin: EdgeInsets.only(top: 16),
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'File Contents:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Text(
                            fileContents!,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}