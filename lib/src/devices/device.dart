// Copyright 2020 The vTap Project Authors. All rights reserved.
// Use of this source code is governed by a BSD 3-Clause license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_finder/device_finder.dart';
import 'package:device_finder/src/command_line_output_parser.dart';

import 'ios_simulator_device.dart';

const String ksJsonFieldDeviceName = 'name';
const String ksJsonFieldDeviceIdentifier = 'identifier';
const String ksJsonFieldDevicePlatform = 'platform';
const String ksJsonFieldDeviceIsLocalEmulator = 'isLocalEmulator';

const String ksJsonValueDevicePlatformAndroid = 'Android';
const String ksJsonValueDevicePlatformIosSimulator = 'iOS Simulator';
const String ksJsonValueDevicePlatformIosDevice = 'iOS';
const String ksJsonValueDevicePlatformWindows = 'Windows';

/// Represents a device that is ready to run tests.
abstract class Device {
  Device(this.name, this.identifier);

  /// The name of the the device.
  final String name;

  /// A string that uniquely identifies the device from others.
  ///
  /// For android, this is the serial number given by the adb tool to the device
  final String identifier;

  bool get isLocalEmulator => false;

  String get platform;

  Future<bool> installApp(String executablePath, ApplicationPackage app);

  Future<DebugSessionInformation> launchFlutterApp({
    required String adbPath,
  }) async {
    stdout.writeln('🤖 launchFlutterApp - flutter run -d RZCT90XD8WZ');

    Completer flutterDebugSessionCompleter = Completer();
    late String debugUrl;

    final flutterDebugSessionFuture = Process.start('flutter', [
      'run',
      '-d',
      identifier,
    ]).then((p) {
      p.stdout.transform(Utf8Decoder()).listen((logLine) {
        if (logLine.contains('is available at:')) {
          stdout.writeln('🤖 Debug url session found.\nInfo = $logLine');
          debugUrl = logLine;
        }
      });

      p.stderr.transform(utf8.decoder).listen((data) {
        stdout.writeln('🔴 $data');
      });

      p.exitCode.then((exitCode) {
        stdout.writeln('🤖 Exit code: $exitCode');
      });

      return p;
    }).catchError((e) {
      stdout.writeln('🔴 Error:${e.toString()}');
      throw 'Error occur while trying to run the application';
    });

    await flutterDebugSessionCompleter.future;
    await flutterDebugSessionFuture;

    // flutterProcessLogOutputSubscription.cancel();

    stdout.writeln('🤖 debugUrl: $debugUrl');

    final debugInformation = await SessionUtils.getDebugSession(
      adbPath: adbPath,
      data: debugUrl,
      identifier: identifier,
      isAndroidDevice: this is AndroidDevice,
    );

    if (debugInformation == null) {
      throw 'Output is fucked up. Check out what is happening above ';
    }

    return debugInformation;
  }

  Future<DebugSessionInformation> launchAppFromBinary(
    String executablePath,
    ApplicationPackage app,
  );

  Future<bool> killApp(String executablePath, ApplicationPackage app);
  Future<bool> pressHomeButton(String executablePath);
  Future<bool> pressEnterButton(String executablePath);
  Future<bool> pressBackButton(String executablePath);

  @override
  String toString() => '$name: $identifier';

  @override
  bool operator ==(dynamic other) {
    return (other is Device) &&
        (this.name == other.name) &&
        (this.identifier == other.identifier);
  }

  @override
  int get hashCode => this.identifier.hashCode;

  Map<String, dynamic> toJson() {
    return {
      ksJsonFieldDeviceName: this.name,
      ksJsonFieldDeviceIdentifier: this.identifier,
      ksJsonFieldDevicePlatform: this.platform,
      ksJsonFieldDeviceIsLocalEmulator: this.isLocalEmulator,
    };
  }

  factory Device.fromJson(Map<String, dynamic> json) {
    final String name = json[ksJsonFieldDeviceName];
    final String identifier = json[ksJsonFieldDeviceIdentifier];

    switch (json[ksJsonFieldDevicePlatform]) {
      case ksJsonValueDevicePlatformAndroid:
        return AndroidDevice(name, identifier);
      case ksJsonValueDevicePlatformIosSimulator:
        return IOSSimulator(name, identifier);
      case ksJsonValueDevicePlatformIosDevice:
        return IosDevice(name, identifier);
      case ksJsonValueDevicePlatformWindows:
        return WindowsDevice(name, identifier);
      default:
        throw ArgumentError(
          'Unknown Device Platform ${json[ksJsonFieldDevicePlatform]}',
        );
    }
  }

  factory Device.fakeAndroidDevice(Map<String, dynamic> json) {
    final String name = json[ksJsonFieldDeviceName];
    final String identifier = json[ksJsonFieldDeviceIdentifier];

    return FakeAndroidDevice(name, identifier);
  }
}

/// Gets all the ready android devices.
///
/// Uses `$ adb devices` command.
class _AndroidDevicesFinder {
  final List<AndroidDevice> devices = [];
  Future<void> extractDevices(String devicesPaths) {
    RegExp pattern = RegExp(r'^(.*?)\s*device.*model:(.*?)\s.*?$');

    LineSplitter().convert(devicesPaths).forEach((line) {
      Iterable<RegExpMatch> matches = pattern.allMatches(line);

      matches.forEach((RegExpMatch match) {
        String identifier =
            match.group(1) ?? "identifier can't be found in $match";
        String name = match.group(2) ?? "name can't be found in $match";

        devices.add(AndroidDevice(name, identifier));
      });
    });

    return Future.value();
  }

  static Future<List<Device>> listReady(String adbPath) async {
    final result = await Process.run('flutter', ['devices']);

    // group 1: name
    // group 2: id
    // group 3: architecture
    // group 4: operating system
    RegExp pattern = RegExp(r'^(.*?)\s*•\s*(.*?)\s*•\s*(.*?)\s*•\s*(.*?)\s*$');

    final devices = <AndroidDevice>[];

    LineSplitter().convert(result.stdout).forEach((line) {
      stdout.writeln('🤖 $line');
      Iterable<RegExpMatch> matches = pattern.allMatches(line);

      matches.forEach((RegExpMatch match) {
        String identifier =
            match.group(2) ?? "identifier can't be found in $match";
        String name = match.group(1) ?? "name can't be found in $match";

        devices.add(AndroidDevice(name, identifier));
      });
    });

    if (result.exitCode != 0) {
      stdout.writeln('🔴 ${result.stderr}');
      throw 'Failed to find android device with `adb devices` exit code $exitCode';
    }

    return devices;
  }
}

class _IOSSimulatorDeviceFinder {
  static Future<List<Device>> listReady() async {
    stdout.writeln('🤖 iOSDeviceFinder:listDevices');
    const String _xcrunPath = '/usr/bin/xcrun';

    try {
      stdout.writeln('🤖 iOSDeviceFinder:listDevices - Start process ...');

      final result = await Process.run(_xcrunPath, [
        'simctl',
        'list',
        '--json',
        'devices',
      ]);

      stdout.writeln('🤖 iOSDeviceFinder:listDevices - Process complete');
      stdout.writeln('🤖 ${result.stdout}');

      if (result.exitCode != 0) {
        throw 'Failed to find simulator devices. Exit code $exitCode. \n Output:${result.stdout} \ Error:${result.stderr}';
      }

      final outputParser = CommandLineOutputParser();

      return outputParser.parseDeviceListing(result.stdout);
    } catch (e, s) {
      stdout.writeln('🔴 Error:${e.toString()} StackTrace:\n$s');
      rethrow;
    }
  }
}

/// Returns all the devices ready for testing.
///
/// If no devices are ready it returns an empty list.
Future<List<Device>> getReadyDevices(String adbPath) async {
  final List<Device> devices = [];

  try {
    devices.addAll(await _AndroidDevicesFinder.listReady(adbPath));
  } catch (e) {
    stdout.writeln('🔴 Android device fetch failed: ${e.toString()}');
  }

  if (Platform.isMacOS) {
    try {
      devices.addAll(await _IOSSimulatorDeviceFinder.listReady());
    } catch (e) {
      stdout.writeln('🔴 iOS simulators fetch failed: ${e.toString()}');
    }
  }

  return devices;
}

/// Checks if ANDROID_HOME path is set in the system.
String? getAndroidSDKPath() {
  String? sdkPath = Platform.environment['ANDROID_HOME'];
  if (sdkPath == null) {
    stdout.writeln('🤖 The ANDROID_HOME environment variable is not set');
    return null;
  }

  return sdkPath;
}

class DebugSessionInformation {
  final String? debugUrl;
  final String? remotePort;
  final String? localPort;

  String get localPortDebugUrl => debugUrl!.replaceAll(remotePort!, localPort!);

  DebugSessionInformation({
    this.debugUrl,
    this.remotePort,
    this.localPort,
  });

  @override
  String toString() {
    return 'DebugSessionInformation | $debugUrl remote:$remotePort localPort:$localPort localPortDebugUrl:$localPortDebugUrl';
  }
}

class CollectingStdErrConsumer extends StreamConsumer<List<int>> {
  final List<int> _collectedUnits = [];
  String get collectAsString => utf8.decode(_collectedUnits);

  @override
  Future addStream(Stream<List<int>> stream) {
    return stream.forEach((data) {
      _collectedUnits.addAll(data);
      stderr.add(data);
    });
  }

  @override
  Future close() {
    return Future(() => null);
  }
}

class FakeAndroidDevice extends Device {
  FakeAndroidDevice(String name, String identifier) : super(name, identifier);

  @override
  Future<bool> installApp(
    String executablePath,
    covariant AndroidApk app,
  ) async {
    stdout.writeln('🤖 installApp');
    return true;
  }

  Future<void> grantPermissions(String executablePath, AndroidApk app) async {
    stdout.writeln('🤖 Fetching required permissions');
  }

  @override
  Future<DebugSessionInformation> launchAppFromBinary(
    String executablePath,
    covariant AndroidApk app,
  ) async {
    return DebugSessionInformation(debugUrl: 'Fake Android Device debugUrl');
  }

  @override
  Future<bool> killApp(String executablePath, covariant AndroidApk app) async {
    return true;
  }

  @override
  Future<bool> pressHomeButton(String executablePath) async {
    return true;
  }

  @override
  String get platform => ksJsonValueDevicePlatformAndroid;

  @override
  Future<bool> pressBackButton(String executablePath) {
    // TODO: implement pressBackButton
    throw UnimplementedError();
  }

  @override
  Future<bool> pressEnterButton(String executablePath) {
    // TODO: implement pressEnterButton
    throw UnimplementedError();
  }
}
