import 'dart:io';
import 'dart:async';

import 'dart:typed_data';
import 'dart:ui';

import 'package:move/utils/snackbar.dart';
import 'package:move/widgets/scan_result_tile.dart';
import 'package:provider/provider.dart';

import 'globals.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'sizeConfig.dart';
import 'package:intl/intl.dart';

import 'package:sn_progress_dialog/sn_progress_dialog.dart';
import 'package:file_picker/file_picker.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '/src/bloc/bloc/update_bloc.dart';
import '/src/model/firmware_update_request.dart';
import '/src/providers/firmware_update_request_provider.dart';
import '/src/view/stepper_view/firmware_select.dart';
import '/src/view/stepper_view/peripheral_select.dart';
import '/src/view/stepper_view/update_view.dart';


bool connectedToDevice = false;
bool pcConnected = false;
String pcCurrentDeviceID = " ";
String pcCurrentDeviceName = " ";

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
    print(" " + logString);
  }

  Widget _buildDFUCard(BuildContext context) {
    final provider = context.watch<FirmwareUpdateRequestProvider>();
    FirmwareUpdateRequest parameters = provider.updateParameters;

    return Stepper(
      currentStep: provider.currentStep,
      onStepContinue: () {
        setState(() {
          provider.nextStep();
        });
      },
      onStepCancel: () {
        setState(() {
          provider.previousStep();
        });
      },
      controlsBuilder: _controlBuilder,
      steps: [
        Step(
          title: Text('Select Firmware',style: hPi4Global.subValueWhiteTextStyle,),
          content: Center(
              child:Column(
                children: [
                   FirmwareSelect()
                ],
              )

          ),
          isActive: provider.currentStep == 0,
        ),
        Step(
          title: Text('Select Device',style: hPi4Global.subValueWhiteTextStyle,),
          content: Center(child: PeripheralSelect()),
          isActive: provider.currentStep == 1,
        ),
        Step(
          title: Text('Update',style: hPi4Global.subValueWhiteTextStyle,),
          content: Text('Update',style: hPi4Global.subValueWhiteTextStyle),
          isActive: provider.currentStep == 2,
        ),
      ],
    );

  }

  Widget _controlBuilder(BuildContext context, ControlsDetails details) {
    final provider = context.watch<FirmwareUpdateRequestProvider>();
    FirmwareUpdateRequest parameters = provider.updateParameters;
    switch (provider.currentStep) {
      case 0:
        if (parameters.firmware == null) {
          return Container();
        }
        return Row(
          children: [
            ElevatedButton(
              onPressed: details.onStepContinue,
              child: Text('Next'),
            ),
          ],
        );
      case 1:
        if (parameters.peripheral == null) {
          return Container();
        }
        return Row(
          children: [
            TextButton(
              onPressed: details.onStepCancel,
              child: Text('Back'),
            ),
            ElevatedButton(
              onPressed: details.onStepContinue,
              child: Text('Next'),
            ),
          ],
        );
      case 2:
        return BlocProvider(
          create: (context) => UpdateBloc(firmwareUpdateRequest: parameters),
          child: UpdateStepView(),
        );
      default:
        throw Exception('Unknown step');
    }
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Scaffold(
      backgroundColor: hPi4Global.appBackgroundColor,
      appBar: AppBar(
        backgroundColor: hPi4Global.hpi4Color,
        iconTheme: IconThemeData(
          color: Colors.white, //change your color here
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
      body: SingleChildScrollView(
        child: Center(
          child:  Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                child: Text(
                  "Select device to control",
                  style: hPi4Global.cardTextStyle,
                ),
              ),
              Container(
                height: SizeConfig.blockSizeVertical * 70,
                width: SizeConfig.blockSizeHorizontal * 97,
                child: _buildDFUCard(context),
              ),
            ],
          ),
        )

      ),
    );
  }
}
