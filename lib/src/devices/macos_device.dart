// An iOS device ready to run tests.
import 'dart:async';

import 'package:device_finder/application_package.dart';

import 'device.dart';

class MacOsDevice extends Device {
  MacOsDevice(String name, String identifier) : super(name, identifier);

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
  String get platform => ksJsonValueDevicePlatformMacOS;

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

  @override
  Future<bool> pressEnterButton(String executablePath) {
    // TODO: implement pressEnterButton
    throw UnimplementedError();
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
