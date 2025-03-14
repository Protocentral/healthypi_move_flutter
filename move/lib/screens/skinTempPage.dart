import 'package:flutter/material.dart';
import '../home.dart';
import '../sizeConfig.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../globals.dart';

class SkinTemperaturePage extends StatefulWidget {
  const SkinTemperaturePage({Key? key}) : super(key: key);
  @override
  State<SkinTemperaturePage> createState() => _SkinTemperaturePageState();
}
class _SkinTemperaturePageState extends State<SkinTemperaturePage>
    with SingleTickerProviderStateMixin {

  @override
  void initState() {
    super.initState();
  }

  Widget buildchartBlock() {
    return Padding(
      padding: const EdgeInsets.all(2.0),
      child: Card(
        color: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              Container(
                  child: SfCartesianChart(
                      plotAreaBorderWidth: 0,
                      primaryXAxis: NumericAxis(
                          minimum: 0,
                          maximum: 24,
                          interval: 8,
                          majorGridLines: MajorGridLines(width: 0),
                          labelStyle: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500
                          )
                      ),
                      primaryYAxis: NumericAxis(
                          majorGridLines: MajorGridLines(width: 0.05),
                          minimum: 0,
                          maximum: 200,
                          interval: 10,
                          labelStyle: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500
                          )
                      ),
                      palette: <Color>[
                        hPi4Global.hpi4Color,
                      ],
                      series: <CartesianSeries>[
                        HiloSeries<ChartData, int>(
                            dataSource: <ChartData>[

                            ],
                            xValueMapper: (ChartData data, _) => data.x,
                            lowValueMapper: (ChartData data, _) => data.low,
                            highValueMapper: (ChartData data, _) => data.high
                        )

                      ]
                  )
              )
            ]),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: hPi4Global.appBackgroundColor,
        appBar: AppBar(
          backgroundColor: hPi4Global.hpi4AppBarColor,
          leading: IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => HomePage()))
          ),
          title: const Text(
            'Skin Temerature',
            style: TextStyle(fontSize: 16, color:Colors.white),
          ),
          centerTitle: true,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(40),
            child: ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              child: Container(
                height: 40,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(Radius.circular(10)),
                  color: Colors.grey.shade800,
                ),
                child: const TabBar(
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: hPi4Global.hpi4Color,
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white,
                  tabs: [
                    Text('Day'),
                    Text('Week'),
                    Text('Month')
                  ],
                ),
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            Card(
              color: Colors.black,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(height: 30),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              height: SizeConfig.blockSizeVertical * 45,
                              width: SizeConfig.blockSizeHorizontal * 88,
                              color:Colors.transparent,
                              child:buildchartBlock(),
                            )
                          ],
                        ),
                        SizedBox(height:20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              height: SizeConfig.blockSizeVertical * 10,
                              width: SizeConfig.blockSizeHorizontal * 88,
                              child: Card(
                                color: Colors.grey[900],
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Column(
                                      mainAxisAlignment: MainAxisAlignment.start,
                                      children: <Widget>[
                                        Row(
                                          children: <Widget>[
                                            SizedBox(
                                              width: 10.0,
                                            ),
                                            Text('Latest',
                                                style: hPi4Global.movecardSubValueTextStyle),
                                            SizedBox(
                                              width: 15.0,
                                            ),
                                            //Icon(Icons.favorite_border, color: Colors.black),
                                          ],
                                        ),
                                        Row(
                                          children: <Widget>[
                                            SizedBox(
                                              width: 10.0,
                                            ),
                                            Text("92.19", style: hPi4Global.moveValueTextStyle),
                                            Text("\u00b0 F", style: hPi4Global.moveValueTextStyle),
                                            SizedBox(
                                              width: 10.0,
                                            ),

                                          ],
                                        ),
                                      ]),
                                ),
                              ),
                            )
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Center(child: Text('Week')),
            const Center(child: Text('Month')),
          ],
        ),
      ),
    );
  }
}

class ChartData {
  ChartData(this.x, this.high, this.low);
  final int x;
  final double high;
  final double low;
}
