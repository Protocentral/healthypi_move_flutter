import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../globals.dart';
import '../../../sizeConfig.dart';
import '/src/model/firmware_update_request.dart';
import '/src/providers/firmware_update_request_provider.dart';
import '/src/view/logger_screen/logger_screen.dart';

import '../../bloc/bloc/update_bloc.dart';

class UpdateStepView extends StatelessWidget {
  const UpdateStepView({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FirmwareUpdateRequestProvider>();
    final request = provider.updateParameters;
    return BlocBuilder<UpdateBloc, UpdateState>(
      builder: (context, state) {
        switch (state) {
          case UpdateInitial():
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _firmwareInfo(context, request.firmware!),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hPi4Global.hpi4Color, // background color
                    foregroundColor: Colors.white, // text color
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                   // minimumSize: Size(SizeConfig.blockSizeHorizontal*100, 30),
                  ),
                  onPressed: () {
                    context.read<UpdateBloc>().add(BeginUpdateProcess());
                  },
                  child: Text('Update', style: TextStyle(fontSize: 12, color:hPi4Global.hpi4AppBarIconsColor)),
                ),
              ],
            );
          case UpdateFirmwareStateHistory():
            return Column(
              children: [
                for (var state in state.history)
                  Row(
                    children: [
                      _stateIcon(state),
                      Text(state.stage,style: hPi4Global.subValueWhiteTextStyle),
                    ],
                  ),
                if (state.currentState != null)
                  Row(
                    children: [
                      CircularProgressIndicator(),
                      _currentState(state),
                    ],
                  ),
                if (state.isComplete && state.updateManager?.logger != null)
                  ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: hPi4Global.hpi4Color, // background color
                        foregroundColor: Colors.white, // text color
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                       // minimumSize: Size(SizeConfig.blockSizeHorizontal*100, 30),
                      ),
                      onPressed: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => LoggerScreen(
                                      logger: state.updateManager!.logger,
                                    )));
                      },
                      child: Text('Show Log',style: TextStyle(fontSize: 12, color:hPi4Global.hpi4AppBarIconsColor))),
                if (state.isComplete)
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
                      BlocProvider.of<UpdateBloc>(context).add(ResetUpdate());
                      provider.reset();
                    },
                    child: Text('Update Again',style: TextStyle(fontSize: 12, color:hPi4Global.hpi4AppBarIconsColor)),
                  ),
              ],
            );
          default:
            return Text('Unknown state',style: hPi4Global.subValueWhiteTextStyle);
        }
      },
    );
  }

  Icon _stateIcon(UpdateFirmware state) {
    if (state is UpdateCompleteFailure) {
      return Icon(Icons.error_outline, color: Colors.red);
    } else {
      return Icon(Icons.check_circle_outline, color: Colors.green);
    }
  }

  Text _currentState(UpdateFirmwareStateHistory state) {
    final currentState = state.currentState;
    if (currentState == null) {
      return Text('Unknown state',style: hPi4Global.subValueWhiteTextStyle);
    } else if (currentState is UpdateProgressFirmware) {
      return Text("Uploading ${currentState.progress}%",style: hPi4Global.subValueWhiteTextStyle);
    } else {
      return Text(currentState.stage,style: hPi4Global.subValueWhiteTextStyle);
    }
  }

  Widget _firmwareInfo(BuildContext context, SelectedFirmware firmware) {
    if (firmware is LocalFirmware) {
      return _localFirmwareInfo(context, firmware);
    } else if (firmware is RemoteFirmware) {
      return _remoteFirmwareInfo(context, firmware);
    } else {
      return Text('Unknown firmware type',style: hPi4Global.subValueWhiteTextStyle);
    }
  }

  Widget _localFirmwareInfo(BuildContext context, LocalFirmware firmware) {
    return Text('Firmware: ${firmware.name}',style: hPi4Global.subValueWhiteTextStyle);
  }

  Widget _remoteFirmwareInfo(BuildContext context, RemoteFirmware firmware) {
    return Column(
      children: [
        Text('Firmware: ${firmware.application.appName}',style: hPi4Global.subValueWhiteTextStyle),
        Text('Version: ${firmware.version.version}',style: hPi4Global.subValueWhiteTextStyle),
        Text('Board: ${firmware.board.name}',style: hPi4Global.subValueWhiteTextStyle),
        Text('Firmware: ${firmware.firmware.name}',style: hPi4Global.subValueWhiteTextStyle),
      ],
    );
  }
}
