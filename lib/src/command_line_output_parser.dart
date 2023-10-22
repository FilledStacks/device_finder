import 'dart:convert';

import 'devices/ios_device.dart';

/// This class parses expected command line outputs into a typed structure
class CommandLineOutputParser {
  List<IOSSimulator> parseDeviceListing(String input) {
    final devices = <IOSSimulator>[];
    try {
      final Object? simulators = json.decode(input)['devices'];
      if (simulators is Map<String, dynamic>) {
        for (final String deviceCategory in simulators.keys) {
          final Object? devicesData = simulators[deviceCategory];
          if (devicesData != null && devicesData is List<dynamic>) {
            for (final data in devicesData) {
              if (data['state'] == 'Booted')
                devices.add(IOSSimulator(data['name'], data['udid']));
            }
          }
        }
      }
    } on FormatException {
      // We failed to parse the simctl output, or it returned junk.
      // One known message is "Install Started" isn't valid JSON but is
      // returned sometimes.
      print('🔴 simctl returned non-JSON response: $input');
    }

    return devices;
  }
}
