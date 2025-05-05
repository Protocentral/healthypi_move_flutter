import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../globals.dart';
import '../../../sizeConfig.dart';
import '../../model/firmware_update_request.dart';
import '../../providers/firmware_update_request_provider.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as httpd;
import 'package:path_provider/path_provider.dart';
import 'package:version/version.dart';


class FirmwareList extends StatefulWidget {
  const FirmwareList({super.key});

  @override
  _FirmwareListState createState() => _FirmwareListState();
}

class _FirmwareListState extends State<FirmwareList> {

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: hPi4Global.appBackgroundColor,
      appBar: AppBar(
        backgroundColor: hPi4Global.hpi4AppBarColor,
        iconTheme: IconThemeData(
          color: hPi4Global.hpi4AppBarIconsColor, //change your color here
        ),
        title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            //mainAxisSize: MainAxisSize.max,
            children: [
              const Text(
                'Firmware',
                style: TextStyle(
                    fontSize: 16, color: hPi4Global.hpi4AppBarIconsColor),
              ),
              SizedBox(width: 30.0),
            ]
        ),
      ),
      body: _body(context),

    );
  }

  void showLoadingIndicator(String text, BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8.0)),
            ),
            backgroundColor: Colors.black87,
            content: LoadingIndicator(text: text),
          ),
        );
      },
    );
  }

  Future<List<String>> fetchTags() async {
    final url = Uri.parse('https://api.github.com/repos/Protocentral/healthypi-move-fw/tags');
    final response = await httpd.get(url);

    if (response.statusCode == 200) {
      // Parse the JSON response
      List<dynamic> data = json.decode(response.body);
      // Extract the tag names from the response
      List<String> tags = data.map((tag) => tag['name'] as String).toList();
      //print("............."+ tags.toString());
      return tags;
    } else {
      throw Exception('Failed to load tags');
    }
  }

  String latestReleasePath = "";

  Future<String> _getLatestVersion() async {

    List<String> tags = await fetchTags();
    print(tags);

    String latestFWVersion = "0.9.18";

    List<String> tagsWithoutV = tags.map((tag) => tag.startsWith('v') ? tag.substring(1) : tag).toList();

    // Print the new list
    print(tagsWithoutV);

    for (int i = 0; i < tagsWithoutV.length; i++) {
      latestFWVersion = _getAvailableLatestVersion(latestFWVersion, tagsWithoutV[i]);
    }

    return latestFWVersion;
  }

  String _getAvailableLatestVersion(String versionCurrent, String versionAvail) {
    Version availVersion = Version.parse(versionAvail);
    Version currentVersion = Version.parse(versionCurrent);

    if (availVersion > currentVersion) {
      //print("...........availble"+versionAvail);
      return versionAvail;
    } else {
      //print("...........current"+versionCurrent);
      return versionCurrent;
    }
  }


  String _status = 'Click the button to download the ZIP file';

  Future<void> downloadFile() async {
    showLoadingIndicator("Downloading dfu file...", context);
    String fwVesion = await _getLatestVersion();
    Directory  dir = Directory("");
    if (Platform.isAndroid) {
      // Redirects it to download folder in android
      dir = Directory("/storage/emulated/0/Download/");
    } else {
      dir = await getApplicationDocumentsDirectory();
    }

    final url = 'https://github.com/Protocentral/healthypi-move-fw/releases/latest/download/healthypi_move_update_v$fwVesion.zip'; // Replace with your URL
    print(url);
    final response = await httpd.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final filePath = '${dir.path}/$fwVesion.zip';
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);
      setState(() {
        _status = 'File downloaded to: $filePath';
      });
    } else {
      setState(() {
        _status = 'Failed to download file';
      });
    }
    Navigator.pop(context);
    print(_status);
  }


  Widget _body(BuildContext context) {
    return SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: hPi4Global.hpi4Color,
                        // background color
                        foregroundColor: Colors.white,
                        // text color
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        minimumSize: Size(
                            SizeConfig.blockSizeHorizontal * 60, 40),
                      ),
                      onPressed: () async {
                        await downloadFile();

                        FilePickerResult? result = await FilePicker.platform
                            .pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['zip', 'bin'],
                        );
                        if (result == null) {
                          return;
                        }

                        final ext = result.files.first.extension;
                        final fwType = ext == 'zip'
                            ? FirmwareType.multiImage
                            : FirmwareType.singleImage;

                        final firstResult = result.files.first;
                        final file = File(firstResult.path!);
                        final bytes = await file.readAsBytes();

                        final fw = LocalFirmware(
                            data: bytes, type: fwType, name: firstResult.name);

                        context.read<FirmwareUpdateRequestProvider>().setFirmware(fw);
                        Navigator.pop(context);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text('Select Firmware',
                                style: TextStyle(fontSize: 16, color: Colors
                                    .white)
                            ),
                          ],
                        ),
                      ),
                    ),
                  ]),
            ],
          ),
        )
    );
  }

}


