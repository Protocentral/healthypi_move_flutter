import 'package:flutter/material.dart';
import 'package:move/src/providers/firmware_update_request_provider.dart';
import 'package:provider/provider.dart';
//#import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'home.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
        create: (context) => FirmwareUpdateRequestProvider()),
      ],
      child: MaterialApp(
        title: 'HealthyPi',
        theme: ThemeData(
          primarySwatch: Colors.purple,
          visualDensity: VisualDensity.adaptivePlatformDensity,
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ButtonStyle(
              //shape: MaterialStateProperty.resolveWith(getBorder),
            ),
          ),
        ),
        home: HomePage(), //HomeScreen(),
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
