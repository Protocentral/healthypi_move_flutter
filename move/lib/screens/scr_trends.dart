import 'package:flutter/material.dart';
import 'scr_hr.dart';
import 'scr_spo2.dart';
import 'scr_skin_temp.dart';
import 'scr_activity.dart';
import '../globals.dart';

class ScrTrends extends StatefulWidget {
  final String? initialMetric; // Optional: navigate to specific metric
  
  const ScrTrends({super.key, this.initialMetric});

  @override
  _ScrTrendsState createState() => _ScrTrendsState();
}

class _ScrTrendsState extends State<ScrTrends> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    
    // Determine initial tab index based on initialMetric parameter
    int initialIndex = 0;
    if (widget.initialMetric != null) {
      switch (widget.initialMetric) {
        case 'hr':
          initialIndex = 0;
          break;
        case 'spo2':
          initialIndex = 1;
          break;
        case 'temp':
          initialIndex = 2;
          break;
        case 'activity':
          initialIndex = 3;
          break;
      }
    }
    
    _tabController = TabController(
      length: 4, 
      vsync: this,
      initialIndex: initialIndex,
    );
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: hPi4Global.hpi4AppBarColor,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Image.asset(
              'assets/healthypi_move.png',
              height: 32,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 12),
            const Text(
              'Health Trends',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            color: hPi4Global.hpi4AppBarColor,
            child: TabBar(
              controller: _tabController,
              indicatorColor: hPi4Global.hpi4Color,
              indicatorWeight: 3,
              labelColor: hPi4Global.hpi4Color,
              unselectedLabelColor: Colors.grey[400],
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              tabs: const [
                Tab(
                  icon: Icon(Icons.favorite, size: 20),
                  text: 'Heart Rate',
                ),
                Tab(
                  icon: Icon(Icons.bloodtype, size: 20),
                  text: 'SpO2',
                ),
                Tab(
                  icon: Icon(Icons.thermostat, size: 20),
                  text: 'Temperature',
                ),
                Tab(
                  icon: Icon(Icons.directions_walk, size: 20),
                  text: 'Activity',
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          ScrHR(),
          ScrSPO2(),
          ScrSkinTemperature(),
          ScrActivity(),
        ],
      ),
    );
  }
}
