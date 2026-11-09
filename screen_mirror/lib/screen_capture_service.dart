import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_screenshot/desktop_screenshot.dart';
import 'package:flutter_screen_recording/flutter_screen_recording.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class ScreenCaptureService {
  final DesktopScreenshot _desktopScreenshot = DesktopScreenshot();

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
    final fileName =
        'mlrc_debug_capture_${DateTime.now().millisecondsSinceEpoch}';
    final cacheDirectories = await getExternalCacheDirectories();
    final cacheDirectory =
        cacheDirectories != null && cacheDirectories.isNotEmpty
        ? cacheDirectories.first
        : await getTemporaryDirectory();
    final temporaryRecording = File(
      '${cacheDirectory.path}${Platform.pathSeparator}$fileName.mp4',
    );

    String? recordingPath;
    try {
      final started = await FlutterScreenRecording.startRecordScreen(
        fileName,
        titleNotification: 'MLRC screen capture',
        messageNotification: 'Capturing one screen preview',
      );
      if (!started) {
        throw StateError(
          'Android did not start the user-authorized screen capture.',
        );
      }

      await Future<void>.delayed(const Duration(milliseconds: 1200));
      recordingPath = await FlutterScreenRecording.stopRecordScreen;
      if (recordingPath.isEmpty) {
        throw StateError('Android screen capture returned no recording path.');
      }

      final bytes = await VideoThumbnail.thumbnailData(
        video: recordingPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 960,
        quality: 75,
        timeMs: 700,
      );
      if (bytes == null || bytes.isEmpty) {
        throw StateError(
          'Could not decode a preview frame from the Android capture.',
        );
      }
      return bytes;
    } finally {
      if (recordingPath != null &&
          recordingPath.isNotEmpty &&
          recordingPath != temporaryRecording.path) {
        final recording = File(recordingPath);
        if (await recording.exists()) await recording.delete();
      }
      if (await temporaryRecording.exists()) {
        await temporaryRecording.delete();
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
