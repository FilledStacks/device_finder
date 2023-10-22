import 'dart:io';

import 'package:device_finder/application_package.dart';
import 'package:device_finder/src/session_utils.dart';

import 'device.dart';

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
    try {
      await clearAppData(executablePath, app);

      final spawn = await Process.run(
        executablePath,
        ['-s', identifier, 'install', '-r', app.filePath],
      );

      stdout.writeln('🤖 ${spawn.stdout}');

      // Previous app data is retained using the above command
      // We need to clear the data manually for a fresh install
      await grantPermissions(executablePath, app);

      if (spawn.exitCode != 0) {
        stdout.writeln('🤖 ${spawn.stderr}');
        throw 'Failed to install ${app.filePath} on $identifier cause of ${spawn.stderr}';
      }

      return true;
    } catch (e, s) {
      stdout.writeln('🔴 Error:${e.toString()} StackTrace:\n$s');
      return false;
    }
  }

  Future<void> grantPermissions(String executablePath, AndroidApk app) async {
    stdout.writeln('🤖 Fetching required permissions...');

    final permissions = await app.getPermissions();

    for (String? permission in permissions) {
      await Process.run(
        executablePath,
        ['-s', identifier, 'shell', 'pm', 'grant', app.id, permission!],
        // ignore: invalid_return_type_for_catch_error
      ).then((result) {
        stdout.writeln('🤖 ${result.stdout}');

        if (result.exitCode != 0) {
          stdout.writeln('🤖 ${result.stderr}');
        }
      }).catchError((e) {
        stdout.writeln('🔴 Unable to grant permission: $permission');
      });
    }
  }

  @override
  Future<DebugSessionInformation> launchAppFromBinary(
    String executablePath,
    covariant AndroidApk app,
  ) async {
    stdout.writeln('🤖 executablePath:$executablePath app:$app');

    final spawn = await Process.run(executablePath, [
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

    stdout.writeln('🤖 ${spawn.stdout}');

    if (spawn.exitCode != 0) {
      stdout.writeln('🤖 ${spawn.stderr}');
      throw 'Failed to launch ${app.launchActivity} on $identifier. You might have given an incorrect Activity or package name.';
    }

    final logProcResults = await Process.run(executablePath, [
      '-s',
      identifier,
      'logcat',
      '-d',
      'flutter:I', // Take those with flutter tag in info or higher
      '*:S', // Ignore all others
      // '-T',
      // '$time' // To get the most recent debugUrl
    ]);

    stdout.writeln('🤖 ${logProcResults.stdout}');

    if (logProcResults.exitCode != 0) {
      stdout.writeln('🤖 ${logProcResults.stderr}');
      throw 'Logcat failed to run with error message: ${logProcResults.stderr}';
    }

    final debugInformation = await SessionUtils.getDebugSession(
      adbPath: executablePath,
      data: logProcResults.stdout as String,
      identifier: identifier,
      isAndroidDevice: true,
    );

    if (debugInformation == null) {
      throw 'Output from logcat does not contain debug url: ${logProcResults.stderr}';
    }

    return debugInformation;
  }

  Future<bool> clearAppData(
    String executablePath,
    covariant AndroidApk app,
  ) async {
    final result = await Process.run(
      executablePath,
      ['-s', identifier, 'uninstall', app.id],
    );

    stdout.writeln('🤖 ${result.stdout}');
    if (result.exitCode != 0) {
      stdout.writeln('🤖 ${result.stderr}');
      return false;
    }

    return true;
  }

  @override
  Future<bool> killApp(String executablePath, covariant AndroidApk app) async {
    final result = await Process.run(
      executablePath,
      ['-s', identifier, 'shell', 'am', 'force-stop', app.id],
    );

    stdout.writeln('🤖 ${result.stdout}');
    if (result.exitCode != 0) {
      stdout.writeln('🤖 ${result.stderr}');
      throw 'Failed to kill ${app.id} on $identifier';
    }

    return true;
  }

  @override
  Future<bool> pressHomeButton(String executablePath) async {
    final result = await Process.run(
      executablePath,
      ['-s', identifier, 'shell', 'input', 'keyevent', 'KEYCODE_HOME'],
    );

    stdout.writeln('🤖 ${result.stdout}');
    if (result.exitCode != 0) {
      stdout.writeln('🤖 ${result.stderr}');
      throw 'Failed to press home button on $identifier';
    }

    return true;
  }

  @override
  String get platform => ksJsonValueDevicePlatformAndroid;

  @override
  Future<bool> pressBackButton(String executablePath) async {
    final result = await Process.run(
      executablePath,
      ['-s', identifier, 'shell', 'input', 'keyevent', 'KEYCODE_BACK'],
    );

    stdout.writeln('🤖 ${result.stdout}');
    if (result.exitCode != 0) {
      stdout.writeln('🤖 ${result.stderr}');
      throw 'Failed to press back button on $identifier';
    }

    return true;
  }
}
