import 'dart:io';

import 'package:desktop_screenshot/desktop_screenshot.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class ScreenCaptureService {
  static const MethodChannel _androidCaptureChannel = MethodChannel(
    'flutter_screen_recording',
  );

  final DesktopScreenshot _desktopScreenshot = DesktopScreenshot();
  bool _androidCaptureStarted = false;

  Future<void> startContinuousCapture() async {
    if (!Platform.isAndroid || _androidCaptureStarted) return;

    final started = await _androidCaptureChannel.invokeMethod<bool>(
      'startCaptureSession',
      {
        'name': 'mlrc_stream_${DateTime.now().millisecondsSinceEpoch}',
        'title': 'MLRC screen streaming',
        'message': 'Screen sharing is active',
      },
    );
    if (started != true) {
      throw StateError('Android did not authorize continuous screen capture.');
    }
    _androidCaptureStarted = true;
  }

  Future<void> stopContinuousCapture() async {
    if (!Platform.isAndroid || !_androidCaptureStarted) return;
    _androidCaptureStarted = false;
    await _androidCaptureChannel.invokeMethod<void>('stopCaptureSession');
  }

  Future<Uint8List> captureCurrentScreen() async {
    if (Platform.isWindows || Platform.isLinux) {
      final bytes = await _desktopScreenshot.getScreenshot();
      if (bytes == null || bytes.isEmpty) {
        throw StateError('The desktop capture API returned no image.');
      }
      return _encodeCompactFrame(bytes);
    }

    if (Platform.isAndroid) {
      return _captureAndroidScreen();
    }

    throw UnsupportedError(
      'Screen capture is not supported on ${Platform.operatingSystem}.',
    );
  }

  Future<Uint8List> _captureAndroidScreen() async {
    final isTemporarySession = !_androidCaptureStarted;
    try {
      if (isTemporarySession) {
        await startContinuousCapture();
      }
      for (var attempt = 0; attempt < 20; attempt++) {
        final bytes = await _androidCaptureChannel.invokeMethod<Uint8List>(
          'captureScreenFrame',
        );
        if (bytes != null && bytes.isNotEmpty) return bytes;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      throw StateError('Android screen capture produced no frame.');
    } finally {
      if (isTemporarySession) {
        await stopContinuousCapture();
      }
    }
  }

  Uint8List _encodeCompactFrame(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException(
        'The desktop capture is not a supported image.',
      );
    }

    final resized = decoded.width > 960 || decoded.height > 960
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? 960 : null,
            height: decoded.height > decoded.width ? 960 : null,
            interpolation: img.Interpolation.average,
          )
        : decoded;
    return img.encodeJpg(resized, quality: 75);
  }
}
