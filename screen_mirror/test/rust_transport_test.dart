import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:screen_mirror/rust_transport.dart';

Future<int> _unusedUdpPort() async {
  final socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  socket.close();
  return port;
}

void main() {
  final libraryPath = Platform.environment['MLRC_RUST_BACKEND_DLL'];

  test(
    'Dart FFI transports a frame between Rust UDP watchers',
    () async {
      final senderPort = await _unusedUdpPort();
      var receiverPort = await _unusedUdpPort();
      while (receiverPort == senderPort) {
        receiverPort = await _unusedUdpPort();
      }

      final sender = RustTransport.fromLibraryPath(libraryPath!);
      final receiver = RustTransport.fromLibraryPath(libraryPath);
      try {
        sender.start(
          transmitting: true,
          localPort: senderPort,
          peerAddress: '127.0.0.1',
          peerPort: receiverPort,
        );
        receiver.start(
          transmitting: false,
          localPort: receiverPort,
          peerAddress: '127.0.0.1',
          peerPort: senderPort,
        );

        final expected = Uint8List.fromList(
          'Dart-to-Rust-to-Dart frame'.codeUnits,
        );
        sender.sendFrame(expected);

        Uint8List? actual;
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (actual == null && DateTime.now().isBefore(deadline)) {
          actual = receiver.pollFrame();
          if (actual == null) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        }
        expect(actual, expected);
        expect(sender.acknowledgedBytes, expected.length);
      } finally {
        sender.stop();
        receiver.stop();
      }
    },
    skip: libraryPath == null
        ? 'Set MLRC_RUST_BACKEND_DLL to test FFI.'
        : false,
  );
}
