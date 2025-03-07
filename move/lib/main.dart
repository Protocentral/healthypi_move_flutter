import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'home.dart';
import 'ble/ble_status_monitor.dart';
import 'ble/ble_device_connector.dart';
import 'ble/ble_logger.dart';
import 'ble/ble_scanner.dart';
import 'states/WiserBLEProvider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final _bleLogger = BleLogger();
  final _ble = FlutterReactiveBle();
  final _scanner = BleScanner(ble: _ble, logMessage: _bleLogger.addToLog);
  final _connector = BleDeviceConnector(
    ble: _ble,
    logMessage: _bleLogger.addToLog,
  );
  final _monitor = BleStatusMonitor(_ble);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<WiserBLEProvider>(
            create: (context) => WiserBLEProvider(ble: _ble)),
        Provider.value(value: _scanner),
        Provider.value(value: _monitor),
        StreamProvider<BleScannerState>(
          create: (_) => _scanner.state,
          initialData: BleScannerState(
            discoveredDevices: [],
            scanIsInProgress: false,
          ),
        ),
        StreamProvider<BleStatus?>(
          create: (_) => _monitor.state,
          initialData: BleStatus.unknown,
        ),
        /*StreamProvider<BleStatus>(
          create: (_) => _monitor.state,
          initialData: BleStatus.unknown,
        ),
        */
        StreamProvider<ConnectionStateUpdate>(
          create: (_) => _connector.state,
          initialData: const ConnectionStateUpdate(
            deviceId: 'Unknown device',
            connectionState: DeviceConnectionState.disconnected,
            failure: null,
          ),
        ),
      ],
      child: MaterialApp(
          title: 'HealthyPi',
          theme: ThemeData(
            primarySwatch: Colors.purple,
            visualDensity: VisualDensity.adaptivePlatformDensity,
            elevatedButtonTheme: ElevatedButtonThemeData(
                style: ButtonStyle(
                    //shape: MaterialStateProperty.resolveWith(getBorder),
                    )),
          ),
          home: HomePage() //HomeScreen(),
          ),
    ),
  );
  //runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HealthyPi5',
      initialRoute: '/',
      routes: {
        //'/newsession': (context) => NewSessionPage(
        //      title: "Title",
        //    ),
      },
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: HomePage(),
    );
  }
}
