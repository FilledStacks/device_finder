import 'dart:convert';
import 'dart:io';

import 'package:device_finder/src/devices/android_device.dart';
import 'package:device_finder/src/devices/device.dart';
import 'package:device_finder/src/devices/ios_device.dart';
import 'package:device_finder/src/devices/macos_device.dart';

class DeviceFinder {
  static Future<List<Device>> listReady({bool verbose = false}) async {
    try {
      final flutterDevicesProcess = await Process.run(
        'flutter',
        [
          'devices',
          if (verbose) '-v',
        ],
      );

      // group 1: name
      // group 2: id
      // group 3: architecture
      // group 4: operating system
      RegExp pattern = RegExp(
        r'^(.*?)\s*•\s*(.*?)\s*•\s*(.*?)\s*•\s*(.*?)\s*$',
      );

      final androidDevices = <AndroidDevice>[];
      final iOSDevices = <IosDevice>[];
      final macOSDevices = <MacOsDevice>[];

      LineSplitter().convert(flutterDevicesProcess.stdout).forEach((line) {
        if (verbose) {
          stdout.writeln('🤖 $line');
        }

        Iterable<RegExpMatch> matches = pattern.allMatches(line);

        matches.forEach((RegExpMatch match) {
          String identifier =
              match.group(2)?.trim() ?? "identifier can't be found in $match";
          String name =
              match.group(1)?.trim() ?? "name can't be found in $match";
          if (match.group(4)!.toLowerCase().contains('android')) {
            androidDevices.add(AndroidDevice(name, identifier));
          } else if (match.group(4)!.toLowerCase().contains('ios')) {
            iOSDevices.add(IosDevice(name, identifier));
          } else if (match.group(4)!.toLowerCase().contains('macos')) {
            macOSDevices.add(MacOsDevice(name, identifier));
          }
        });
      });

      if (flutterDevicesProcess.exitCode != 0) {
        if (verbose) {
          stdout.writeln('🔴 ${flutterDevicesProcess.stderr}');
        }

        throw 'Failed to find android device with `adb devices` exit code $exitCode';
      }

      return [...androidDevices, ...iOSDevices, ...macOSDevices];
    } catch (e, s) {
      stdout.writeln('🔴 Error:${e.toString()} \nStackTrace:$s');
      return [];
    }
  }
}
