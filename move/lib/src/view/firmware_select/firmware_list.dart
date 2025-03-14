import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../globals.dart';
import '../../../sizeConfig.dart';
import '/src/model/firmware_update_request.dart';
import '/src/providers/firmware_update_request_provider.dart';
import 'package:provider/provider.dart';

class FirmwareList extends StatelessWidget {

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
                    style: TextStyle(fontSize: 16, color:hPi4Global.hpi4AppBarIconsColor),
                  ),
                  SizedBox(width:30.0),
                ]
            ),

        ),
        body: _body(context),
    );
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
                        backgroundColor: hPi4Global.hpi4Color, // background color
                        foregroundColor: Colors.white, // text color
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        minimumSize: Size(SizeConfig.blockSizeHorizontal*60, 40),
                      ),
                      onPressed: () async {
                        // Navigator.pop(context, 'Firmware');
                        FilePickerResult? result = await FilePicker.platform.pickFiles(
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
                            Text('Select Firmware', style: new TextStyle(fontSize: 16, color:Colors.white)
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
