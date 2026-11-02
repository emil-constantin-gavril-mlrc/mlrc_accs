import 'package:flutter_test/flutter_test.dart';
import 'package:screen_mirror/debug_services.dart';

void main() {
  group('parseAdbDevices', () {
    test('parses authorized and unauthorized devices', () {
      final devices = parseAdbDevices('''
List of devices attached
R58M123456A device product:demo model:Pixel_8 device:husky transport_id:1
R58M987654B unauthorized usb:1-2 transport_id:2
''');

      expect(devices, hasLength(2));
      expect(devices[0].serial, 'R58M123456A');
      expect(devices[0].status, 'device');
      expect(devices[0].description, 'Pixel 8');
      expect(devices[1].status, 'unauthorized');
    });

    test('accepts adb startup output before the device list', () {
      final devices = parseAdbDevices('''
* daemon started successfully
List of devices attached
emulator-5554 device product:sdk_gphone64_x86_64 model:Virtual_Device
''');

      expect(devices, hasLength(1));
      expect(devices.single.description, 'Virtual Device');
    });

    test('rejects output that is not an adb device list', () {
      expect(() => parseAdbDevices('adb failed'), throwsFormatException);
    });
  });
}
