import 'package:flutter/material.dart';
import '../../../globals.dart';
import '../../../sizeConfig.dart';
import '/src/model/firmware_update_request.dart';
import '/src/providers/firmware_update_request_provider.dart';
import '/src/view/peripheral_select/peripheral_list.dart';
import 'package:provider/provider.dart';

class PeripheralSelect extends StatelessWidget {
  const PeripheralSelect({super.key});

  @override
  Widget build(BuildContext context) {
    FirmwareUpdateRequest updateParameters =
        context.watch<FirmwareUpdateRequestProvider>().updateParameters;

    return Column(
      children: [
        if (updateParameters.peripheral != null)
          Text(updateParameters.peripheral!.name,style: hPi4Global.subValueWhiteTextStyle),
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
                MaterialPageRoute(builder: (context) => PeripheralList()),
              );
            },
            child: Text('Select Peripheral',style: TextStyle(fontSize: 12, color:hPi4Global.hpi4AppBarIconsColor))),
      ],
    );
  }
}
