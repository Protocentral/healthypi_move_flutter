import 'package:flutter/material.dart';
import 'package:mcumgr_flutter/mcumgr_flutter.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class FileDownloadScreen extends StatefulWidget {
  final BluetoothDevice device;

  const FileDownloadScreen({Key? key, required this.device}) : super(key: key);

  @override
  State createState() => _FileDownloadScreenState();
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
    final deviceId = widget.device.remoteId.toString();
    fsManager = FsManager(deviceId);
    print('=== FileDownloadScreen initialized with device: $deviceId ===');
  }

  String _getMcuMgrErrorMessage(String errorString) {
    print('--- Parsing McuMgr Error ---');
    print('Raw error string: $errorString');
    
    if (errorString.contains('McuMgrErrorException')) {
      final errorMatch = RegExp(r'McuMgr Error: (\d+) \(group: (\d+)\)').firstMatch(errorString);
      if (errorMatch != null) {
        final errorCode = int.parse(errorMatch.group(1)!);
        final groupCode = int.parse(errorMatch.group(2)!);
        
        print('Error Code: $errorCode, Group Code: $groupCode');

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

  Future checkFileStatus(String filePath) async {
    print('\n========== CHECK FILE STATUS ==========');
    print('File path: "$filePath"');
    
    setState(() {
      isLoading = true;
      error = null;
      statusMessage = null;
      fileSize = null;
    });

    if (filePath.trim().isEmpty) {
      print('ERROR: Empty file path provided');
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
      
      print('Calling fsManager.status()...');
      final status = await fsManager.status(filePath);
      print('Status response: $status');

      String statusText;
      switch (status) {
        case 0:
          statusText = "File exists and is accessible";
          break;
        case -2:
          statusText = "File does not exist";
          break;
        case -13:
          statusText = "Permission denied - cannot access file";
          break;
        case -21:
          statusText = "Path points to a directory, not a file";
          break;
        case -36:
          statusText = "File path is too long";
          break;
        default:
          statusText = "Status code: $status";
      }

      print('Status result: $statusText');
      
      setState(() {
        statusMessage = statusText;
        fileSize = status;
      });

      if (status == 0) {
        setState(() {
          statusMessage = "$statusText - Ready to download";
        });
        print('✓ File is ready for download');
      }
    } catch (e, stackTrace) {
      print('❌ EXCEPTION in checkFileStatus:');
      print('Exception type: ${e.runtimeType}');
      print('Exception message: $e');
      print('Stack trace:\n$stackTrace');
      
      final errorMsg = _getMcuMgrErrorMessage(e.toString());
      print('Parsed error message: $errorMsg');
      
      setState(() {
        error = errorMsg;
      });
    } finally {
      setState(() {
        isLoading = false;
      });
      print('========== CHECK FILE STATUS COMPLETE ==========\n');
    }
  }

  Future downloadFile(String filePath) async {
    print('\n========== DOWNLOAD FILE ==========');
    print('File path: "$filePath"');
    
    setState(() {
      isLoading = true;
      error = null;
      fileContents = null;
    });

    if (filePath.trim().isEmpty) {
      print('ERROR: Empty file path provided');
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
      
      print('Calling fsManager.download()...');
      final data = await fsManager.download(filePath);
      print('Download response received');
    //  print('Data type: ${data.runtimeType}');
      //print('Data: $data');

      // Add your data processing logic here when uncommented
      
      print('✓ Download completed successfully');
      
    } catch (e, stackTrace) {
      print('EXCEPTION in downloadFile:');
      print('Exception type: ${e.runtimeType}');
      print('Exception message: $e');
      print('Stack trace:\n$stackTrace');
      
      final errorMsg = _getMcuMgrErrorMessage(e.toString());
      print('Parsed error message: $errorMsg');
      
      setState(() {
        error = errorMsg;
      });
    } finally {
      setState(() {
        isLoading = false;
      });
      print('========== DOWNLOAD FILE COMPLETE ==========\n');
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
            if (isLoading) CircularProgressIndicator(),
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