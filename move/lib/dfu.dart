import 'dart:ui';
import 'package:provider/provider.dart';

import 'globals.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'home.dart';
import 'sizeConfig.dart';
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

    return Theme(
        data: ThemeData(
            hintColor: hPi4Global.hpi4AppBarIconsColor,
            primarySwatch: Colors.orange,
            colorScheme: ColorScheme.light(
                primary: hPi4Global.hpi4Color
            )
        ),
        child: Stepper(
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
        ),
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
              /*style: ElevatedButton.styleFrom(
                backgroundColor: hPi4Global.hpi4AppBarIconsColor, // background color
                foregroundColor: hPi4Global.hpi4AppBarColor, // text color
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                minimumSize: Size(SizeConfig.blockSizeHorizontal*20, 20),
              ),*/
              onPressed: details.onStepContinue,
              child: Text('Next',style: new TextStyle(fontSize: 12, color: hPi4Global.hpi4AppBarColor)),
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
              child: Text('Back',style: new TextStyle(fontSize: 12, color: hPi4Global.hpi4AppBarIconsColor)),
            ),
            ElevatedButton(
              /*style: ElevatedButton.styleFrom(
                backgroundColor: hPi4Global.hpi4AppBarIconsColor, // background color
                foregroundColor: hPi4Global.hpi4AppBarColor, // text color
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                minimumSize: Size(SizeConfig.blockSizeHorizontal*20, 20),
              ),*/
              onPressed: details.onStepContinue,
              child: Text('Next',style: new TextStyle(fontSize: 12, color: hPi4Global.hpi4AppBarColor)),
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
                width: SizeConfig.blockSizeHorizontal * 85,
                child: Card(
                  color: Colors.grey[900],
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child:_buildDFUCard(context))),

              ),
            ],
          ),
        )

      ),
    );
  }
}
