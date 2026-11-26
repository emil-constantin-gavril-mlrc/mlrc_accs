import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';

class DiscoveredNode {
  const DiscoveredNode({
    required this.id,
    required this.address,
    required this.transport,
    required this.port,
    this.status = 'available',
    this.allAddresses = const [],
  });

  final String id;
  final String address;
  final String transport;
  final int port;
  final String status;
  final List<String> allAddresses;
}

/// Preference score for IPv4 addresses advertised via mDNS (lower is better).
/// Peers can advertise several addresses; virtual adapters (WSL, Docker,
/// Hyper-V) and APIPA link-local addresses must lose to the real LAN address.
int _ipv4Preference(String address) {
  if (address.startsWith('169.254.')) {
    return 4;
  }
  if (address.startsWith('192.168.')) {
    return 0;
  }
  if (address.startsWith('10.')) {
    return 1;
  }
  if (RegExp(r'^172\.(1[6-9]|2[0-9]|3[01])\.').hasMatch(address)) {
    return 3;
  }
  return 2;
}

/// Opens a short-lived TCP handshake to the peer's presence endpoint so a
/// wrong/unreachable advertised address fails fast with an actionable log
/// line instead of silently sending UDP frames into a black hole.
///
/// A peer can advertise several IPv4 addresses at once (a stale disconnected
/// adapter, a virtual NIC, plus the live Wi-Fi adapter). Candidates are probed
/// in advertised preference order and the first address that completes the
/// handshake is returned; the caller must use that address for the transport
/// session. Throws [SocketException] naming every failed candidate otherwise.
Future<String> verifyPeerReachability(
  DiscoveredNode peer, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final candidates = <String>[
    if (peer.allAddresses.isNotEmpty) ...peer.allAddresses else peer.address,
  ];
  final failures = <String>[];
  for (final candidate in candidates) {
    try {
      final socket = await Socket.connect(
        candidate,
        peer.port,
        timeout: timeout,
      );
      socket.destroy();
      return candidate;
    } catch (error) {
      failures.add('$candidate -> ${_reachabilityErrorText(error)}');
    }
  }
  throw SocketException(
    'No advertised address completed the presence handshake on port '
    '${peer.port}: ${failures.join('; ')}',
  );
}

String _reachabilityErrorText(Object error) {
  if (error is TimeoutException) {
    return 'timed out (firewall drop, or this machine is on a different network)';
  }
  if (error is SocketException) {
    final osError = error.osError;
    if (osError != null) {
      return 'errno ${osError.errorCode} (${osError.message})';
    }
    return 'unreachable';
  }
  return error.toString();
}

class AdbDevice {
  const AdbDevice({
    required this.serial,
    required this.status,
    required this.description,
  });

  final String serial;
  final String status;
  final String description;
}

List<AdbDevice> parseAdbDevices(String output) {
  final devices = <AdbDevice>[];
  final lines = const LineSplitter().convert(output);
  final headerIndex = lines.indexWhere(
    (line) => line.contains('List of devices attached'),
  );
  if (headerIndex == -1) {
    throw const FormatException('ADB returned an unrecognized device list.');
  }

  for (final line in lines.skip(headerIndex + 1)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('*')) {
      continue;
    }

    final fields = trimmed.split(RegExp(r'\s+'));
    if (fields.length < 2) {
      continue;
    }

    final serial = fields.first;
    final status = fields[1];
    String? modelField;
    for (final field in fields) {
      if (field.startsWith('model:')) {
        modelField = field;
        break;
      }
    }
    final model = modelField?.substring('model:'.length).replaceAll('_', ' ');
    devices.add(
      AdbDevice(
        serial: serial,
        status: status,
        description: model == null || model.isEmpty ? serial : model,
      ),
    );
  }
  return devices;
}

Future<String> _resolveAdbExecutable() async {
  final executableName = Platform.isWindows ? 'adb.exe' : 'adb';
  final environment = Platform.environment;
  final sdkRoots = <String?>[
    environment['ANDROID_SDK_ROOT'],
    environment['ANDROID_HOME'],
    if (Platform.isWindows && environment['LOCALAPPDATA'] != null)
      '${environment['LOCALAPPDATA']}${Platform.pathSeparator}Android${Platform.pathSeparator}Sdk',
    if (!Platform.isWindows && environment['HOME'] != null)
      '${environment['HOME']}${Platform.pathSeparator}Android${Platform.pathSeparator}Sdk',
  ];
  String? adbPath;
  for (final sdkRoot in sdkRoots) {
    if (sdkRoot == null || sdkRoot.isEmpty) continue;
    final candidate =
        '$sdkRoot${Platform.pathSeparator}platform-tools${Platform.pathSeparator}$executableName';
    if (await File(candidate).exists()) {
      adbPath = candidate;
      break;
    }
  }

  return adbPath ?? 'adb';
}

Future<List<AdbDevice>> findAdbDevices() async {
  if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
    throw UnsupportedError(
      'ADB USB discovery is supported on desktop hosts only.',
    );
  }

  final executable = await _resolveAdbExecutable();
  ProcessResult result;
  try {
    result = await Process.run(executable, const ['devices', '-l']);
  } on ProcessException catch (error) {
    throw StateError(
      'ADB was not found. Install Android SDK Platform-Tools or add adb to PATH. ${error.message}',
    );
  }
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      const ['devices', '-l'],
      result.stderr.toString().trim(),
      result.exitCode,
    );
  }
  return parseAdbDevices(result.stdout.toString());
}

/// Asks an ADB-connected device for its Wi-Fi IPv4 address. The direct USB
/// transport is not implemented yet, but this seeds the peer picker with the
/// device's real LAN address so an ADB-discovered phone is still connectable
/// today over the Wi-Fi path without waiting for mDNS.
Future<String?> findAdbWlan4Address(String serial) async {
  final executable = await _resolveAdbExecutable();
  for (final interface in const ['wlan0', 'wlan1']) {
    ProcessResult result;
    try {
      result = await Process.run(executable, [
        '-s',
        serial,
        'shell',
        'ip',
        '-f',
        'inet',
        'addr',
        'show',
        interface,
      ]);
    } on ProcessException {
      return null;
    }
    if (result.exitCode != 0) {
      continue;
    }
    final match = RegExp(r'inet\s+(\d+\.\d+\.\d+\.\d+)/')
        .firstMatch(result.stdout.toString());
    final address = match?.group(1);
    if (address != null && address != '127.0.0.1') {
      return address;
    }
  }
  return null;
}

/// (Re)applies the TCP tunnel rules that carry MLRC ACCS traffic across the
/// USB cable for one ADB device. The device-side reverse-connect port is
/// distinct from the device's receive/listen port because `adb reverse`
/// occupies its local endpoint. The rules are idempotent; an empty list means
/// all rules were applied successfully.
Future<List<String>> setupAdbUsbTunnels(String serial) async {
  final executable = await _resolveAdbExecutable();
  final data = LocalPeerDiscovery.usbTunnelDataPort;
  final phoneConnect = LocalPeerDiscovery.usbTunnelPhoneConnectPort;
  final hostConnect = LocalPeerDiscovery.usbTunnelHostConnectPort;
  final presence = LocalPeerDiscovery.usbTunnelPresencePort;
  final realPresence = LocalPeerDiscovery.fixedPresencePort;
  final failures = <String>[];
  for (final direction in ['forward', 'reverse']) {
    try {
      final result = await Process.run(executable, [
        '-s',
        serial,
        direction,
        '--remove',
        'tcp:$data',
      ]);
      final message = result.stderr.toString().trim();
      if (result.exitCode != 0 &&
          !message.toLowerCase().contains('not found')) {
        failures.add(
          'adb $direction --remove tcp:$data: '
          '${message.isEmpty ? 'exit code ${result.exitCode}' : message}',
        );
      }
    } on ProcessException catch (error) {
      failures.add('adb $direction --remove tcp:$data: ${error.message}');
    }
  }
  final rules = <List<String>>[
    ['forward', 'tcp:$hostConnect', 'tcp:$data'],
    ['forward', 'tcp:$presence', 'tcp:$realPresence'],
    ['reverse', 'tcp:$phoneConnect', 'tcp:$data'],
    ['reverse', 'tcp:$presence', 'tcp:$realPresence'],
  ];
  for (final rule in rules) {
    try {
      final result = await Process.run(executable, ['-s', serial, ...rule]);
      if (result.exitCode != 0) {
        final message = result.stderr.toString().trim();
        failures.add(
          'adb ${rule.join(' ')}: '
          '${message.isEmpty ? 'exit code ${result.exitCode}' : message}',
        );
      }
    } on ProcessException catch (error) {
      failures.add('adb ${rule.join(' ')}: ${error.message}');
    }
  }
  return failures;
}

class LocalPeerDiscovery {
  LocalPeerDiscovery({required this.onNodesChanged, required this.onError});

  static const _serviceType = '_mlrc-accs._tcp';

  /// Fixed presence port shared by the TCP discovery responder and the Rust
  /// UDP transport (which binds this same number). Fixed so firewall rules,
  /// packet captures, and manual testing stay predictable across both nodes.
  static const int fixedPresencePort = 38421;

  /// Ports for the interim direct USB link. Screen-share frames travel
  /// through an `adb forward`/`adb reverse` tunnel on [usbTunnelDataPort];
  /// presence handshakes run against [usbTunnelPresencePort], which the
  /// tunnel maps to [fixedPresencePort] at the far end of the cable.
  static const int usbTunnelDataPort = 38430;
  static const int usbTunnelPhoneConnectPort = 38432;
  static const int usbTunnelHostConnectPort = 38433;
  static const int usbTunnelPresencePort = 38431;

  final void Function(List<DiscoveredNode> nodes) onNodesChanged;
  final void Function(Object error) onError;
  final Map<String, DiscoveredNode> _nodes = {};

  String? _serviceName;
  ServerSocket? _server;
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<dynamic>? _discoverySubscription;
  bool _broadcastStarted = false;
  bool _discoveryStarted = false;
  final String _instanceId = '$pid-${DateTime.now().microsecondsSinceEpoch}';

  int get port {
    final server = _server;
    if (server == null) {
      throw StateError('Peer discovery has not started.');
    }
    return server.port;
  }

  /// Adds a manually typed peer so a session can be established without
  /// depending on mDNS discovery working on the local network.
  DiscoveredNode addManualNode(String rawAddress, {int? port}) {
    final parsed = InternetAddress.tryParse(rawAddress.trim());
    if (parsed == null || parsed.type != InternetAddressType.IPv4) {
      throw FormatException(
        'Enter the peer\u2019s IPv4 address, for example 192.168.1.140.',
        rawAddress,
      );
    }
    final resolvedPort = port ?? fixedPresencePort;
    if (resolvedPort < 1 || resolvedPort > 65535) {
      throw RangeError.range(resolvedPort, 1, 65535, 'port');
    }
    final node = DiscoveredNode(
      id: 'Manual ${parsed.address}',
      address: parsed.address,
      transport: 'Manual (Wi-Fi)',
      port: resolvedPort,
      allAddresses: [parsed.address],
    );
    _nodes[node.id] = node;
    onNodesChanged(_nodes.values.toList());
    return node;
  }

  /// Adds the loopback peer used by the direct USB link on the Android side.
  /// It stands in for the desktop host: while the phone is attached, the
  /// host's peer discovery applies `adb reverse`, so 127.0.0.1 on the phone
  /// reaches the host machine through the cable.
  DiscoveredNode addUsbTunnelNode() {
    final node = DiscoveredNode(
      id: 'USB Host (ADB tunnel)',
      address: '127.0.0.1',
      transport: 'USB (ADB tunnel)',
      port: usbTunnelPresencePort,
      allAddresses: const ['127.0.0.1'],
    );
    _nodes[node.id] = node;
    onNodesChanged(_nodes.values.toList());
    return node;
  }

  Future<void> start() async {
    try {
      await stop();
    } catch (error) {
      // A broken previous session must never block a fresh start: stop()
      // already released every resource it owns, so reporting is enough.
      onError(error);
    }
    _nodes.clear();
    _serviceName = 'MLRC ACCS';

    try {
      try {
        _server = await ServerSocket.bind(
          InternetAddress.anyIPv4,
          fixedPresencePort,
        );
      } on SocketException catch (error) {
        throw StateError(
          'Presence port $fixedPresencePort is unavailable '
          '(${error.osError?.message ?? error.message}). '
          'Another MLRC ACCS instance may already be running on this machine.',
        );
      }
      _server!.listen((socket) {
        socket
          ..writeln('MLRC-ACCS/1')
          ..close();
      }, onError: onError);

      final service = BonsoirService(
        name: _serviceName!,
        type: _serviceType,
        port: _server!.port,
        attributes: {'id': _instanceId, 'v': '1'},
      );
      _broadcast = BonsoirBroadcast(service: service);
      await _broadcast!.initialize();
      await _broadcast!.start();
      _broadcastStarted = true;

      _discovery = BonsoirDiscovery(type: _serviceType);
      await _discovery!.initialize();
      final events = _discovery!.eventStream;
      if (events == null) {
        throw StateError(
          'The local discovery event stream was not initialized.',
        );
      }
      _discoverySubscription = events.listen(
        _handleDiscoveryEvent,
        onError: onError,
      );
      await _discovery!.start();
      _discoveryStarted = true;
      _publishNodes();
    } catch (_) {
      try {
        await stop();
      } catch (_) {
        // stop() reports its own teardown problems step by step; a partial
        // teardown must not mask the original start() failure.
      }
      rethrow;
    }
  }

  /// Tears the session down step by step so one faulty Bonsoir step can
  /// never leave the presence socket bound or the UI half-stopped: each
  /// step always runs, references are dropped before awaiting, every Bonsoir
  /// call is time-boxed so a hung stop cannot freeze the discovery toggle,
  /// and failures are collected and re-thrown together at the end.
  Future<void> stop() async {
    final failures = <String>[];

    final subscription = _discoverySubscription;
    _discoverySubscription = null;
    if (subscription != null) {
      try {
        await subscription.cancel().timeout(const Duration(seconds: 2));
      } catch (error) {
        failures.add('discovery events: $error');
      }
    }

    final discovery = _discovery;
    _discovery = null;
    if (discovery != null && _discoveryStarted) {
      _discoveryStarted = false;
      try {
        await discovery.stop().timeout(const Duration(seconds: 2));
      } catch (error) {
        failures.add('discovery browser: $error');
      }
    }

    final broadcast = _broadcast;
    _broadcast = null;
    if (broadcast != null && _broadcastStarted) {
      _broadcastStarted = false;
      try {
        await broadcast.stop().timeout(const Duration(seconds: 2));
      } catch (error) {
        failures.add('presence broadcast: $error');
      }
    }

    // The presence socket is closed last and unconditionally: even when a
    // Bonsoir step above failed, port 38421 must be released so the next
    // start (or the Rust UDP transport) can bind it again.
    final server = _server;
    _server = null;
    if (server != null) {
      try {
        await server.close();
      } catch (error) {
        failures.add('presence socket: $error');
      }
    }

    if (failures.isNotEmpty) {
      throw StateError(
        'Discovery teardown reported problems: ${failures.join('; ')}',
      );
    }
  }

  void _handleDiscoveryEvent(dynamic event) {
    if (event is BonsoirDiscoveryServiceFoundEvent) {
      final service = event.service;
      if (service.attributes['id'] != _instanceId) {
        unawaited(_resolveService(service));
      }
      return;
    }

    if (event is BonsoirDiscoveryServiceResolvedEvent) {
      final service = event.service;
      if (service.attributes['id'] == _instanceId) {
        return;
      }
      final addresses = service.hostAddresses;
      final routable = <String>[];
      final linkLocal = <String>[];
      for (final address in addresses) {
        final parsedAddress = InternetAddress.tryParse(address);
        if (parsedAddress?.type != InternetAddressType.IPv4) {
          continue;
        }
        final value = parsedAddress!.address;
        if (value.startsWith('169.254.') || value == '127.0.0.1') {
          linkLocal.add(value);
        } else {
          routable.add(value);
        }
      }
      String? ipv4Address;
      for (final candidate in routable) {
        if (ipv4Address == null ||
            _ipv4Preference(candidate) < _ipv4Preference(ipv4Address)) {
          ipv4Address = candidate;
        }
      }
      ipv4Address ??= linkLocal.isEmpty ? null : linkLocal.first;
      _nodes[service.name] = DiscoveredNode(
        id: service.name,
        address: ipv4Address ?? 'IPv4 address unavailable',
        transport: 'Wi-Fi (mDNS)',
        port: service.port,
        allAddresses: [...routable, ...linkLocal],
      );
      _publishNodes();
      return;
    }

    if (event is BonsoirDiscoveryServiceLostEvent) {
      final service = event.service;
      if (_nodes.remove(service.name) != null) {
        _publishNodes();
      }
    }
  }

  void _publishNodes() {
    onNodesChanged(List.unmodifiable(_nodes.values.toList()));
  }

  Future<void> _resolveService(BonsoirService service) async {
    try {
      await service.resolve(_discovery!.serviceResolver);
    } catch (error) {
      onError(error);
    }
  }
}
