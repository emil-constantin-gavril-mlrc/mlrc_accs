import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'debug_services.dart';
import 'screen_capture_service.dart';

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
  static const String _envMode = String.fromEnvironment(
    'OPERATION_MODE',
    defaultValue: 'Standby',
  );
  static const bool _envDebugLogs = bool.fromEnvironment(
    'ENABLE_DEBUG_LOGS',
    defaultValue: false,
  );
  static const bool _showDebugPanel = bool.fromEnvironment(
    'SHOW_DEBUG_PANEL',
    defaultValue: false,
  );

  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();

  bool _isStreaming = false;
  late String _activeMode;
  final String _commType = 'Auto (USB preferred)';

  StreamSubscription? _eventSubscription;
  bool _initialized = false;
  final ScreenCaptureService _screenCaptureService = ScreenCaptureService();
  late final LocalPeerDiscovery _peerDiscovery;
  bool _isCapturing = false;
  bool _isDiscovering = false;
  Uint8List? _screenshot;
  List<DiscoveredNode> _networkNodes = [];
  List<AdbDevice> _adbDevices = [];
  int _screencapCount = 0;
  String _lastScreencapTime = 'Never';

  @override
  void initState() {
    super.initState();
    _activeMode = _envMode;
    _peerDiscovery = LocalPeerDiscovery(
      onNodesChanged: (nodes) {
        if (mounted) {
          setState(() => _networkNodes = nodes);
        }
      },
      onError: (error) {
        if (mounted) _logEvent('[Discovery error] $error');
      },
    );
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
        _logEvent(
          '[DEBUG] Screen capture and peer discovery require explicit user action.',
        );
      }
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    unawaited(_peerDiscovery.stop());
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _captureScreen() async {
    setState(() => _isCapturing = true);
    _logEvent(
      '[Capture] Screen capture requested. Approve the system prompt if shown.',
    );
    try {
      final image = await _screenCaptureService.captureCurrentScreen();
      if (!mounted) return;
      setState(() {
        _screenshot = image;
        _screencapCount++;
        _lastScreencapTime = DateTime.now().toLocal().toString().substring(
          11,
          19,
        );
      });
      _logEvent(
        '[Capture] Screen captured in memory (#$_screencapCount); temporary capture data was removed.',
      );
    } catch (error) {
      if (mounted) {
        _logEvent('[Capture error] $error');
      }
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  Future<void> _toggleDeviceDiscovery() async {
    if (_isDiscovering) {
      try {
        await _peerDiscovery.stop();
        if (!mounted) return;
        setState(() {
          _isDiscovering = false;
          _networkNodes = [];
        });
        _logEvent('[Discovery] Local peer discovery stopped.');
      } catch (error) {
        if (mounted) _logEvent('[Discovery error] $error');
      }
      return;
    }

    setState(() => _isDiscovering = true);
    _logEvent(
      '[Discovery] Starting opted-in MLRC peer discovery on the local network.',
    );
    try {
      await _peerDiscovery.start();
      if (mounted) {
        _logEvent('[Discovery] Local service discovery is active.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _isDiscovering = false);
        _logEvent('[Discovery error] $error');
      }
    }

    if (!mounted) return;
    if (Theme.of(context).platform == TargetPlatform.android) {
      _logEvent(
        '[USB] ADB discovery is available when the app runs on a Windows or Linux host.',
      );
      return;
    }

    try {
      final devices = await findAdbDevices();
      if (!mounted) return;
      setState(() => _adbDevices = devices);
      _logEvent('[USB] ADB reported ${devices.length} connected device(s).');
    } catch (error) {
      if (mounted) {
        _logEvent('[USB discovery error] $error');
      }
    }
  }

  void _logEvent(String message) {
    setState(() {
      final timestamp = DateTime.now()
          .toIso8601String()
          .split('T')
          .last
          .substring(0, 8);
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
    _eventSubscription = Stream.periodic(const Duration(seconds: 2), (_) {})
        .listen((_) {
          if (!_isStreaming) return;

          if (_activeMode == 'Transmit') {
            _logEvent(
              '[Network] USB bulk endpoint active. Transmitting video frame chunk...',
            );
            _logEvent(
              '[Display HAL] Captured frame from capture source successfully.',
            );
          } else {
            _logEvent(
              '[Network] Polling fallback Wi-Fi socket (UDP)... Packet received.',
            );
            _logEvent(
              '[Display HAL] Rendered incoming frame buffer to display surface.',
            );
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _showDebugPanel
              ? 'AV Watcher Control Terminal [DEBUG MODE]'
              : 'AV Watcher Control Terminal',
        ),
        backgroundColor: _showDebugPanel
            ? const Color(0xFF7C2D12)
            : const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 900;
            final isAndroid =
                Theme.of(context).platform == TargetPlatform.android;
            return Flex(
              direction: compact ? Axis.vertical : Axis.horizontal,
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
                          _buildStatusCard(
                            'Operation Mode',
                            _activeMode,
                            Icons.settings_input_component,
                          ),
                          const SizedBox(width: 12),
                          _buildStatusCard(
                            'Comm Channel',
                            _commType,
                            Icons.usb,
                          ),
                          const SizedBox(width: 12),
                          _buildStatusCard(
                            'Status',
                            _isStreaming ? 'ACTIVE' : 'IDLE',
                            _isStreaming
                                ? Icons.fiber_manual_record
                                : Icons.pause_circle_outline,
                            color: _isStreaming
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _toggleWatcher('Transmit'),
                              icon: Icon(
                                _isStreaming && _activeMode == 'Transmit'
                                    ? Icons.stop
                                    : Icons.upload,
                              ),
                              label: Text(
                                _isStreaming && _activeMode == 'Transmit'
                                    ? 'Stop Transmitting'
                                    : 'Start Transmitting',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    _isStreaming && _activeMode == 'Transmit'
                                    ? Colors.redAccent
                                    : Colors.blueAccent,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _toggleWatcher('Receive'),
                              icon: Icon(
                                _isStreaming && _activeMode == 'Receive'
                                    ? Icons.stop
                                    : Icons.download,
                              ),
                              label: Text(
                                _isStreaming && _activeMode == 'Receive'
                                    ? 'Stop Receiving'
                                    : 'Start Receiving',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    _isStreaming && _activeMode == 'Receive'
                                    ? Colors.redAccent
                                    : Colors.teal,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
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
                          const Text(
                            'Event Stream Terminal',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => setState(() => _logs.clear()),
                            icon: const Icon(Icons.clear_all, size: 16),
                            label: const Text('Clear Logs'),
                          ),
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
                              if (log.contains('Network')) {
                                textColor = const Color(0xFF38BDF8);
                              }
                              if (log.contains('Display HAL')) {
                                textColor = const Color(0xFF4ADE80);
                              }
                              if (log.contains('System') ||
                                  log.contains('Debug')) {
                                textColor = const Color(0xFFFACC15);
                              }

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2.0,
                                ),
                                child: Text(
                                  log,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 13,
                                    color: textColor,
                                  ),
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
                  SizedBox(width: compact ? 0 : 16, height: compact ? 16 : 0),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Debug Inspector Panel',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.amberAccent,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Network discovery panel
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.amber.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Available MLRC peers',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: _toggleDeviceDiscovery,
                                    icon: Icon(
                                      _isDiscovering
                                          ? Icons.stop
                                          : Icons.search,
                                      size: 16,
                                    ),
                                    label: Text(
                                      _isDiscovering ? 'Stop' : 'Discover',
                                    ),
                                  ),
                                ],
                              ),
                              const Text(
                                'Discovers opted-in MLRC apps on this LAN; desktop hosts also list USB-connected Android devices with ADB.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white60,
                                ),
                              ),
                              const Divider(color: Colors.white24),
                              if (_networkNodes.isEmpty && _adbDevices.isEmpty)
                                Text(
                                  _isDiscovering
                                      ? isAndroid
                                            ? 'Searching for peers...'
                                            : 'Searching for peers and USB devices...'
                                      : 'Discovery has not been started.',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white60,
                                  ),
                                ),
                              ..._networkNodes.map(
                                (node) => _buildNodeRow(
                                  Icons.wifi,
                                  node.id,
                                  '${node.address}:${node.port}',
                                ),
                              ),
                              ..._adbDevices.map(
                                (device) => _buildNodeRow(
                                  Icons.usb,
                                  device.description,
                                  '${device.serial} (${device.status})',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // User-triggered screen capture preview
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.amber.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Current screen preview',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: _isCapturing
                                          ? null
                                          : _captureScreen,
                                      icon: _isCapturing
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.camera_alt,
                                              size: 16,
                                            ),
                                      label: Text(
                                        _isCapturing ? 'Capturing' : 'Capture',
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(color: Colors.white24),
                                Expanded(
                                  child: Center(
                                    child: Container(
                                      width: double.infinity,
                                      height: double.infinity,
                                      decoration: BoxDecoration(
                                        color: Colors.black,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: Colors.white10,
                                        ),
                                      ),
                                      child: _screenshot == null
                                          ? const Center(
                                              child: Text(
                                                'Capture starts only when requested.\nPreview stays in memory.',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.white60,
                                                ),
                                              ),
                                            )
                                          : ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              child: Image.memory(
                                                _screenshot!,
                                                fit: BoxFit.contain,
                                                errorBuilder:
                                                    (
                                                      context,
                                                      error,
                                                      stackTrace,
                                                    ) => const Center(
                                                      child: Text(
                                                        'Could not display captured image.',
                                                      ),
                                                    ),
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _screencapCount == 0
                                      ? 'Last capture: Never'
                                      : 'Capture #$_screencapCount at $_lastScreencapTime',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white60,
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
            );
          },
        ),
      ),
    );
  }

  Widget _buildNodeRow(IconData icon, String name, String details) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.amberAccent),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  details,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white60),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(
    String title,
    String value,
    IconData icon, {
    Color color = Colors.white,
  }) {
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
                Text(
                  title,
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
