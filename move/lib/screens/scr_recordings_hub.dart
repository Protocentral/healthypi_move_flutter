import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:share_plus/share_plus.dart';
import '../globals.dart';
import '../models/research_recording.dart';
import '../utils/research_recording_manager.dart';
import 'scr_ecg_recordings.dart';
import 'scr_hrv_recordings.dart';
import 'scr_gsr_recordings.dart';

/// Unified recordings hub screen with tabs for Spot Check and Research recordings
class ScrRecordingsHub extends StatefulWidget {
  final String deviceMacAddress;

  const ScrRecordingsHub({super.key, required this.deviceMacAddress});

  @override
  State<ScrRecordingsHub> createState() => _ScrRecordingsHubState();
}

class _ScrRecordingsHubState extends State<ScrRecordingsHub>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey<_ResearchTabState> _researchTabKey = GlobalKey<_ResearchTabState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    // Rebuild to update actions based on current tab
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Recordings'),
        backgroundColor: hPi4Global.hpi4AppBarColor,
        foregroundColor: Colors.white,
        actions: _buildAppBarActions(),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: hPi4Global.hpi4Color,
          labelColor: hPi4Global.hpi4Color,
          unselectedLabelColor: Colors.grey[400],
          tabs: const [
            Tab(
              icon: Icon(Icons.monitor_heart, size: 20),
              text: 'Spot Check',
            ),
            Tab(
              icon: Icon(Symbols.science, size: 20),
              text: 'Research',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Spot Check (ECG recordings)
          _SpotCheckTab(deviceMacAddress: widget.deviceMacAddress),
          // Tab 2: Research recordings
          _ResearchTab(key: _researchTabKey, deviceMacAddress: widget.deviceMacAddress),
        ],
      ),
    );
  }

  List<Widget> _buildAppBarActions() {
    // Only show actions for Research tab (index 1)
    if (_tabController.index != 1) return [];

    return [
      IconButton(
        icon: const Icon(Icons.refresh),
        tooltip: 'Refresh',
        onPressed: () {
          _researchTabKey.currentState?.refreshSessions();
        },
      ),
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (value) async {
          switch (value) {
            case 'wipe_all':
              _showWipeAllDialog();
              break;
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'wipe_all',
            child: Row(
              children: [
                Icon(Icons.delete_forever, color: Colors.red, size: 20),
                SizedBox(width: 12),
                Text('Wipe All Research Data', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  Future<void> _showWipeAllDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text(
          'Wipe All Research Recordings?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will permanently delete ALL research recordings from the device.\n\nThis action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Wipe All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _researchTabKey.currentState?.wipeAllSessions();
    }
  }
}


class _SpotCheckTab extends StatefulWidget {
  final String deviceMacAddress;

  const _SpotCheckTab({required this.deviceMacAddress});

  @override
  State<_SpotCheckTab> createState() => _SpotCheckTabState();
}

class _SpotCheckTabState extends State<_SpotCheckTab> with SingleTickerProviderStateMixin {
  late TabController _nestedTabController;

  @override
  void initState() {
    super.initState();
    // Initialize nested tab controller with the number of sub-tabs you want
    _nestedTabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _nestedTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Nested TabBar
        Container(
          color: const Color(0xFF1E1E1E),
          child: TabBar(
            controller: _nestedTabController,
            indicatorColor: hPi4Global.hpi4Color,
            labelColor: hPi4Global.hpi4Color,
            unselectedLabelColor: Colors.grey[400],
            tabs: const [
              Tab(text: 'ECG'),
              Tab(text: 'HRV'),
              Tab(text: 'GSR'),
            ],
          ),
        ),
        // Nested TabBarView
        Expanded(
          child: TabBarView(
            controller: _nestedTabController,
            children: [
              // Sub-tab 1: All recordings
              ScrEcgRecordingsContent(deviceMacAddress: widget.deviceMacAddress),
              // Sub-tab 2: Recent recordings
              ScrHRVRecordingsContent(deviceMacAddress: widget.deviceMacAddress),
              // Sub-tab 3: Favorite recordings
              ScrGSRRecordingsContent(deviceMacAddress: widget.deviceMacAddress),
            ],
          ),
        ),
      ],
    );
  }

}

/// Spot Check tab - wraps the existing ECG recordings functionality
/*class _SpotCheckTab extends StatelessWidget {
  final String deviceMacAddress;

  const _SpotCheckTab({required this.deviceMacAddress});

  @override
  Widget build(BuildContext context) {
    // Directly embed the ECG recordings content
    return ScrEcgRecordingsContent(deviceMacAddress: deviceMacAddress);
  }
}*/

/// Research recordings tab
class _ResearchTab extends StatefulWidget {
  final String deviceMacAddress;

  const _ResearchTab({super.key, required this.deviceMacAddress});

  @override
  State<_ResearchTab> createState() => _ResearchTabState();
}

class _ResearchTabState extends State<_ResearchTab> {
  BluetoothDevice? _device;
  ResearchRecordingManager? _manager;

  List<ResearchRecording> _sessions = [];
  bool _isLoading = true;
  String? _errorMessage;

  RecordingStatus? _activeRecordingStatus;
  Timer? _statusPollTimer;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _statusPollTimer?.cancel();
    _manager?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      _device = BluetoothDevice.fromId(widget.deviceMacAddress);

      if (_device!.isDisconnected) {
        await _device!.connect(license: License.values.first, timeout: const Duration(seconds: 15));
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (_device!.servicesList.isEmpty) {
        await _device!.discoverServices();
      }

      _manager = ResearchRecordingManager(_device!);
      await _manager!.initialize();

      await _loadSessions();
      await _checkActiveRecording();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to initialize: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadSessions() async {
    if (!mounted || _manager == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final sessions = await _manager!.getSessionList();
      if (mounted) {
        setState(() {
          _sessions = sessions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load sessions: $e';
          _isLoading = false;
        });
      }
    }
  }

  /// Public method to refresh sessions from parent
  Future<void> refreshSessions() async {
    await _loadSessions();
    await _checkActiveRecording();
  }

  /// Public method to wipe all sessions from parent
  Future<void> wipeAllSessions() async {
    if (_manager == null) return;

    try {
      final result = await _manager!.wipeAll();
      if (result == 0) {
        await _loadSessions();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('All research recordings wiped from device'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Wipe failed (code: $result)'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Wipe failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _checkActiveRecording() async {
    if (_manager == null) return;

    try {
      final status = await _manager!.getStatus();
      if (mounted) {
        setState(() {
          _activeRecordingStatus = status.isRecording ? status : null;
        });

        if (status.isRecording) {
          _startStatusPolling();
        }
      }
    } catch (e) {
      print('Error checking active recording: $e');
    }
  }

  void _startStatusPolling() {
    _statusPollTimer?.cancel();
    _statusPollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_manager == null || !mounted) {
        _statusPollTimer?.cancel();
        return;
      }

      try {
        final status = await _manager!.getStatus();
        if (mounted) {
          setState(() {
            _activeRecordingStatus = status.isRecording ? status : null;
          });

          if (!status.isRecording) {
            _statusPollTimer?.cancel();
            _loadSessions(); // Refresh list when recording completes
          }
        }
      } catch (e) {
        print('Status poll error: $e');
      }
    });
  }

  Future<void> _stopRecording() async {
    if (_manager == null) return;

    try {
      await _manager!.stopRecording();
      _statusPollTimer?.cancel();
      setState(() {
        _activeRecordingStatus = null;
      });
      await _loadSessions();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recording stopped'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to stop recording: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteSession(ResearchRecording session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('Delete Recording?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete this research recording from ${session.formattedDateTime}?\n\nThis action cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || _manager == null) return;

    try {
      await _manager!.deleteSession(session);
      await _loadSessions();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recording deleted'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _navigateToNewRecording() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _ResearchRecordingConfigScreen(
          deviceMacAddress: widget.deviceMacAddress,
          onRecordingStarted: () {
            _checkActiveRecording();
          },
        ),
      ),
    );
  }

  void _navigateToSessionDetail(ResearchRecording session) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _ResearchSessionDetailScreen(
          session: session,
          deviceMacAddress: widget.deviceMacAddress,
          onDeleted: () {
            _loadSessions();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Active recording banner
        if (_activeRecordingStatus != null) _buildActiveRecordingBanner(),

        // Main content
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildActiveRecordingBanner() {
    final status = _activeRecordingStatus!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Colors.red.withOpacity(0.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.5),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'RECORDING IN PROGRESS',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: status.progress,
            backgroundColor: Colors.grey[700],
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${status.elapsedFormatted} elapsed',
                style: TextStyle(color: Colors.grey[400], fontSize: 13),
              ),
              Text(
                '${status.remainingFormatted} remaining',
                style: TextStyle(color: Colors.grey[400], fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Signals: ${status.signals.map((s) => s.shortName).join(', ')}',
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _stopRecording,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
              child: const Text('Stop Recording'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Loading research recordings...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadSessions,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: hPi4Global.hpi4Color,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_sessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Symbols.science, size: 64, color: Colors.grey[600]),
              const SizedBox(height: 16),
              const Text(
                'No research recordings',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Start a new multi-signal research recording',
                style: TextStyle(color: Colors.grey[500], fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _navigateToNewRecording,
                icon: const Icon(Icons.add),
                label: const Text('New Recording'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: hPi4Global.hpi4Color,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadSessions,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _sessions.length,
            itemBuilder: (context, index) => _buildSessionCard(_sessions[index]),
          ),
        ),
        // FAB for new recording
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton.extended(
            onPressed: _activeRecordingStatus != null ? null : _navigateToNewRecording,
            backgroundColor: _activeRecordingStatus != null
                ? Colors.grey
                : hPi4Global.hpi4Color,
            icon: const Icon(Icons.add),
            label: const Text('New Recording'),
          ),
        ),
      ],
    );
  }

  Widget _buildSessionCard(ResearchRecording session) {
    return Card(
      color: const Color(0xFF2D2D2D),
      elevation: 4,
      shadowColor: Colors.black54,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Symbols.science,
                    color: Colors.blue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Research Recording',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        session.formattedDateTime,
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Session info
            Row(
              children: [
                _buildInfoChip(Icons.timer, session.formattedDuration),
                const SizedBox(width: 8),
                _buildInfoChip(Icons.storage, session.formattedSize),
              ],
            ),
            const SizedBox(height: 8),
            // Signals
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: session.signals.map((signal) {
                return Chip(
                  avatar: Icon(signal.icon, size: 16, color: Colors.white70),
                  label: Text(
                    signal.shortName,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  backgroundColor: Colors.grey[700],
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _navigateToSessionDetail(session),
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Download'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: hPi4Global.hpi4Color,
                      side: BorderSide(color: hPi4Global.hpi4Color),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _deleteSession(session),
                  icon: const Icon(Icons.delete_outline),
                  color: Colors.red[300],
                  tooltip: 'Delete recording',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey[400]),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Research recording configuration screen
class _ResearchRecordingConfigScreen extends StatefulWidget {
  final String deviceMacAddress;
  final VoidCallback? onRecordingStarted;

  const _ResearchRecordingConfigScreen({
    required this.deviceMacAddress,
    this.onRecordingStarted,
  });

  @override
  State<_ResearchRecordingConfigScreen> createState() =>
      _ResearchRecordingConfigScreenState();
}

class _ResearchRecordingConfigScreenState
    extends State<_ResearchRecordingConfigScreen> {
  BluetoothDevice? _device;
  ResearchRecordingManager? _manager;
  bool _isInitializing = true;
  bool _isStarting = false;
  String? _errorMessage;

  // Configuration
  int _selectedDurationMinutes = 10;
  final Set<ResearchSignalType> _selectedSignals = {
    ResearchSignalType.ppgWrist,
    ResearchSignalType.accel,
  };

  static const List<int> _durationOptions = [1, 5, 10, 30, 60];

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _manager?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      _device = BluetoothDevice.fromId(widget.deviceMacAddress);

      if (_device!.isDisconnected) {
        await _device!.connect(license: License.values.first, timeout: const Duration(seconds: 15));
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (_device!.servicesList.isEmpty) {
        await _device!.discoverServices();
      }

      _manager = ResearchRecordingManager(_device!);
      await _manager!.initialize();

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to connect: $e';
          _isInitializing = false;
        });
      }
    }
  }

  RecordingConfig get _config => RecordingConfig(
    durationSeconds: _selectedDurationMinutes * 60,
    signalMask: ResearchSignalTypeExtension.toMask(_selectedSignals.toList()),
  );

  Future<void> _startRecording() async {
    if (_manager == null || _selectedSignals.isEmpty) return;

    setState(() {
      _isStarting = true;
    });

    try {
      // Configure
      final configResult = await _manager!.configure(_config);
      if (configResult != 0) {
        throw Exception('Configuration failed (code: $configResult)');
      }

      // Start
      final startResult = await _manager!.startRecording();
      if (startResult != 0) {
        throw Exception('Start failed (code: $startResult)');
      }

      widget.onRecordingStarted?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recording started!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start recording: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('New Research Recording'),
        backgroundColor: hPi4Global.hpi4AppBarColor,
        foregroundColor: Colors.white,
      ),
      body: _isInitializing
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Connecting to device...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      )
          : _errorMessage != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      )
          : _buildConfigForm(),
    );
  }

  Widget _buildConfigForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Duration selector
          _buildSectionHeader('DURATION'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _durationOptions.map((minutes) {
              final isSelected = _selectedDurationMinutes == minutes;
              return ChoiceChip(
                label: Text('$minutes min'),
                selected: isSelected,
                onSelected: (_) {
                  setState(() {
                    _selectedDurationMinutes = minutes;
                  });
                },
                selectedColor: hPi4Global.hpi4Color,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey[400],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // Signal selector
          _buildSectionHeader('SIGNALS TO RECORD'),
          const SizedBox(height: 8),
          ...ResearchSignalType.values.map((signal) {
            final isSelected = _selectedSignals.contains(signal);
            return Card(
              color: const Color(0xFF2D2D2D),
              margin: const EdgeInsets.only(bottom: 8),
              child: CheckboxListTile(
                value: isSelected,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _selectedSignals.add(signal);
                    } else {
                      _selectedSignals.remove(signal);
                    }
                  });
                },
                title: Row(
                  children: [
                    Icon(signal.icon, color: Colors.white70, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      signal.displayName,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
                subtitle: Text(
                  signal.description,
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
                secondary: Text(
                  '${signal.kbPerMinute.toStringAsFixed(1)} KB/min',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
                activeColor: hPi4Global.hpi4Color,
                checkColor: Colors.white,
              ),
            );
          }),
          const SizedBox(height: 24),

          // Storage estimate
          _buildSectionHeader('STORAGE ESTIMATE'),
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFF2D2D2D),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.storage, color: Colors.grey[400]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Estimated size: ${_config.estimatedSizeFormatted}',
                          style: const TextStyle(color: Colors.white),
                        ),
                        Text(
                          '${_selectedSignals.length} signal(s) × ${_selectedDurationMinutes} min',
                          style: TextStyle(color: Colors.grey[500], fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (_selectedSignals.isNotEmpty)
                    Icon(Icons.check_circle, color: Colors.green[400]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Start button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _selectedSignals.isEmpty || _isStarting
                  ? null
                  : _startRecording,
              icon: _isStarting
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(Icons.fiber_manual_record, color: Colors.red),
              label: Text(_isStarting ? 'Starting...' : 'START RECORDING'),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                _selectedSignals.isEmpty ? Colors.grey : hPi4Global.hpi4Color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          if (_selectedSignals.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Select at least one signal to record',
              style: TextStyle(color: Colors.orange[300], fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.grey[400],
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }
}

/// Research session detail and download screen
class _ResearchSessionDetailScreen extends StatefulWidget {
  final ResearchRecording session;
  final String deviceMacAddress;
  final VoidCallback? onDeleted;

  const _ResearchSessionDetailScreen({
    required this.session,
    required this.deviceMacAddress,
    this.onDeleted,
  });

  @override
  State<_ResearchSessionDetailScreen> createState() =>
      _ResearchSessionDetailScreenState();
}

class _ResearchSessionDetailScreenState
    extends State<_ResearchSessionDetailScreen> {
  BluetoothDevice? _device;
  ResearchRecordingManager? _manager;
  bool _isInitializing = true;
  String? _errorMessage;

  // Download state
  bool _isDownloading = false;
  String _downloadStatus = '';
  double _downloadProgress = 0.0;
  ResearchSignalType? _currentSignal;
  Map<ResearchSignalType, Uint8List> _downloadedData = {};
  Map<ResearchSignalType, bool> _downloadedSignals = {};

  // Export state
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _initialize();
    // Initialize download status for each signal
    for (var signal in widget.session.signals) {
      _downloadedSignals[signal] = false;
    }
  }

  @override
  void dispose() {
    _manager?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      _device = BluetoothDevice.fromId(widget.deviceMacAddress);

      if (_device!.isDisconnected) {
        await _device!.connect(
          license: License.values.first,
          timeout: const Duration(seconds: 15),
        );
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (_device!.servicesList.isEmpty) {
        await _device!.discoverServices();
      }

      _manager = ResearchRecordingManager(_device!);
      await _manager!.initialize();

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to connect: $e';
          _isInitializing = false;
        });
      }
    }
  }

  Future<void> _downloadSignal(ResearchSignalType signal) async {
    if (_manager == null || _isDownloading) return;

    setState(() {
      _isDownloading = true;
      _currentSignal = signal;
      _downloadStatus = 'Downloading ${signal.displayName}...';
      _downloadProgress = 0.0;
    });

    try {
      final data = await _manager!.downloadSignalFile(
        widget.session,
        signal,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
            });
          }
        },
      );

      // Save to local storage
      await _manager!.saveSignalFile(
        widget.session,
        signal,
        data,
        widget.deviceMacAddress,
      );

      if (mounted) {
        setState(() {
          _downloadedData[signal] = data;
          _downloadedSignals[signal] = true;
          _isDownloading = false;
          _currentSignal = null;
          _downloadStatus = '';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${signal.displayName} downloaded successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _currentSignal = null;
          _downloadStatus = '';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _downloadAllSignals() async {
    if (_manager == null || _isDownloading) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    final signals = widget.session.signals;
    int completed = 0;

    for (final signal in signals) {
      if (!mounted) break;

      setState(() {
        _currentSignal = signal;
        _downloadStatus = 'Downloading ${signal.displayName} (${completed + 1}/${signals.length})...';
        _downloadProgress = completed / signals.length;
      });

      try {
        final data = await _manager!.downloadSignalFile(
          widget.session,
          signal,
        );

        await _manager!.saveSignalFile(
          widget.session,
          signal,
          data,
          widget.deviceMacAddress,
        );

        _downloadedData[signal] = data;
        _downloadedSignals[signal] = true;
        completed++;
      } catch (e) {
        print('Failed to download ${signal.displayName}: $e');
      }
    }

    if (mounted) {
      setState(() {
        _isDownloading = false;
        _currentSignal = null;
        _downloadStatus = '';
        _downloadProgress = 1.0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloaded $completed/${signals.length} signals'),
          backgroundColor: completed == signals.length ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  Future<void> _exportToCsv(ResearchSignalType signal) async {
    if (_manager == null || !_downloadedSignals.containsKey(signal)) return;

    final data = _downloadedData[signal];
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please download ${signal.displayName} first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isExporting = true;
    });

    try {
      final file = await _manager!.exportToCsv(widget.session, signal, data);

      if (mounted) {
        setState(() {
          _isExporting = false;
        });

        // Share the file
        await Share.shareXFiles(
          [XFile(file.path)],
          text: '${signal.displayName} data from research recording',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _exportAllAsZip() async {
    if (_manager == null || _downloadedData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please download at least one signal first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isExporting = true;
    });

    try {
      final file = await _manager!.exportToZip(widget.session, _downloadedData);

      if (mounted) {
        setState(() {
          _isExporting = false;
        });

        // Share the ZIP file
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'Research recording from ${widget.session.formattedDateTime}',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('Delete Recording?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete this research recording from ${widget.session.formattedDateTime}?\n\nThis will remove it from the device and cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || _manager == null) return;

    try {
      await _manager!.deleteSession(widget.session);
      widget.onDeleted?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recording deleted'),
            backgroundColor: Colors.blue,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Recording Details'),
        backgroundColor: hPi4Global.hpi4AppBarColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            color: Colors.red[300],
            onPressed: _deleteSession,
            tooltip: 'Delete recording',
          ),
        ],
      ),
      body: _isInitializing
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Connecting to device...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      )
          : _errorMessage != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      )
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Session info card
          Card(
            color: const Color(0xFF2D2D2D),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Symbols.science,
                          color: Colors.blue,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Research Recording',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.session.formattedDateTime,
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildInfoChip(Icons.timer, widget.session.formattedDuration),
                      const SizedBox(width: 8),
                      _buildInfoChip(Icons.storage, widget.session.formattedSize),
                      const SizedBox(width: 8),
                      _buildInfoChip(Icons.sensors, '${widget.session.signals.length} signals'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Download progress
          if (_isDownloading) ...[
            Card(
              color: const Color(0xFF2D2D2D),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _downloadStatus,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: _downloadProgress,
                      backgroundColor: Colors.grey[700],
                      valueColor: AlwaysStoppedAnimation<Color>(hPi4Global.hpi4Color),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Download all button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isDownloading || _isExporting ? null : _downloadAllSignals,
              icon: const Icon(Icons.download),
              label: const Text('Download All Signals'),
              style: ElevatedButton.styleFrom(
                backgroundColor: hPi4Global.hpi4Color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Signals section
          Text(
            'SIGNALS',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          ...widget.session.signals.map((signal) => _buildSignalCard(signal)),
          const SizedBox(height: 24),

          // Export section
          if (_downloadedData.isNotEmpty) ...[
            Text(
              'EXPORT',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              color: const Color(0xFF2D2D2D),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isDownloading || _isExporting ? null : _exportAllAsZip,
                        icon: _isExporting
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : const Icon(Icons.archive),
                        label: Text(_isExporting ? 'Exporting...' : 'Export as ZIP'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Exports all downloaded signals as CSV files with metadata in a ZIP archive',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSignalCard(ResearchSignalType signal) {
    final isDownloaded = _downloadedSignals[signal] ?? false;
    final isCurrentlyDownloading = _currentSignal == signal;

    return Card(
      color: const Color(0xFF2D2D2D),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDownloaded
                    ? Colors.green.withOpacity(0.2)
                    : Colors.grey.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                signal.icon,
                color: isDownloaded ? Colors.green : Colors.grey[400],
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    signal.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${signal.sampleRateHz} Hz • ${signal.kbPerMinute.toStringAsFixed(1)} KB/min',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (isCurrentlyDownloading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (isDownloaded)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.share, size: 20),
                    color: hPi4Global.hpi4Color,
                    onPressed: _isExporting ? null : () => _exportToCsv(signal),
                    tooltip: 'Export CSV',
                  ),
                  const Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 24,
                  ),
                ],
              )
            else
              IconButton(
                icon: const Icon(Icons.download, size: 20),
                color: hPi4Global.hpi4Color,
                onPressed: _isDownloading ? null : () => _downloadSignal(signal),
                tooltip: 'Download',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey[400]),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
          ),
        ],
      ),
    );
  }
}