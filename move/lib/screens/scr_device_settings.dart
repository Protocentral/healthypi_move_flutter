import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/device_info.dart';
import '../utils/device_manager.dart';
import '../utils/database_helper.dart';
import '../globals.dart';
import 'scr_device_scan.dart';

/// Dedicated device management screen for paired HealthyPi Move devices
/// Allows users to view device info, edit nickname, and unpair devices
class ScrDeviceSettings extends StatefulWidget {
  const ScrDeviceSettings({Key? key}) : super(key: key);

  @override
  State<ScrDeviceSettings> createState() => _ScrDeviceSettingsState();
}

class _ScrDeviceSettingsState extends State<ScrDeviceSettings> {
  DeviceInfo? _pairedDevice;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPairedDevice();
  }

  Future<void> _loadPairedDevice() async {
    final device = await DeviceManager.getPairedDevice();
    if (mounted) {
      setState(() {
        _pairedDevice = device;
        _loading = false;
      });
    }
  }

  Future<void> _unpairDevice() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2D2D2D),
        title: Text(
          'Unpair Device?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'This will remove the paired device. You\'ll need to pair again to use automatic connection.',
          style: TextStyle(color: Colors.grey[300]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: Text('Unpair'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DeviceManager.unpairDevice();
      if (mounted) {
        setState(() {
          _pairedDevice = null;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Device unpaired successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _pairNewDevice() async {
    // Check if existing device has data
    final hasData = _pairedDevice != null 
        ? await DatabaseHelper.instance.hasDataForDevice(_pairedDevice!.macAddress)
        : false;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2D2D2D),
        title: Row(
          children: [
            Icon(Icons.bluetooth_searching, color: hPi4Global.hpi4Color, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Pair New Device?',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will unpair "${_pairedDevice?.displayName}" and start scanning for a new device.',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            if (hasData) ...[
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Health data from the current device will be deleted.',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400], fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: hPi4Global.hpi4Color,
              foregroundColor: Colors.white,
            ),
            child: Text(
              'Continue',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Delete data if exists
      if (hasData && _pairedDevice != null) {
        await DatabaseHelper.instance.deleteDataForDevice(_pairedDevice!.macAddress);
      }
      
      // Unpair device
      await DeviceManager.unpairDevice();
      
      if (mounted) {
        // Navigate to scan screen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const ScrDeviceScan(pairOnly: true),
          ),
        );
      }
    }
  }

  Future<void> _editNickname() async {
    if (_pairedDevice == null) return;
    
    final controller = TextEditingController(text: _pairedDevice!.nickname);
    
    final newNickname = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2D2D2D),
        title: Text('Edit Nickname', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Device Nickname',
            labelStyle: TextStyle(color: Colors.grey[400]),
            hintText: 'e.g., "My Watch", "Work Device"',
            hintStyle: TextStyle(color: Colors.grey[600]),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey[700]!),
              borderRadius: BorderRadius.circular(8),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: hPi4Global.hpi4Color),
              borderRadius: BorderRadius.circular(8),
            ),
            prefixIcon: Icon(Icons.edit, color: Colors.grey[500]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: hPi4Global.hpi4Color,
            ),
            child: Text('Save'),
          ),
        ],
      ),
    );

    if (newNickname != null) {
      await DeviceManager.updateNickname(newNickname);
      await _loadPairedDevice(); // Reload to show updated info
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Nickname updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: hPi4Global.hpi4AppBarColor,
        title: Text('Device Settings', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: hPi4Global.hpi4Color))
          : _pairedDevice == null
              ? _buildNoPairedDevice()
              : _buildPairedDeviceInfo(),
    );
  }

  Widget _buildNoPairedDevice() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.watch_off_outlined,
              size: 80,
              color: Colors.grey[700],
            ),
            SizedBox(height: 24),
            Text(
              'No Paired Device',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Connect to a HealthyPi Move device and pair it to enable automatic reconnection.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
              ),
            ),
            SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => const ScrDeviceScan(pairOnly: true),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: hPi4Global.hpi4Color,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: Icon(Icons.bluetooth_searching, size: 24),
              label: Text(
                'Pair Device',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPairedDeviceInfo() {
    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        // Device Card
        Card(
          color: Color(0xFF2D2D2D),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: hPi4Global.hpi4Color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.watch,
                        color: hPi4Global.hpi4Color,
                        size: 32,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _pairedDevice!.displayName,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_pairedDevice!.nickname.isNotEmpty)
                            Text(
                              _pairedDevice!.deviceName,
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 14,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.edit, color: hPi4Global.hpi4Color),
                      onPressed: _editNickname,
                      tooltip: 'Edit nickname',
                    ),
                  ],
                ),
                Divider(color: Colors.grey[700], height: 32),
                _buildInfoRow(
                  Icons.fingerprint,
                  'MAC Address',
                  _pairedDevice!.macAddress,
                ),
                SizedBox(height: 12),
                _buildInfoRow(
                  Icons.calendar_today,
                  'First Paired',
                  DateFormat('MMM dd, yyyy').format(_pairedDevice!.firstPaired),
                ),
                if (_pairedDevice!.lastConnected != null) ...[
                  SizedBox(height: 12),
                  _buildInfoRow(
                    Icons.access_time,
                    'Last Connected',
                    _formatLastConnected(_pairedDevice!.lastConnected!),
                  ),
                ],
                if (_pairedDevice!.firmwareVersion != null) ...[
                  SizedBox(height: 12),
                  _buildInfoRow(
                    Icons.system_update,
                    'Firmware',
                    _pairedDevice!.firmwareVersion!,
                  ),
                ],
                if (_pairedDevice!.batteryLevel != null) ...[
                  SizedBox(height: 12),
                  _buildInfoRow(
                    Icons.battery_full,
                    'Battery',
                    '${_pairedDevice!.batteryLevel}%',
                  ),
                ],
              ],
            ),
          ),
        ),
        
        SizedBox(height: 24),
        
        // Pair New Device Button
        ElevatedButton.icon(
          onPressed: _pairNewDevice,
          style: ElevatedButton.styleFrom(
            backgroundColor: hPi4Global.hpi4Color,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: Icon(Icons.add_circle_outline),
          label: Text(
            'Pair New Device',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        
        SizedBox(height: 12),
        
        // Unpair Button
        ElevatedButton.icon(
          onPressed: _unpairDevice,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: Icon(Icons.link_off),
          label: Text(
            'Unpair Device',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey[500], size: 20),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 12,
                ),
              ),
              SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatLastConnected(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes} minutes ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hours ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return DateFormat('MMM dd, yyyy').format(dateTime);
    }
  }
}
