// In a new file named ble_ctrl.dart
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:intl/intl.dart';
import '../globals.dart';

BluetoothService? commandService;
BluetoothCharacteristic? commandCharacteristic;

BluetoothService? dataService;
BluetoothCharacteristic? dataCharacteristic;


class BLEController {
  Future<void> sendCurrentDateTime(BluetoothDevice deviceName,
      String selectedOption,) async {
    List<int> commandDateTimePacket = [];

    // IMPORTANT: Device interprets datetime components as UTC, so we send UTC time
    // This ensures Unix timestamps recorded by device match actual UTC time
    var dt = DateTime.now().toUtc();
    String cdate = DateFormat("yy").format(dt);
    print('Syncing device time: ${dt.toString()} UTC (local: ${DateTime.now()})');
    print('Year: $cdate, Month: ${dt.month}, Day: ${dt.day}');
    print('Hour: ${dt.hour}, Minute: ${dt.minute}, Second: ${dt.second}');

    ByteData sessionParametersLength = ByteData(8);
    commandDateTimePacket.addAll(hPi4Global.WISER_CMD_SET_DEVICE_TIME);

    sessionParametersLength.setUint8(0, dt.second);
    sessionParametersLength.setUint8(1, dt.minute);
    sessionParametersLength.setUint8(2, dt.hour);
    sessionParametersLength.setUint8(3, dt.day);
    sessionParametersLength.setUint8(4, dt.month);
    sessionParametersLength.setUint8(5, int.parse(cdate));

    Uint8List cmdByteList = sessionParametersLength.buffer.asUint8List(0, 6);

    print("Sending DateTime information: $cmdByteList");

    commandDateTimePacket.addAll(cmdByteList);

    print("Sending DateTime Command: $commandDateTimePacket");

    List<BluetoothService> services = await deviceName.discoverServices();

    BluetoothService? targetService;
    BluetoothCharacteristic? targetCharacteristic;

    // Find a service and characteristic by UUID
    for (BluetoothService service in services) {
      if (service.uuid == Guid(hPi4Global.UUID_SERVICE_CMD)) {
        targetService = service;
        for (BluetoothCharacteristic characteristic
        in service.characteristics) {
          if (characteristic.uuid == Guid(hPi4Global.UUID_CHAR_CMD)) {
            targetCharacteristic = characteristic;
            break;
          }
        }
      }
    }

    if (targetService != null && targetCharacteristic != null) {
      // Write to the characteristic
      await targetCharacteristic.write(
        commandDateTimePacket,
        withoutResponse: true,
      );
      print('Data written: $commandDateTimePacket');
    }

    if (selectedOption == "Set Time") {
      await deviceName.disconnect();
    } else {
      /// Do Nothing;
    }
  }


  Future<void> _eraseAllLogs(BluetoothDevice deviceName) async {
    //logConsole("Erase All initiated");
    //showLoadingIndicator("Erasing logs...", context);
    await Future.delayed(Duration(seconds: 2), () async {
      List<int> commandPacket = [];
      commandPacket.addAll(hPi4Global.sessionLogWipeAll);
      //await _sendCommand(commandPacket, deviceName);
    });
    //Navigator.pop(context);
  }

  Future<void> _sendCommand(List<int> commandList,
      BluetoothDevice deviceName,) async {

    List<BluetoothService> services = await deviceName.discoverServices();

    // Find a service and characteristic by UUID
    for (BluetoothService service in services) {
      if (service.uuid == Guid(hPi4Global.UUID_SERVICE_CMD)) {
        commandService = service;
        for (BluetoothCharacteristic characteristic
        in service.characteristics) {
          if (characteristic.uuid == Guid(hPi4Global.UUID_CHAR_CMD)) {
            commandCharacteristic = characteristic;
            break;
          }
        }
      }
    }

    if (commandService != null && commandCharacteristic != null) {
      // Write to the characteristic
      await commandCharacteristic?.write(commandList, withoutResponse: true);
      //logConsole('Data written: $commandList');
    }
  }

}

