import 'package:flutter/material.dart';
import '../../../globals.dart';
import '../../../sizeConfig.dart';
import '/src/model/firmware_update_request.dart';
import '/src/providers/firmware_update_request_provider.dart';
import 'package:provider/provider.dart';

import '../firmware_select/firmware_list.dart';

class FirmwareSelect extends StatelessWidget {
  const FirmwareSelect({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    FirmwareUpdateRequest updateParameters =
        context.watch<FirmwareUpdateRequestProvider>().updateParameters;

    return Column(
      children: [
        if (updateParameters.firmware != null)
          Text(updateParameters.firmware!.name, style: hPi4Global.subValueWhiteTextStyle),
        ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: hPi4Global.hpi4Color, // background color
              foregroundColor: Colors.white, // text color
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              minimumSize: Size(SizeConfig.blockSizeHorizontal*100, 30),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => FirmwareList()),
              );
            },
            child: Text('Select Firmware',style: TextStyle(fontSize: 12, color:hPi4Global.hpi4AppBarIconsColor))),
      ],
    );
  }
}
