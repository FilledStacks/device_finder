// Copyright 2020 The vTap Project Authors. All rights reserved.
// Use of this source code is governed by a BSD 3-Clause license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_finder/device_finder.dart';
import 'package:io/io.dart';

import 'src/command_line_output_parser.dart';

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

  Future<DebugSessionInformation> launchFlutterApp() async {
    print('launchFlutterApp - flutter run -d RZCT90XD8WZ');

    Completer flutterDebugSessionCompleter = Completer();
    late String debugUrl;
    late StreamSubscription<String> flutterProcessLogOutputSubscription;

    final Future<Process> flutterDebugSessionFuture = Process.start('flutter', [
      'run',
      '-d',
      identifier,
    ]).then((p) {
      flutterProcessLogOutputSubscription =
          p.stdout.transform(new Utf8Decoder()).listen((logLine) {
        if (logLine.contains('is available at:')) {
          print('Debug url session found.\nInfo = $logLine');
          debugUrl = logLine;
          // flutterDebugSessionCompleter.complete();
        }
      });
      // p.stderr.transform(new Utf8Decoder()).listen(print);
      // stdin.pipe(p.stdin);

      return p;
    });

    await flutterDebugSessionCompleter.future;
    final flutterDebugSession = await flutterDebugSessionFuture;

    // flutterProcessLogOutputSubscription.cancel();

    print('debugUrl: $debugUrl');

    final cliPath = Platform.script.toFilePath();
    final adbPath =
        '${cliPath.split('bin').first}dependencies/macos/platform-tools/adb';

    final debugInformation = await SessionUtils.getDebugSession(
      adbPath: adbPath,
      data: debugUrl,
      identifier: identifier,
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
            "Unknown Device Platform ${json[ksJsonFieldDevicePlatform]}");
    }
  }
  factory Device.fakeAndroidDevice(Map<String, dynamic> json) {
    final String name = json[ksJsonFieldDeviceName];
    final String identifier = json[ksJsonFieldDeviceIdentifier];

    return FakeAndroidDevice(name, identifier);
  }
}

/// [-s] Direct an adb command to a specific device, referred to by its adb-assigned serial number (such as emulator-5556).
/// Overrides the serial number value stored in the $ANDROID_SERIAL environment variable
///
/// App installation commands
/// Push packages to the device and install them. Possible options are the following:
/// -l: Forward lock app.
/// -r: Replace the existing app.
/// -t: Allow test packages. If the APK is built using a developer preview SDK (if the targetSdkVersion is a letter instead of a number), you must include the -t option with the install command if you are installing a test APK.
/// -s: Install the app on the SD card.
/// -d: Allow version code downgrade (debugging packages only).
/// -g: Grant all runtime permissions.

/// see [http://adbcommand.com/adbshell] for more info
///
/// An Android device ready to run tests.
class AndroidDevice extends Device {
  AndroidDevice(String name, String identifier) : super(name, identifier);

  @override
  Future<bool> installApp(
    String executablePath,
    covariant AndroidApk app,
  ) async {
    await clearAppData(executablePath, app);

    var spawn = await Process.run(
      executablePath,
      ['-s', identifier, 'install', '-r', app.filePath],
    );
    var exitCode = spawn.exitCode;
    print(spawn.stderr);

    // Previous app data is retained using the above command
    // We need to clear the data manually for a fresh install
    await grantPermissions(executablePath, app);
    if (exitCode != 0)
      throw 'Failed to install ${app.filePath} on $identifier cause of ${spawn.stderr}';
    return true;
  }

  Future<void> grantPermissions(String executablePath, AndroidApk app) async {
    print('Fetching required permissions');
    final List<String?> permissions = await app.getPermissions();
    for (String? permission in permissions) {
      await Process.run(
        executablePath,
        ['-s', identifier, 'shell', 'pm', 'grant', app.id, permission!],
      ).catchError((err) => print('Unable to grant permission: $permission'));
    }
  }

  @override
  Future<DebugSessionInformation> launchAppFromBinary(
    String executablePath,
    covariant AndroidApk app,
  ) async {
    print('executablePath:$executablePath app:$app');
    var spawn = await Process.run(executablePath, [
      '-s',
      identifier,
      'shell',
      'am',
      'start',
      '--ez', 'start-paused', 'true',
      '-n',
      '${app.id}/${app.launchActivity}',
      '-W', // To get the most recent debugUrl
    ]);
    var exitCode = spawn.exitCode;
    if (exitCode != 0)
      throw 'Failed to launch ${app.launchActivity} on $identifier. You might have given an incorrect Activity or package name.';

    var logProcResults = await Process.run(executablePath, [
      '-s',
      identifier,
      'logcat',
      '-d',
      'flutter:I', // Take those with flutter tag in info or higher
      '*:S', // Ignore all others
      // '-T',
      // '$time' // To get the most recent debugUrl
    ]);
    exitCode = logProcResults.exitCode;
    if (exitCode != 0) {
      throw 'Logcat failed to run with error message: ' +
          logProcResults.stderr.toString();
    }

    final data = logProcResults.stdout.toString();
    print('data: $data');

    final debugInformation = await SessionUtils.getDebugSession(
      adbPath: executablePath,
      data: data,
      identifier: identifier,
    );

    if (debugInformation == null) {
      throw 'Output from logcat does not contain debug url: ' +
          logProcResults.stderr.toString();
    }
    return debugInformation;
  }

  Future<bool> clearAppData(
      String executablePath, covariant AndroidApk app) async {
    var process = await Process.run(
      executablePath,
      ['-s', identifier, 'uninstall', app.id],
    );
    return process.exitCode == 0;
  }

  @override
  Future<bool> killApp(String executablePath, covariant AndroidApk app) async {
    var spawn = await Process.run(
      executablePath,
      ['-s', identifier, 'shell', 'am', 'force-stop', app.id],
    );

    var exitCode = await spawn.exitCode;

    if (exitCode != 0) throw 'Failed to kill ${app.id} on $identifier';
    return true;
  }

  @override
  Future<bool> pressHomeButton(String executablePath) async {
    var processResult = await Process.run(executablePath,
        ['-s', identifier, 'shell', 'input', 'keyevent', 'KEYCODE_HOME']);

    if (processResult.exitCode != 0)
      throw 'Failed to press home button on $identifier';
    return true;
  }

  @override
  String get platform => ksJsonValueDevicePlatformAndroid;

  @override
  Future<bool> pressBackButton(String executablePath) async {
    var processResult = await Process.run(executablePath,
        ['-s', identifier, 'shell', 'input', 'keyevent', 'KEYCODE_BACK']);

    if (processResult.exitCode != 0)
      throw 'Failed to press back button on $identifier';
    return true;
  }
}

// An iOS device ready to run tests.
class IosDevice extends Device {
  IosDevice(String name, String identifier) : super(name, identifier);

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
  String get platform => ksJsonValueDevicePlatformIosDevice;

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

/// An iOS simulator ready to run tests.
class IOSSimulator extends Device {
  IOSSimulator(String name, String identifier) : super(name, identifier);

  StreamController<Uri?> _uriStreamController = StreamController();

  @override
  bool get isLocalEmulator => true;

  @override
  Future<bool> installApp(String executablePath, covariant IOSApp app) async {
    try {
      var spawn = await ProcessManager().spawn(
          executablePath, ['simctl', 'install', identifier, app.filePath]);
      if (await spawn.exitCode != 0) throw '';
      return true;
    } catch (exception) {
      print(
          'Unable to install ${app.filePath} on $identifier. This is sometimes caused by a malformed plist file:\n$exception');
      return false;
    }
  }

  @override
  Future<DebugSessionInformation> launchAppFromBinary(
      String executablePath, covariant IOSApp app) async {
    try {
      await _listenToLogs(executablePath).catchError((err) {
        print('LOG ERROR');
      });
      final port = await SessionUtils.findUnusedPort();
      final manager = new ProcessManager();
      var spawn = await manager.spawn(executablePath, [
        'simctl',
        'launch',
        identifier,
        app.id,
        '--start-paused',
        '--observatory-port=$port',
        // ...?launchArgs,
      ]).catchError((err) {
        print('SPAWN ERROR');
        print(err);
      });
      final uri = await (_uriStreamController.stream.first as FutureOr<Uri>);
      return DebugSessionInformation(
        debugUrl: uri.toString(),
        localPort: uri.port.toString(),
        remotePort: uri.port.toString(),
      );
    } catch (exception) {
      throw ('Unable to launch on $identifier. This is sometimes caused by a malformed plist file:\n$exception');
    }
  }

  /// Simulates home button press by opening settings app on the simulator
  @override
  Future<bool> pressHomeButton(String executablePath) async {
    try {
      var spawn = await ProcessManager().spawn(executablePath, [
        'simctl',
        'launch',
        identifier,
        'com.apple.Preferences',
      ]);
      if (await spawn.exitCode != 0) throw '';
      return true;
    } catch (exception) {
      print('Unable to pressHomeButton on $identifier. $exception');
      return false;
    }
  }

  StreamSubscription? subscription;
  Timer? timer;
  Future _listenToLogs(String executablePath) async {
    // Future<Process> launchDeviceUnifiedLogging (IOSSimulator device, String appName) async {
    // Make NSPredicate concatenation easier to read.
    String orP(List<String> clauses) => '(${clauses.join(" OR ")})';
    String andP(List<String> clauses) => clauses.join(' AND ');
    String notP(String clause) => 'NOT($clause)';

    final String predicate = andP(<String>[
      'eventType = logEvent',
      // if (appName != null) 'processImagePath ENDSWITH "$appName"',
      // Either from Flutter or Swift (maybe assertion or fatal error) or from the app itself.
      orP(<String>[
        'senderImagePath ENDSWITH "/Flutter"',
        'senderImagePath ENDSWITH "/libswiftCore.dylib"',
        'processImageUUID == senderImageUUID',
      ]),
      // Filter out some messages that clearly aren't related to Flutter.
      notP(
          'eventMessage CONTAINS ": could not find icon for representation -> com.apple."'),
      notP('eventMessage BEGINSWITH "assertion failed: "'),
      notP('eventMessage CONTAINS " libxpc.dylib "'),
    ]);

    final process = await ProcessManager().spawn(executablePath, [
      'simctl',
      'spawn',
      identifier,
      'log',
      'stream',
      // '--style',
      // 'json',
      '--predicate',
      predicate
    ]);

    subscription?.cancel();
    subscription = process.stdout
        .transform<String>(utf8.decoder)
        .transform<String>(const LineSplitter())
        .listen((data) {
      final RegExp r =
          RegExp(r' listening on ((http|//)[a-zA-Z0-9:/=_\-\.\[\]]+)');
      final Match? match = r.firstMatch(data);
      if (match != null) {
        print('URL ${Uri.parse(match[1]!)}');
        _uriStreamController.add(Uri.parse(match[1]!));
        subscription?.cancel();
        process.kill();
        timer?.cancel();
      }
    });
    timer = Timer(Duration(seconds: 10), () {
      print('TIME OUT');
      _uriStreamController.add(null);
      process.kill();
      subscription?.cancel();
    });
  }

  @override
  Future<bool> killApp(String executablePath, covariant IOSApp app) async {
    try {
      var spawn = await ProcessManager()
          .spawn(executablePath, ['simctl', 'terminate', identifier, app.id]);
      if (await spawn.exitCode != 0) throw '';
      return true;
    } catch (exception) {
      throw 'Failed to terminate ${app.id} on $identifier';
    }
  }

  @override
  String get platform => ksJsonValueDevicePlatformIosSimulator;

  @override
  Future<bool> pressBackButton(String executablePath) {
    // TODO: implement pressBackButton
    throw UnimplementedError();
  }
}

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
  static Future<List<Device>> listReady() async {
    ProcessResult result = await Process.run(
      'flutter',
      ['devices'],
    );

    // group 1: name
    // group 2: id
    // group 3: architecture
    // group 4: operating system
    RegExp pattern = RegExp(r'^(.*?)\s*•\s*(.*?)\s*•\s*(.*?)\s*•\s*(.*?)\s*$');

    final devices = <AndroidDevice>[];

    LineSplitter().convert(result.stdout).forEach((line) {
      Iterable<RegExpMatch> matches = pattern.allMatches(line);

      matches.forEach((RegExpMatch match) {
        String identifier =
            match.group(2) ?? "identifier can't be found in $match";
        String name = match.group(1) ?? "name can't be found in $match";
        if (match.group(4)!.toLowerCase().contains('android')) {
          devices.add(AndroidDevice(name, identifier));
        }
      });
    });

    if ((await result.exitCode) != 0)
      throw 'Failed to find android device with `adb devices` exit code $exitCode';

    return devices;
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
    ProcessResult result = await Process.run(
      'flutter',
      ['devices'],
    );

    // group 1: name
    // group 2: id
    // group 3: architecture
    // group 4: operating system
    RegExp pattern = RegExp(r'^(.*?)\s*•\s*(.*?)\s*•\s*(.*?)\s*•\s*(.*?)\s*$');

    final devices = <AndroidDevice>[];

    LineSplitter().convert(result.stdout).forEach((line) {
      Iterable<RegExpMatch> matches = pattern.allMatches(line);

      matches.forEach((RegExpMatch match) {
        String identifier =
            match.group(2) ?? "identifier can't be found in $match";
        String name = match.group(1) ?? "name can't be found in $match";

        devices.add(AndroidDevice(name, identifier));
      });
    });

    if ((await result.exitCode) != 0)
      throw 'Failed to find android device with `adb devices` exit code $exitCode';

    return devices;
  }
}

class _IOSSimulatorDeviceFinder {
  static Future<List<Device>> listReady() async {
    print('iOSDeviceFinder:listDevices');
    const String _xcrunPath = '/usr/bin/xcrun';

    print('iOSDeviceFinder:listDevices - Start process ...');
    var result = await Process.run(
      _xcrunPath,
      [
        'simctl',
        'list',
        '--json',
        'devices',
      ],
    );
    print('iOSDeviceFinder:listDevices - Process complete/');

    int exitCode = result.exitCode;
    String outputResult = result.stdout;

    if (exitCode != 0)
      throw 'Failed to find simulator devices. Exit code $exitCode. \n Output:$outputResult \ Error:${result.stderr}';

    final outputParser = CommandLineOutputParser();

    return outputParser.parseDeviceListing(outputResult);
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
    print('Android device fetch failed: $e');
  }

  if (Platform.isMacOS) {
    try {
      devices.addAll(await _IOSSimulatorDeviceFinder.listReady());
    } catch (e) {
      print('iOS simulators fetch failed: $e');
    }
  }

  return devices;
}

/// Checks if ANDROID_HOME path is set in the system.
String? getAndroidSDKPath() {
  String? sdkPath = Platform.environment['ANDROID_HOME'];
  if (sdkPath == null) {
    print('The ANDROID_HOME environment variable is not set');
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
      String executablePath, covariant AndroidApk app) async {
    print('installApp');
    return true;
  }

  Future<void> grantPermissions(String executablePath, AndroidApk app) async {
    print('Fetching required permissions');
  }

  @override
  Future<DebugSessionInformation> launchAppFromBinary(
      String executablePath, covariant AndroidApk app) async {
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
}
