import 'dart:ui';
import 'package:move/src/view/firmware_select/firmware_list.dart';
import 'package:provider/provider.dart';

import 'globals.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'home.dart';
import 'sizeConfig.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '/src/model/firmware_update_request.dart';
import '/src/providers/firmware_update_request_provider.dart';

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../globals.dart';
import '../../../sizeConfig.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as httpd;
import 'package:path_provider/path_provider.dart';
import 'package:version/version.dart';


class DeviceManagement extends StatefulWidget {
  DeviceManagement({Key? key}) : super(key: key);

  @override
  State createState() => new DeviceManagementState();
}

class DeviceManagementState extends State<DeviceManagement> {

  @override
  void initState(){
    super.initState();
  }

  void dispose() {
    print("AKW: DISPOSING");
    super.dispose();
  }

  void logConsole(String logString) async {
    print("debug - $logString");
    setState(() {
      debugText += logString;
      debugText += "\n";
    });
  }

  String debugText = " ";

  Widget _buildDebugConsole() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: SingleChildScrollView(
        child: SizedBox(
          height: 150, // 8 lines of text approximately
          width: SizeConfig.blockSizeHorizontal * 88,
          child: SingleChildScrollView(
            child: Text(
              debugText,
              style: TextStyle(
                fontSize: 12,
                color: hPi4Global.hpi4AppBarIconsColor,
              ),
            ),
          ),
        ),
      ),
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

    String _latestFWVersion = "0.9.18";

    List<String> tagsWithoutV = tags.map((tag) => tag.startsWith('v') ? tag.substring(1) : tag).toList();

    // Print the new list
    print(tagsWithoutV);

    for (int i = 0; i < tagsWithoutV.length; i++) {
      _latestFWVersion = _getAvailableLatestVersion(_latestFWVersion, tagsWithoutV[i]);
    }

    return _latestFWVersion;
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


  Future<void> showFirmwareSelectDialog() {
    return showDialog<void>(
      context: context,
      barrierDismissible: true, // user must tap button!
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.black,
              title: Text(
                'Select device to connect',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
              content: Container(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Expanded(
                      child: ListView(
                        shrinkWrap: true,
                        children: <Widget>[
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

                                    final fw = LocalFirmware(data: bytes, type: fwType, name: firstResult.name);

                                    logConsole(".............."+file.toString());

                                    context.read<FirmwareUpdateRequestProvider>().setFirmware(fw);
                                    Navigator.pop(context);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        Text('Select Firmware',
                                            style: new TextStyle(fontSize: 16, color: Colors
                                                .white)
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ]),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: Text(
                    'Close',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Scaffold(
      backgroundColor: hPi4Global.appBackgroundColor,
      appBar: AppBar(
        backgroundColor: hPi4Global.hpi4AppBarColor,
        leading: IconButton(
            icon: Icon(Icons.arrow_back, color: hPi4Global.hpi4AppBarIconsColor,),
            onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => HomePage()))
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.max,
          children: <Widget>[
            Image.asset('assets/healthypi_move.png',
                fit: BoxFit.fitWidth, height: 30),
          ],
        ),
      ),
      body:ListView(
        children: [
          Center(
            child: Column(
              children: <Widget>[
                Card(
                  color: Colors.black,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  //height: SizeConfig.blockSizeVertical * 20,
                                  width: SizeConfig.blockSizeHorizontal * 88,
                                  child: Card(
                                    color: Colors.grey[900],
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Column(
                                        mainAxisAlignment:
                                        MainAxisAlignment.start,
                                        children: <Widget>[
                                          Row(
                                            mainAxisAlignment:
                                            MainAxisAlignment.center,
                                            children: <Widget>[
                                              Text(
                                                'Select device to control',
                                                style:
                                                hPi4Global
                                                    .movecardTextStyle,
                                              ),
                                              //Icon(Icons.favorite_border, color: Colors.black),
                                            ],
                                          ),
                                          SizedBox(height: 10.0),
                                          ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: hPi4Global.hpi4Color, // background color
                                                foregroundColor: Colors.white, // text color
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                                minimumSize: Size(SizeConfig.blockSizeHorizontal*100, 40),
                                              ),
                                              onPressed: () {
                                                showFirmwareSelectDialog();
                                              },
                                              child: Text('Select Firmware',
                                                  style: TextStyle(fontSize: 12, color:hPi4Global.hpi4AppBarIconsColor))),
                                          SizedBox(height: 10.0),

                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  //height: SizeConfig.blockSizeVertical * 20,
                                  width: SizeConfig.blockSizeHorizontal * 88,
                                  child: Card(
                                    color: Colors.grey[900],
                                    elevation: 2,
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Column(
                                        mainAxisAlignment:
                                        MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.max,
                                        children: <Widget>[
                                          _buildDebugConsole(),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}





