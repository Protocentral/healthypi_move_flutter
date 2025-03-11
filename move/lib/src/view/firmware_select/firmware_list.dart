import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../globals.dart';
import '/src/model/firmware_update_request.dart';
import '/src/providers/firmware_update_request_provider.dart';
import 'package:provider/provider.dart';

class FirmwareList extends StatelessWidget {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: hPi4Global.appBackgroundColor,
        appBar: AppBar(
            backgroundColor: hPi4Global.hpi4Color,
            title: const Text('Firmware')
        ),
        body: _body(),
        floatingActionButton: FloatingActionButton(
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
          child: const Icon(Icons.add),
        ));
  }

  Widget _body() {
    return SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                child: Text(
                  "Select firmware to upload",
                  style: hPi4Global.cardWhiteTextStyle,
                ),
              ),
            ],
          ),
        )
    );

  }

}
