import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_finder/application_package.dart';
import 'package:device_finder/src/devices/device.dart';
import 'package:device_finder/src/session_utils.dart';
import 'package:io/io.dart';

/// An iOS simulator ready to run tests.
class IOSSimulator extends Device {
  IOSSimulator(String name, String identifier) : super(name, identifier);

  StreamController<Uri?> _uriStreamController = StreamController();

  @override
  bool get isLocalEmulator => true;

  @override
  Future<bool> installApp(String executablePath, covariant IOSApp app) async {
    try {
      final result = await ProcessManager().spawn(
        executablePath,
        ['simctl', 'install', identifier, app.filePath],
      );

      stdout.writeln('🤖 ${result.stdout}');
      if (result.exitCode != 0) {
        stdout.writeln('🤖 ${result.stderr}');
        throw 'Failed to install app';
      }

      return true;
    } catch (e, s) {
      stdout.writeln(
        '🔴 Unable to install ${app.filePath} on $identifier. This is sometimes caused by a malformed plist file:\n$e\nStackTrace:$s',
      );
      return false;
    }
  }

  @override
  Future<DebugSessionInformation> launchAppFromBinary(
    String executablePath,
    covariant IOSApp app,
  ) async {
    try {
      await _listenToLogs(executablePath).catchError((err) {
        stdout.writeln('🤖 LOG ERROR');
      });
      final port = await SessionUtils.findUnusedPort();
      final manager = ProcessManager();
      await manager.spawn(executablePath, [
        'simctl',
        'launch',
        identifier,
        app.id,
        '--start-paused',
        '--observatory-port=$port',
        // ...?launchArgs,
        // ignore: body_might_complete_normally_catch_error
      ]).then((result) {
        stdout.writeln('🤖 ${result.stdout}');
        if (result.exitCode != 0) {
          stdout.writeln('🤖 ${result.stderr}');
        }
      }).catchError((e) {
        stdout.writeln('🔴 SPAWN ERROR:${e.toString()}');
      });

      final uri = await (_uriStreamController.stream.first as FutureOr<Uri>);

      return DebugSessionInformation(
        debugUrl: uri.toString(),
        localPort: uri.port.toString(),
        remotePort: uri.port.toString(),
      );
    } catch (e) {
      throw ('Unable to launch on $identifier. This is sometimes caused by a malformed plist file:\n${e.toString()}');
    }
  }

  /// Simulates home button press by opening settings app on the simulator
  @override
  Future<bool> pressHomeButton(String executablePath) async {
    try {
      final spawn = await ProcessManager().spawn(executablePath, [
        'simctl',
        'launch',
        identifier,
        'com.apple.Preferences',
      ]);

      stdout.writeln('🤖 ${spawn.stdout}');
      if (await spawn.exitCode != 0) {
        stdout.writeln('🤖 ${spawn.stderr}');
        throw 'Could not simulate home button press';
      }

      return true;
    } catch (e, s) {
      stdout.writeln(
        '🔴 Unable to pressHomeButton on $identifier. ${e.toString()}. StackTrace:\n$s',
      );
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

    if (await process.exitCode != 0) {
      stdout.writeln('🤖 ${process.stderr}');
    }

    subscription?.cancel();
    subscription = process.stdout
        .transform<String>(utf8.decoder)
        .transform<String>(const LineSplitter())
        .listen((data) {
      final RegExp r = RegExp(
        r' listening on ((http|//)[a-zA-Z0-9:/=_\-\.\[\]]+)',
      );
      final Match? match = r.firstMatch(data);
      if (match != null) {
        stdout.writeln('🤖 URL ${Uri.parse(match[1]!)}');
        _uriStreamController.add(Uri.parse(match[1]!));
        subscription?.cancel();
        process.kill();
        timer?.cancel();
      }
    });

    timer = Timer(Duration(seconds: 10), () {
      stdout.writeln('🤖 TIME OUT');
      _uriStreamController.add(null);
      process.kill();
      subscription?.cancel();
    });
  }

  @override
  Future<bool> killApp(String executablePath, covariant IOSApp app) async {
    try {
      final spawn = await ProcessManager()
          .spawn(executablePath, ['simctl', 'terminate', identifier, app.id]);

      stdout.writeln('🤖 ${spawn.stdout}');

      if (await spawn.exitCode != 0) {
        stdout.writeln('🔴 ${spawn.stderr}');
        throw 'App could not be killed';
      }

      return true;
    } catch (e) {
      stdout.writeln('🔴 ${e.toString()}');
      throw 'Failed to terminate ${app.id} on $identifier. ${e.toString()}';
    }
  }

  @override
  String get platform => ksJsonValueDevicePlatformIosSimulator;

  @override
  Future<bool> pressBackButton(String executablePath) {
    return Future.value(true);
  }

  @override
  Future<bool> pressEnterButton(String executablePath) {
    return Future.value(true);
  }

  @override
  Future<bool> performDrag(
      {required String executablePath,
      required double startX,
      required double startY,
      required double endX,
      required double endY}) {
    // TODO: implement performDrag
    throw UnimplementedError();
  }
}
