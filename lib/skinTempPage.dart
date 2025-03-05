import 'package:flutter/material.dart';
import 'home.dart';
import 'sizeConfig.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import 'globals.dart';

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              Container(
                  child: SfCartesianChart(
                      primaryXAxis: NumericAxis(
                          minimum: 0,
                          maximum: 150
                      ),
                      primaryYAxis: NumericAxis(
                          minimum: 0,
                          maximum: 100
                      ),
                      palette: <Color>[
                        Color(0xFF125871),
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
        appBar: AppBar(
          leading: IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => HomePage()))
          ),
          title: const Text(
            'Skin Temerature',
            style: TextStyle(fontSize: 16),
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
                  color: Colors.grey.shade100,
                ),
                child: const TabBar(
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: hPi4Global.hpi4Color,
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.black54,
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
              color: Colors.grey[200],
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          height: SizeConfig.blockSizeVertical * 10,
                          width: SizeConfig.blockSizeHorizontal * 80,
                          //color:Colors.white,
                          child:const Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text("92.19", style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.black),),
                              Text("\u00b0 F", style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.black),),
                            ],
                          ),
                        ),
                        SizedBox(height: 30),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              height: SizeConfig.blockSizeVertical * 45,
                              width: SizeConfig.blockSizeHorizontal * 88,
                              //color:Colors.white,
                              child:buildchartBlock(),
                            )
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              height: SizeConfig.blockSizeVertical * 20,
                              width: SizeConfig.blockSizeHorizontal * 88,
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
