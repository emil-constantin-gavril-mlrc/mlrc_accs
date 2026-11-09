import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _StartNative = ffi.Int32 Function(
  ffi.Uint32,
  ffi.Uint16,
  ffi.Uint32,
  ffi.Uint16,
  ffi.Pointer<ffi.Pointer<ffi.Void>>,
  ffi.Pointer<ffi.Char>,
  ffi.IntPtr,
);
typedef _StartDart = int Function(
  int,
  int,
  int,
  int,
  ffi.Pointer<ffi.Pointer<ffi.Void>>,
  ffi.Pointer<ffi.Char>,
  int,
);
typedef _SendNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.IntPtr,
  ffi.Pointer<ffi.Char>,
  ffi.IntPtr,
);
typedef _SendDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Char>,
  int,
);
typedef _PollNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
  ffi.Pointer<ffi.IntPtr>,
  ffi.Pointer<ffi.Char>,
  ffi.IntPtr,
);
typedef _PollDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
  ffi.Pointer<ffi.IntPtr>,
  ffi.Pointer<ffi.Char>,
  int,
);
typedef _FreeBufferNative = ffi.Void Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.IntPtr,
);
typedef _FreeBufferDart = void Function(ffi.Pointer<ffi.Uint8>, int);
typedef _SentBytesNative = ffi.IntPtr Function(ffi.Pointer<ffi.Void>);
typedef _SentBytesDart = int Function(ffi.Pointer<ffi.Void>);
typedef _StopNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _StopDart = void Function(ffi.Pointer<ffi.Void>);

class RustTransport {
  RustTransport._(ffi.DynamicLibrary library)
    : _start = library.lookupFunction<_StartNative, _StartDart>(
        'mlrc_watcher_start',
      ),
      _send = library.lookupFunction<_SendNative, _SendDart>(
        'mlrc_watcher_send',
      ),
      _poll = library.lookupFunction<_PollNative, _PollDart>(
        'mlrc_watcher_poll',
      ),
      _freeBuffer = library.lookupFunction<_FreeBufferNative, _FreeBufferDart>(
        'mlrc_buffer_free',
      ),
      _sentBytes = library.lookupFunction<_SentBytesNative, _SentBytesDart>(
        'mlrc_watcher_sent_bytes',
      ),
      _stop = library.lookupFunction<_StopNative, _StopDart>(
        'mlrc_watcher_stop',
      );

  static const int _errorCapacity = 1024;
  final _StartDart _start;
  final _SendDart _send;
  final _PollDart _poll;
  final _FreeBufferDart _freeBuffer;
  final _SentBytesDart _sentBytes;
  final _StopDart _stop;
  ffi.Pointer<ffi.Void>? _watcher;

  factory RustTransport() {
    if (Platform.isWindows) {
      return RustTransport._(ffi.DynamicLibrary.open('mlrc_accs_backend.dll'));
    }
    if (Platform.isAndroid) {
      return RustTransport._(
        ffi.DynamicLibrary.open('libmlrc_accs_backend.so'),
      );
    }
    throw UnsupportedError(
      'The Rust transport is currently packaged for Windows and Android only.',
    );
  }

  RustTransport.fromLibraryPath(String path)
    : this._(ffi.DynamicLibrary.open(path));

  void start({
    required bool transmitting,
    required int localPort,
    required String peerAddress,
    required int peerPort,
  }) {
    if (_watcher != null) {
      throw StateError('The Rust transport is already running.');
    }
    final address = InternetAddress.tryParse(peerAddress);
    if (address == null || address.type != InternetAddressType.IPv4) {
      throw FormatException(
        'Peer address must be an IPv4 address.',
        peerAddress,
      );
    }
    if (peerPort < 1 || peerPort > 65535) {
      throw RangeError.range(peerPort, 1, 65535, 'peerPort');
    }
    if (localPort < 0 || localPort > 65535) {
      throw RangeError.range(localPort, 0, 65535, 'localPort');
    }

    final output = calloc<ffi.Pointer<ffi.Void>>();
    final error = calloc<ffi.Char>(_errorCapacity);
    try {
      final result = _start(
        transmitting ? 0 : 1,
        localPort,
        address.rawAddress.fold<int>(0, (value, octet) => (value << 8) | octet),
        peerPort,
        output,
        error,
        _errorCapacity,
      );
      if (result != 0) {
        throw StateError(_readError(error));
      }
      _watcher = output.value;
    } finally {
      calloc.free(error);
      calloc.free(output);
    }
  }

  void sendFrame(Uint8List frame) {
    final watcher = _requireWatcher();
    final data = calloc<ffi.Uint8>(frame.isEmpty ? 1 : frame.length);
    final error = calloc<ffi.Char>(_errorCapacity);
    try {
      data.asTypedList(frame.length).setAll(0, frame);
      final result = _send(watcher, data, frame.length, error, _errorCapacity);
      if (result != 0) {
        throw StateError(_readError(error));
      }
    } finally {
      calloc.free(error);
      calloc.free(data);
    }
  }

  Uint8List? pollFrame() {
    final watcher = _requireWatcher();
    final output = calloc<ffi.Pointer<ffi.Uint8>>();
    final length = calloc<ffi.IntPtr>();
    final error = calloc<ffi.Char>(_errorCapacity);
    try {
      final result = _poll(watcher, output, length, error, _errorCapacity);
      if (result == 0) return null;
      if (result < 0) {
        throw StateError(_readError(error));
      }
      try {
        return Uint8List.fromList(output.value.asTypedList(length.value));
      } finally {
        _freeBuffer(output.value, length.value);
      }
    } finally {
      calloc.free(error);
      calloc.free(length);
      calloc.free(output);
    }
  }

  int get sentBytes => _sentBytes(_requireWatcher());

  void stop() {
    final watcher = _watcher;
    if (watcher == null) return;
    _watcher = null;
    _stop(watcher);
  }

  ffi.Pointer<ffi.Void> _requireWatcher() {
    final watcher = _watcher;
    if (watcher == null) {
      throw StateError('The Rust transport is not running.');
    }
    return watcher;
  }

  String _readError(ffi.Pointer<ffi.Char> error) {
    final message = error.cast<Utf8>().toDartString();
    return message.isEmpty ? 'Rust transport operation failed.' : message;
  }
}
