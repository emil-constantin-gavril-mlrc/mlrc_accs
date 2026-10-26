import 'dart:async';
import 'package:flutter/material.dart';

void main() {
  runApp(const WatcherTerminalApp());
}

class WatcherTerminalApp extends StatelessWidget {
  const WatcherTerminalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Watcher Terminal',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF38BDF8),
          surface: Color(0xFF1E293B),
        ),
      ),
      home: const TerminalDashboard(),
    );
  }
}

class TerminalDashboard extends StatefulWidget {
  const TerminalDashboard({super.key});

  @override
  State<TerminalDashboard> createState() => _TerminalDashboardState();
}

class _TerminalDashboardState extends State<TerminalDashboard> {
  // Compile-time environment flags loaded via --dart-define-from-file
  static const String _envMode = String.fromEnvironment('OPERATION_MODE', defaultValue: 'Standby');
  static const bool _envDebugLogs = bool.fromEnvironment('ENABLE_DEBUG_LOGS', defaultValue: false);
  static const bool _showDebugPanel = bool.fromEnvironment('SHOW_DEBUG_PANEL', defaultValue: false);

  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();
  
  bool _isStreaming = false;
  late String _activeMode;
  final String _commType = 'Auto (USB preferred)';
  
  StreamSubscription? _eventSubscription;
  Timer? _screencapTimer;
  bool _initialized = false;

  // Mock discovered nodes for debug mode
  final List<Map<String, String>> _discoveredNodes = [
    {'id': 'watcher_node_alpha', 'ip': '192.168.1.105', 'transport': 'USB (Direct)'},
    {'id': 'watcher_node_beta', 'ip': '192.168.1.112', 'transport': 'Wi-Fi (UDP)'},
  ];

  int _screencapCount = 0;
  String _lastScreencapTime = 'Never';

  @override
  void initState() {
    super.initState();
    _activeMode = _envMode;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _logEvent('System initialized. OS: ${Theme.of(context).platform.name}');
      if (_envDebugLogs) {
        _logEvent('[DEBUG] Debug logging is active.');
      }
      if (_showDebugPanel) {
        _logEvent('[DEBUG] Debug panel enabled via config profile.');
        _startScreencapTimer();
      }
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _screencapTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _startScreencapTimer() {
    // Live screencap simulation once every 10 seconds
    _screencapTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      setState(() {
        _screencapCount++;
        _lastScreencapTime = DateTime.now().toIso8601String().split('T').last.substring(0, 8);
      });
      _logEvent('[Debug HAL] Live screencap captured successfully (#$_screencapCount). Frame size: 1.2 MB.');
    });
  }

  void _logEvent(String message) {
    setState(() {
      final timestamp = DateTime.now().toIso8601String().split('T').last.substring(0, 8);
      _logs.add('[$timestamp] $message');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toggleWatcher(String mode) {
    if (_isStreaming && _activeMode == mode) {
      _eventSubscription?.cancel();
      setState(() {
        _isStreaming = false;
        _activeMode = 'Standby';
      });
      _logEvent('Watcher stopped.');
    } else {
      _eventSubscription?.cancel();
      setState(() {
        _isStreaming = true;
        _activeMode = mode;
      });
      _logEvent('Watcher started in mode: $mode');
      _simulateWatcherEvents();
    }
  }

  void _simulateWatcherEvents() {
    _eventSubscription = Stream.periodic(const Duration(seconds: 2), (_) {}).listen((_) {
      if (!_isStreaming) return;

      if (_activeMode == 'Transmit') {
        _logEvent('[Network] USB bulk endpoint active. Transmitting video frame chunk...');
        _logEvent('[Display HAL] Captured frame from capture source successfully.');
      } else {
        _logEvent('[Network] Polling fallback Wi-Fi socket (UDP)... Packet received.');
        _logEvent('[Display HAL] Rendered incoming frame buffer to display surface.');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showDebugPanel ? 'AV Watcher Control Terminal [DEBUG MODE]' : 'AV Watcher Control Terminal'),
        backgroundColor: _showDebugPanel ? const Color(0xFF7C2D12) : const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Column: Main Dashboard Control & Terminal
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status Cards Header
                  Row(
                    children: [
                      _buildStatusCard('Operation Mode', _activeMode, Icons.settings_input_component),
                      const SizedBox(width: 12),
                      _buildStatusCard('Comm Channel', _commType, Icons.usb),
                      const SizedBox(width: 12),
                      _buildStatusCard('Status', _isStreaming ? 'ACTIVE' : 'IDLE', 
                        _isStreaming ? Icons.fiber_manual_record : Icons.pause_circle_outline,
                        color: _isStreaming ? Colors.greenAccent : Colors.orangeAccent),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _toggleWatcher('Transmit'),
                          icon: Icon(_isStreaming && _activeMode == 'Transmit' ? Icons.stop : Icons.upload),
                          label: Text(_isStreaming && _activeMode == 'Transmit' ? 'Stop Transmitting' : 'Start Transmitting'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isStreaming && _activeMode == 'Transmit' ? Colors.redAccent : Colors.blueAccent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _toggleWatcher('Receive'),
                          icon: Icon(_isStreaming && _activeMode == 'Receive' ? Icons.stop : Icons.download),
                          label: Text(_isStreaming && _activeMode == 'Receive' ? 'Stop Receiving' : 'Start Receiving'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isStreaming && _activeMode == 'Receive' ? Colors.redAccent : Colors.teal,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Terminal Console Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Event Stream Terminal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      TextButton.icon(
                        onPressed: () => setState(() => _logs.clear()),
                        icon: const Icon(Icons.clear_all, size: 16),
                        label: const Text('Clear Logs'),
                      )
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Terminal Console Box
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: ListView.builder(
                        controller: _scrollController,
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          final log = _logs[index];
                          Color textColor = Colors.white70;
                          if (log.contains('Network')) textColor = const Color(0xFF38BDF8);
                          if (log.contains('Display HAL')) textColor = const Color(0xFF4ADE80);
                          if (log.contains('System') || log.contains('Debug')) textColor = const Color(0xFFFACC15);

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: Text(
                              log,
                              style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: textColor),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Right Column: Conditional Debug Panel (Only shows if SHOW_DEBUG_PANEL is true)
            if (_showDebugPanel) ...[
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Debug Inspector Panel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.amberAccent)),
                    const SizedBox(height: 8),
                    
                    // Discovered Network Nodes Section
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.hub, size: 16, color: Colors.amberAccent),
                              SizedBox(width: 8),
                              Text('Available Nodes on Network', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                          const Divider(color: Colors.white24),
                          ..._discoveredNodes.map((node) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(node['id']!, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                                Text(node['ip']!, style: const TextStyle(fontSize: 12, color: Colors.white60)),
                              ],
                            ),
                          )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Live Screencap Preview Section (Updates every 10s)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.camera, size: 16, color: Colors.amberAccent),
                                    SizedBox(width: 8),
                                    Text('Live Screencap (10s interval)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  ],
                                ),
                                Text('#$_screencapCount', style: const TextStyle(color: Colors.amberAccent, fontSize: 12)),
                              ],
                            ),
                            const Divider(color: Colors.white24),
                            Expanded(
                              child: Center(
                                child: Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.monitor, size: 48, color: Colors.white24),
                                      const SizedBox(height: 8),
                                      Text(
                                        _screencapCount == 0 ? 'Waiting for first capture...' : 'Last Capture: $_lastScreencapTime',
                                        style: const TextStyle(fontSize: 11, color: Colors.white60),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(String title, String value, IconData icon, {Color color = Colors.white}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: Colors.white54),
                const SizedBox(width: 6),
                Text(title, style: const TextStyle(fontSize: 12, color: Colors.white54)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}