import 'package:flutter/material.dart';
import '../home.dart';
import '../sizeConfig.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../globals.dart';

class SPO2Page extends StatefulWidget {
  const SPO2Page({Key? key}) : super(key: key);
  @override
  State<SPO2Page> createState() => _SPO2PageState();
}
class _SPO2PageState extends State<SPO2Page>
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
            'SPO2',
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
                              Text("98", style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.black),),
                              Text("%", style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.black),),
                              Text("AVERAGE", style: TextStyle(fontSize: 12, color: Colors.black),),
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
                              width: SizeConfig.blockSizeHorizontal * 44,
                              child: Card(
                                // color: Colors.white,
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
                                            Text('MAXIMUM',
                                                style: hPi4Global.movecardSubValueTextStyle),
                                            SizedBox(
                                              width: 15.0,
                                            ),
                                            //Icon(Icons.favorite_border, color: Colors.black),
                                          ],
                                        ),
                                        SizedBox(
                                          height: 70.0,
                                        ),
                                        Row(
                                          children: <Widget>[
                                            SizedBox(
                                              width: 10.0,
                                            ),
                                            Text('98%',
                                                style: hPi4Global.moveValueTextStyle),
                                            SizedBox(
                                              width: 10.0,
                                            ),

                                          ],
                                        ),
                                      ]),
                                ),
                              ),
                            ),
                            Column(
                              //mainAxisAlignment: MainAxisAlignment.start,
                                children: <Widget>[
                                  Container(
                                    height: SizeConfig.blockSizeVertical * 10,
                                    width: SizeConfig.blockSizeHorizontal * 44,
                                    child: Card(
                                      //color: Colors.white,
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
                                                  Text('98%',
                                                      style: hPi4Global.moveValueTextStyle),
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
                                                  Text('MINIMUM',
                                                      style: hPi4Global.movecardSubValueTextStyle),
                                                ],
                                              ),

                                            ]),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    height: SizeConfig.blockSizeVertical * 10,
                                    width: SizeConfig.blockSizeHorizontal * 44,
                                    child: Card(
                                      //color: Colors.white,
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
                                                  Text('98%',
                                                      style: hPi4Global.moveValueTextStyle),
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
                                                  Text('AVERAGE',
                                                      style: hPi4Global.movecardSubValueTextStyle),
                                                ],
                                              ),

                                            ]),
                                      ),
                                    ),
                                  )
                                ]
                            ),

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
