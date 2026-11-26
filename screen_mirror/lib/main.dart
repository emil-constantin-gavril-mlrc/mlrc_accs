import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'app_log.dart';
import 'debug_services.dart';
import 'screen_capture_service.dart';
import 'rust_transport.dart';

void main() {
  AppLog.init();
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
  bool _initialized = false;
  final ScreenCaptureService _screenCaptureService = ScreenCaptureService();
  late final LocalPeerDiscovery _peerDiscovery;
  RustTransport? _rustTransport;
  Timer? _receivePollTimer;
  Timer? _streamTimer;
  bool _queueFullLogged = false;
  String _transportLabel = 'Rust UDP';
  bool _isCapturing = false;
  bool _isDiscovering = false;
  int _lastLoggedSentBytes = 0;
  DateTime? _receiveStartedAt;
  bool _loggedReceiveTimeout = false;
  Uint8List? _screenshot;
  List<DiscoveredNode> _networkNodes = [];
  List<AdbDevice> _adbDevices = [];
  List<DiscoveredNode> _adbNodes = [];
  final TextEditingController _manualAddressController =
      TextEditingController();
  int _screencapCount = 0;
  String _lastScreencapTime = 'Never';
  String? _selectedPeerId;

  String get _commType => _isStreaming
      ? (_transportLabel == 'Rust UDP'
            ? 'Wi-Fi (Rust UDP)'
            : 'USB (ADB tunnel)')
      : 'Wi-Fi';

  @override
  void initState() {
    super.initState();
    _activeMode = _envMode;
    _peerDiscovery = LocalPeerDiscovery(
      onNodesChanged: (nodes) {
        if (!mounted) return;
        final knownIds = _networkNodes.map((node) => node.id).toSet();
        for (final node in nodes) {
          if (!knownIds.contains(node.id)) {
            _logEvent(
              '[Discovery] Peer "${node.id}" reachable at '
              '${node.address}:${node.port}'
              '${node.allAddresses.length > 1 ? ' (all IPv4: ${node.allAddresses.join(', ')})' : ''}.',
            );
          }
        }
        setState(() {
          _networkNodes = nodes;
          final selectedStillKnown =
              _selectedPeerId != null &&
              (nodes.any((node) => node.id == _selectedPeerId) ||
                  _adbNodes.any((node) => node.id == _selectedPeerId));
          if (!selectedStillKnown) {
            _selectedPeerId = nodes.isEmpty ? null : nodes.first.id;
          }
        });
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
    unawaited(_stopWatcher());
    unawaited(
      _peerDiscovery.stop().catchError((Object error) {
        AppLog.line('[Discovery] shutdown stop problem: $error');
      }),
    );
    _manualAddressController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _captureScreen({bool periodic = false}) async {
    setState(() => _isCapturing = true);
    if (!periodic) {
      _logEvent('[Capture] Capturing the next screen frame.');
    }
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
      if (!periodic || _screencapCount % 20 == 1) {
        _logEvent(
          '[Capture] Screen captured in memory (#$_screencapCount, ${image.length} bytes); temporary capture data was removed.',
        );
      }
      if (_isStreaming && _activeMode == 'Transmit') {
        try {
          _rustTransport!.sendFrame(image);
          _queueFullLogged = false;
          if (!periodic || _screencapCount % 20 == 1) {
            _logEvent(
              '[Network] Queued $_screencapCount frame over $_transportLabel.',
            );
          }
        } catch (error) {
          if (!_queueFullLogged) {
            _queueFullLogged = true;
            _logEvent(
              '[Network warning] Dropping frames: $error Captures keep '
              'running; queueing resumes automatically once the peer drains.',
            );
          }
        }
      }
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
      String? stopFailure;
      try {
        await _peerDiscovery.stop();
      } catch (error) {
        stopFailure = '$error';
      }
      if (!mounted) return;
      // The toggle must flip to "not discovering" even when teardown
      // reported problems: stop() always releases the resources it owns,
      // and a stuck-on toggle would block starting discovery again.
      setState(() {
        _isDiscovering = false;
        _networkNodes = [];
      });
      if (stopFailure == null) {
        _logEvent('[Discovery] Local peer discovery stopped.');
      } else {
        _logEvent(
          '[Discovery warning] Local peer discovery stopped with cleanup '
          'problems: $stopFailure',
        );
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
        '[USB] This app is running on the phone. For a direct USB session, '
        'keep the phone attached over ADB, run MLRC ACCS on the desktop '
        'with peer discovery on, then press "USB host (ADB tunnel)" to add '
        'the desktop as a peer.',
      );
      return;
    }

    try {
      final devices = await findAdbDevices();
      if (!mounted) return;
      setState(() => _adbDevices = devices);
      _logEvent('[USB] ADB reported ${devices.length} connected device(s).');
      final seeded = <DiscoveredNode>[];
      for (final device in devices) {
        if (device.status != 'device') {
          continue;
        }
        final failures = await setupAdbUsbTunnels(device.serial);
        if (failures.isEmpty) {
          seeded.add(
            DiscoveredNode(
              id: 'USB ${device.description}',
              address: '127.0.0.1',
              transport: 'USB (ADB tunnel)',
              port: LocalPeerDiscovery.usbTunnelPresencePort,
              allAddresses: const ['127.0.0.1'],
            ),
          );
          _logEvent(
            '[USB] Tunnelled "${device.description}" across the cable: '
            'frames travel through 127.0.0.1:${LocalPeerDiscovery.usbTunnelDataPort} '
            'and presence through 127.0.0.1:${LocalPeerDiscovery.usbTunnelPresencePort} '
            '(adb forward/reverse applied). Select it and press Start for '
            'a direct USB session.',
          );
        } else {
          _logEvent(
            '[USB] ADB tunnel setup failed for "${device.description}": '
            '${failures.join('; ')} The direct USB session will not work '
            'until the tunnel rules apply (is USB debugging authorized?).',
          );
        }
        final address = await findAdbWlan4Address(device.serial);
        if (address != null) {
          seeded.add(
            DiscoveredNode(
              id: 'ADB Wi-Fi ${device.description}',
              address: address,
              transport: 'ADB-seeded (Wi-Fi path)',
              port: LocalPeerDiscovery.fixedPresencePort,
              allAddresses: [address],
            ),
          );
        }
      }
      if (mounted) {
        setState(() => _adbNodes = seeded);
      }
    } catch (error) {
      if (mounted) {
        _logEvent('[USB discovery error] $error');
      }
    }
  }

  void _logEvent(String message) {
    AppLog.line(message);
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

  /// mDNS, ADB-seeded, and manually added peers share one picker; peers with
  /// the same IPv4 are only listed once (the mDNS entry wins).
  List<DiscoveredNode> _peerPickerItems() {
    final seenAddresses = <String>{};
    return [..._networkNodes, ..._adbNodes].where((node) {
      if (node.address == 'IPv4 address unavailable') {
        return true;
      }
      return seenAddresses.add(node.address);
    }).toList();
  }

  void _addManualPeer() {
    final raw = _manualAddressController.text.trim();
    if (raw.isEmpty) {
      _logEvent('[Manual] Type the peer\u2019s IPv4 address, then press Add.');
      return;
    }
    try {
      final node = _peerDiscovery.addManualNode(raw);
      _manualAddressController.clear();
      setState(() => _selectedPeerId = node.id);
      _logEvent(
        '[Manual] Added "${node.id}" at ${node.address}:${node.port} and '
        'selected it. Press Start Transmitting or Start Receiving to '
        'connect now, without waiting for discovery.',
      );
    } catch (error) {
      _logEvent('[Manual error] $error');
    }
  }

  void _addUsbHostPeer() {
    try {
      final node = _peerDiscovery.addUsbTunnelNode();
      setState(() => _selectedPeerId = node.id);
      _logEvent(
        '[USB] Added "${node.id}" at 127.0.0.1:${node.port}. The phone '
        'reaches the desktop through adb reverse, which the desktop app '
        'applies while its peer discovery runs with this phone attached. '
        'Press Start Transmitting or Start Receiving to connect.',
      );
    } catch (error) {
      _logEvent('[USB error] $error');
    }
  }

  Future<void> _toggleWatcher(String mode) async {
    if (_isStreaming && _activeMode == mode) {
      await _stopWatcher();
      return;
    }
    if (_isStreaming) {
      await _stopWatcher();
    }

    if (!_isDiscovering) {
      await _toggleDeviceDiscovery();
      if (_isDiscovering) {
        _logEvent(
          '[Network] Discovery started. Select the other device, then start again.',
        );
      }
      return;
    }

    DiscoveredNode? peer;
    for (final node in [..._networkNodes, ..._adbNodes]) {
      if (node.id == _selectedPeerId) {
        peer = node;
        break;
      }
    }
    if (peer == null) {
      _logEvent('[Network error] Select a discovered peer before connecting.');
      return;
    }
    if (peer.address == 'IPv4 address unavailable') {
      _logEvent(
        '[Network error] The selected peer did not advertise an IPv4 address.',
      );
      return;
    }
    final viaUsbTunnel = peer.transport == 'USB (ADB tunnel)';
    int localPresencePort;
    try {
      localPresencePort = _peerDiscovery.port;
    } on StateError {
      _logEvent(
        '[Network error] Local peer discovery is not running any more. '
        'Toggle Peer Discovery on, then press Start again.',
      );
      return;
    }

    final candidateText = peer.allAddresses.isEmpty
        ? peer.address
        : peer.allAddresses.join(', ');
    _logEvent(
      '[Network] Presence handshake for "${peer.id}" '
      '(candidates: $candidateText, port ${peer.port})...',
    );
    String reachableAddress;
    try {
      reachableAddress = await verifyPeerReachability(peer);
    } catch (error) {
      if (viaUsbTunnel) {
        _logEvent(
          '[Network error] The USB tunnel probe for "${peer.id}" failed: '
          '$error Keep the cable attached and the phone unlocked, make sure '
          'the peer app is running with discovery on, and (on the desktop '
          'side) toggle peer discovery once more so the adb tunnel rules '
          'are reapplied for this device.',
        );
      } else {
        _logEvent(
          '[Network error] Cannot reach "${peer.id}" on port ${peer.port}. '
          '$error Verify the peer is running MLRC ACCS with discovery on, '
          'both devices share one Wi-Fi network, and the Windows firewall '
          'allows inbound UDP and TCP on port ${peer.port} (the Wi-Fi '
          'network profile should be Private).',
        );
      }
      return;
    }
    if (reachableAddress != peer.address) {
      _logEvent(
        '[Network] Preferred ${peer.address} did not answer; the presence '
        'handshake succeeded on $reachableAddress instead. Using it.',
      );
      peer = DiscoveredNode(
        id: peer.id,
        address: reachableAddress,
        transport: peer.transport,
        port: peer.port,
        status: peer.status,
        allAddresses: peer.allAddresses,
      );
    }
    _logEvent(
      '[Network] Reachability to $reachableAddress:${peer.port} confirmed.',
    );

    try {
      if (mode == 'Transmit') {
        _logEvent(
          '[Capture] Starting capture for this session. On Android, approve '
          'the system prompt once; subsequent frames reuse that permission.',
        );
        await _screenCaptureService.startContinuousCapture();
      }
      final transport = RustTransport();
      _transportLabel = viaUsbTunnel ? 'Rust USB tunnel' : 'Rust UDP';
      final localDataPort = viaUsbTunnel
          ? LocalPeerDiscovery.usbTunnelDataPort
          : localPresencePort;
      final peerDataAddress = viaUsbTunnel ? '127.0.0.1' : peer.address;
      final int peerDataPort;
      if (!viaUsbTunnel) {
        peerDataPort = peer.port;
      } else if (mode == 'Receive') {
        peerDataPort = LocalPeerDiscovery.usbTunnelDataPort;
      } else if (Platform.isAndroid) {
        peerDataPort = LocalPeerDiscovery.usbTunnelPhoneConnectPort;
      } else {
        peerDataPort = LocalPeerDiscovery.usbTunnelHostConnectPort;
      }
      transport.start(
        transmitting: mode == 'Transmit',
        localPort: localDataPort,
        peerAddress: peerDataAddress,
        peerPort: peerDataPort,
        tunnel: viaUsbTunnel,
      );
      _logEvent(
        '[Transport] ${mode == 'Transmit' ? 'Transmitter' : 'Receiver'} '
        'session active: '
        '${viaUsbTunnel ? 'USB (ADB tunnel) 127.0.0.1:$localDataPort' : 'UDP $localDataPort'} '
        '<-> $peerDataAddress:$peerDataPort.',
      );
      setState(() {
        _rustTransport = transport;
        _isStreaming = true;
        _activeMode = mode;
      });
      _lastLoggedSentBytes = 0;
      _receiveStartedAt = mode == 'Receive' ? DateTime.now() : null;
      _loggedReceiveTimeout = false;
      _queueFullLogged = false;
      _logEvent(
        '[Network] $_transportLabel $mode session started; local port '
        '$localDataPort, peer $peerDataAddress:$peerDataPort.',
      );
      if (mode == 'Receive') {
        _logEvent(
          '[Network] Listening for $_transportLabel frames from '
          '$peerDataAddress:$peerDataPort.',
        );
      }
      _receivePollTimer = Timer.periodic(
        const Duration(milliseconds: 40),
        (_) => _pollTransport(transport, mode, peer!),
      );

      if (mode == 'Transmit') {
        unawaited(_captureScreen());
        _streamTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
          if (_isStreaming && _activeMode == 'Transmit' && !_isCapturing) {
            unawaited(_captureScreen(periodic: true));
          }
        });
        _logEvent(
          '[Capture] Continuous capture armed: the next frame is captured '
          'as soon as the previous capture finishes (the desktop targets '
          'about 4 frames per second; Android is limited by screencap '
          'speed).',
        );
      }
    } catch (error) {
      if (mounted) {
        await _stopWatcher();
        _logEvent('[Network error] Could not start $mode: $error');
      }
    }
  }

  Future<void> _stopWatcher() async {
    _receivePollTimer?.cancel();
    _receivePollTimer = null;
    _streamTimer?.cancel();
    _streamTimer = null;
    _queueFullLogged = false;
    _rustTransport?.stop();
    _rustTransport = null;
    try {
      await _screenCaptureService.stopContinuousCapture();
    } catch (error) {
      AppLog.line('[Capture] Could not stop Android screen capture: $error');
    }
    _receiveStartedAt = null;
    _loggedReceiveTimeout = false;
    _lastLoggedSentBytes = 0;
    if (!mounted) return;
    setState(() {
      _isStreaming = false;
      _activeMode = 'Standby';
    });
    _logEvent('Watcher stopped.');
  }

  void _pollTransport(
    RustTransport transport,
    String mode,
    DiscoveredNode peer,
  ) {
    try {
      final frame = transport.pollFrame();
      if (frame != null) {
        if (!mounted) return;
        setState(() {
          _screenshot = frame;
          _screencapCount++;
          _lastScreencapTime = DateTime.now().toLocal().toString().substring(
            11,
            19,
          );
        });
        _receiveStartedAt = DateTime.now();
        _loggedReceiveTimeout = false;
        _logEvent(
          '[Network] Received frame (${frame.length} bytes) over $_transportLabel.',
        );
      }
      if (mode == 'Transmit') {
        final acknowledgedBytes = transport.acknowledgedBytes;
        if (acknowledgedBytes > _lastLoggedSentBytes) {
          final delta = acknowledgedBytes - _lastLoggedSentBytes;
          _lastLoggedSentBytes = acknowledgedBytes;
          _logEvent(
            '[Network] Peer acknowledged receipt of $delta frame bytes from '
            '${peer.address}:${peer.port}.',
          );
        }
      } else {
        final startedAt = _receiveStartedAt;
        if (!_loggedReceiveTimeout &&
            startedAt != null &&
            DateTime.now().difference(startedAt) >=
                const Duration(seconds: 10)) {
          _loggedReceiveTimeout = true;
          _logEvent(
            '[Network warning] No $_transportLabel frame received in 10 seconds. Check that the peer is transmitting to this device’s advertised address and that the link (Wi-Fi/firewall, or the USB tunnel) is up.',
          );
        }
      }
    } catch (error) {
      unawaited(_stopWatcher());
      _logEvent(
        '[Network error] $_transportLabel $mode session failed: $error',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _showDebugPanel
              ? 'AV Watcher Control Terminal [DEBUG MODE]'
              : 'AV Watcher Control Terminal',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
            if (compact) {
              return _buildCompactDashboard(isAndroid: isAndroid);
            }
            return Flex(
              direction: Axis.horizontal,
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
                          Expanded(
                            child: _buildStatusCard(
                              'Operation Mode',
                              _activeMode,
                              Icons.settings_input_component,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatusCard(
                              'Comm Channel',
                              _commType,
                              Icons.wifi,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatusCard(
                              'Status',
                              _isStreaming ? 'ACTIVE' : 'IDLE',
                              _isStreaming
                                  ? Icons.fiber_manual_record
                                  : Icons.pause_circle_outline,
                              color: _isStreaming
                                  ? Colors.greenAccent
                                  : Colors.orangeAccent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Wi-Fi peer',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _isStreaming
                                ? null
                                : _toggleDeviceDiscovery,
                            icon: Icon(
                              _isDiscovering ? Icons.stop : Icons.search,
                              size: 16,
                            ),
                            label: Text(
                              _isDiscovering ? 'Stop discovery' : 'Discover',
                            ),
                          ),
                        ],
                      ),
                      if (_networkNodes.isEmpty && _adbNodes.isEmpty)
                        const Text(
                          'Start discovery on both devices, then select the peer here.',
                          style: TextStyle(color: Colors.white60, fontSize: 12),
                        )
                      else
                        DropdownButtonFormField<String>(
                          key: ValueKey(_selectedPeerId),
                          initialValue: _selectedPeerId,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          hint: const Text('Select a discovered peer'),
                          items: _peerPickerItems()
                              .map(
                                (node) => DropdownMenuItem(
                                  value: node.id,
                                  child: Text(
                                    '${node.id} (${node.address}:${node.port})',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: _isStreaming
                              ? null
                              : (peerId) =>
                                    setState(() => _selectedPeerId = peerId),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _manualAddressController,
                              enabled: !_isStreaming,
                              onFieldSubmitted: (_) => _addManualPeer(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                                hintText: 'Or connect manually: peer IPv4',
                                hintStyle: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonalIcon(
                            onPressed: _isStreaming ? null : _addManualPeer,
                            icon: const Icon(Icons.add_link, size: 16),
                            label: const Text('Add'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (isAndroid) ...[
                        OutlinedButton.icon(
                          onPressed: _isStreaming ? null : _addUsbHostPeer,
                          icon: const Icon(Icons.usb, size: 16),
                          label: const Text('USB host (ADB tunnel)'),
                        ),
                        const SizedBox(height: 8),
                      ],
                      const Text(
                        'Transmitting captures continuously while the session is active; peer discovery also arms the USB (ADB tunnel) link for attached phones.',
                        style: TextStyle(color: Colors.white60, fontSize: 11),
                      ),
                      const SizedBox(height: 12),

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

                      if (_screenshot != null) ...[
                        Text(
                          'Last frame (#$_screencapCount, $_lastScreencapTime)',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: compact ? 100 : 150,
                          child: Center(
                            child: Image.memory(
                              _screenshot!,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

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

  Widget _buildCompactDashboard({required bool isAndroid}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.maxWidth.isFinite || constraints.maxWidth <= 8) {
          return const SizedBox.shrink();
        }
        final cardWidth = (constraints.maxWidth - 8) / 2;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: _buildStatusCard(
                      'Operation Mode',
                      _activeMode,
                      Icons.settings_input_component,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _buildStatusCard(
                      'Comm Channel',
                      _commType,
                      Icons.wifi,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _buildStatusCard(
                      'Status',
                      _isStreaming ? 'ACTIVE' : 'IDLE',
                      _isStreaming
                          ? Icons.fiber_manual_record
                          : Icons.pause_circle_outline,
                      color: _isStreaming
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Wi-Fi peer',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _isStreaming ? null : _toggleDeviceDiscovery,
                    icon: Icon(
                      _isDiscovering ? Icons.stop : Icons.search,
                      size: 16,
                    ),
                    label: Text(_isDiscovering ? 'Stop' : 'Discover'),
                  ),
                ],
              ),
              if (_networkNodes.isEmpty && _adbNodes.isEmpty)
                const Text(
                  'Start discovery on both devices, then select the peer here.',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                )
              else
                DropdownButtonFormField<String>(
                  key: ValueKey(_selectedPeerId),
                  initialValue: _selectedPeerId,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  hint: const Text('Select a discovered peer'),
                  items: _peerPickerItems()
                      .map(
                        (node) => DropdownMenuItem(
                          value: node.id,
                          child: Text(
                            '${node.id} (${node.address}:${node.port})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _isStreaming
                      ? null
                      : (peerId) => setState(() => _selectedPeerId = peerId),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _manualAddressController,
                      enabled: !_isStreaming,
                      onFieldSubmitted: (_) => _addManualPeer(),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        hintText: 'Manual peer IPv4',
                        hintStyle: TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _isStreaming ? null : _addManualPeer,
                    icon: const Icon(Icons.add_link, size: 16),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (isAndroid) ...[
                OutlinedButton.icon(
                  onPressed: _isStreaming ? null : _addUsbHostPeer,
                  icon: const Icon(Icons.usb, size: 16),
                  label: const Text('USB host (ADB tunnel)'),
                ),
                const SizedBox(height: 4),
              ],
              const Text(
                'Transmitting captures continuously while a session is active.',
                style: TextStyle(color: Colors.white60, fontSize: 11),
              ),
              const SizedBox(height: 10),
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
                        maxLines: 2,
                        textAlign: TextAlign.center,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _isStreaming && _activeMode == 'Transmit'
                            ? Colors.redAccent
                            : Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 8,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
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
                        maxLines: 2,
                        textAlign: TextAlign.center,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _isStreaming && _activeMode == 'Receive'
                            ? Colors.redAccent
                            : Colors.teal,
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 8,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildCompactEventLog(),
              if (_showDebugPanel) ...[
                const SizedBox(height: 16),
                _buildCompactInspector(isAndroid: isAndroid),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompactEventLog() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Event Stream Terminal',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            TextButton.icon(
              onPressed: () => setState(() => _logs.clear()),
              icon: const Icon(Icons.clear_all, size: 16),
              label: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(height: 280, child: _buildLogList()),
      ],
    );
  }

  Widget _buildLogList() {
    return Container(
      padding: const EdgeInsets.all(10),
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
          final textColor = log.contains('Network')
              ? const Color(0xFF38BDF8)
              : log.contains('Display HAL')
              ? const Color(0xFF4ADE80)
              : log.contains('System') || log.contains('Debug')
              ? const Color(0xFFFACC15)
              : Colors.white70;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              log,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: textColor,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCompactInspector({required bool isAndroid}) {
    return Column(
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
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Available MLRC peers',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              if (_networkNodes.isEmpty && _adbDevices.isEmpty)
                Text(
                  _isDiscovering
                      ? isAndroid
                            ? 'Searching for peers...'
                            : 'Searching for peers and USB devices...'
                      : 'Discovery has not been started.',
                  style: const TextStyle(fontSize: 12, color: Colors.white60),
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
        const SizedBox(height: 12),
        Container(
          height: 260,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Current screen preview',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _isCapturing ? null : _captureScreen,
                    icon: const Icon(Icons.camera_alt, size: 16),
                    label: Text(_isCapturing ? 'Capturing' : 'Capture'),
                  ),
                ],
              ),
              const Divider(color: Colors.white24),
              Expanded(
                child: Center(
                  child: _screenshot == null
                      ? const Text(
                          'Capture starts only when requested.\nPreview stays in memory.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: Colors.white60),
                        )
                      : Image.memory(_screenshot!, fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _screencapCount == 0
                    ? 'Last capture: Never'
                    : 'Capture #$_screencapCount at $_lastScreencapTime',
                style: const TextStyle(fontSize: 11, color: Colors.white60),
              ),
            ],
          ),
        ),
      ],
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
    return Container(
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
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
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
    );
  }
}
