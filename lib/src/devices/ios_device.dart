// An iOS device ready to run tests.
import 'dart:async';

import '../../application_package.dart';
import 'device.dart';

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
