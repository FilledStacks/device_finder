import 'dart:convert';
import 'dart:io';

import 'package:device_finder/application_package.dart';
import 'package:device_finder/src/devices/ios_device.dart';

import 'android_device.dart';
import 'device.dart';

/// A Windows device ready to run tests.
class WindowsDevice extends Device {
  WindowsDevice(String name, String identifier) : super(name, identifier);

  @override
  Future<bool> installApp(String executablePath, ApplicationPackage app) {
    // TODO: implement installApp
    throw UnimplementedError();
  }

  @override
  Future<bool> killApp(String executablePath, ApplicationPackage app) {
    // TODO: implement killApp
    throw UnimplementedError();
  }

  @override
  Future<DebugSessionInformation> launchAppFromBinary(
      String executablePath, ApplicationPackage app) {
    // TODO: implement launchApp
    throw UnimplementedError();
  }

  @override
  String get platform => ksJsonValueDevicePlatformWindows;

  @override
  Future<bool> pressHomeButton(String executablePath) {
    // TODO: implement pressHomeButton
    throw UnimplementedError();
  }

  @override
  Future<bool> pressBackButton(String executablePath) {
    // TODO: implement pressBackButton
    throw UnimplementedError();
  }
}

class DeviceFinder {
  static Future<List<Device>> listReady({bool verbose = false}) async {
    try {
      final flutterDevicesProcess = await Process.run('flutter', [
        'devices',
        if (verbose) '-v',
      ]);

      // group 1: name
      // group 2: id
      // group 3: architecture
      // group 4: operating system
      RegExp pattern = RegExp(
        r'^(.*?)\s*•\s*(.*?)\s*•\s*(.*?)\s*•\s*(.*?)\s*$',
      );

      final androidDevices = <AndroidDevice>[];
      final iOSDevices = <IosDevice>[];

      LineSplitter().convert(flutterDevicesProcess.stdout).forEach((line) {
        if (verbose) {
          stdout.writeln('🤖 $line');
        }

        Iterable<RegExpMatch> matches = pattern.allMatches(line);

        matches.forEach((RegExpMatch match) {
          String identifier =
              match.group(2) ?? "identifier can't be found in $match";
          String name = match.group(1) ?? "name can't be found in $match";
          if (match.group(4)!.toLowerCase().contains('android')) {
            androidDevices.add(AndroidDevice(name, identifier));
          } else if (match.group(4)!.toLowerCase().contains('ios')) {
            iOSDevices.add(IosDevice(name, identifier));
          }
        });
      });

      if (flutterDevicesProcess.exitCode != 0) {
        if (verbose) {
          stdout.writeln('🔴 ${flutterDevicesProcess.stderr}');
        }

        throw 'Failed to find android device with `adb devices` exit code $exitCode';
      }

      return [...androidDevices, ...iOSDevices];
    } catch (e, s) {
      stdout.writeln('🔴 Error:${e.toString()} \nStackTrace:$s');
      return [];
    }
  }
}
