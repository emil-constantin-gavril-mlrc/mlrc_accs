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
  });

  final String id;
  final String address;
  final String transport;
  final int port;
  final String status;
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

Future<List<AdbDevice>> findAdbDevices() async {
  if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
    throw UnsupportedError(
      'ADB USB discovery is supported on desktop hosts only.',
    );
  }

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

  final executable = adbPath ?? 'adb';
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

class LocalPeerDiscovery {
  LocalPeerDiscovery({required this.onNodesChanged, required this.onError});

  static const _serviceType = '_mlrc-accs._tcp';

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

  Future<void> start() async {
    await stop();
    _nodes.clear();
    _serviceName = 'MLRC ACCS';

    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
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
      await stop();
      rethrow;
    }
  }

  Future<void> stop() async {
    await _discoverySubscription?.cancel();
    _discoverySubscription = null;
    if (_discovery != null) {
      if (_discoveryStarted) {
        await _discovery!.stop();
      }
      _discoveryStarted = false;
      _discovery = null;
    }
    if (_broadcast != null) {
      if (_broadcastStarted) {
        await _broadcast!.stop();
      }
      _broadcastStarted = false;
      _broadcast = null;
    }
    await _server?.close();
    _server = null;
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
      _nodes[service.name] = DiscoveredNode(
        id: service.name,
        address: addresses.isEmpty ? 'Address unavailable' : addresses.first,
        transport: 'Wi-Fi (mDNS)',
        port: service.port,
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
