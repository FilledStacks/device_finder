import 'dart:convert';
import 'dart:io';

abstract class ApplicationPackage {
  ApplicationPackage({
    required this.id,
    required this.filePath,
  });

  /// Package ID from the Android Manifest or equivalent.
  final String id;

  final String filePath;

  @override
  String toString() {
    return 'ApplicationPackage: id: $id, filePath:$filePath';
  }

  Map<String, dynamic> toJson();

  factory ApplicationPackage.fromJson(Map<String, dynamic> json) {
    // Only Android apps have a launch activity
    return json["launchActivity"] != null
        ? AndroidApk.fromJson(json)
        : IOSApp.fromJson(json);
  }
}

class AndroidApk extends ApplicationPackage {
  AndroidApk({
    required String id,
    required String filePath,
    required this.launchActivity,
    required this.aaptPath,
  }) : super(id: id, filePath: filePath);

  /// The path to the activity that should be launched.
  final String launchActivity;

  /// The path to the aapt tool
  final String? aaptPath;

  Future<List<String?>> getPermissions() async {
    try {
      final result =
          await Process.run(aaptPath!, ['d', 'permissions', filePath]);
      final data = result.stdout.toString();
      RegExp permissionPattern =
          RegExp(r"(android\.permission\..*)\'", multiLine: true);
      final matches = permissionPattern
          .allMatches(data)
          .map((match) => match.group(1))
          .toList();

      if (matches.isEmpty) {
        print('No permissions found');
        return [];
      }
      print('Permissions Found - $matches');

      return matches;
    } catch (err) {
      return [];
    }
  }

  @override
  String toString() {
    return 'AndroidApk: id: $id, filePath:$filePath, launchActivity: $launchActivity';
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "filePath": filePath,
      "launchActivity": launchActivity,
    };
  }

  factory AndroidApk.fromJson(Map<String, dynamic> json) {
    return AndroidApk(
      id: json["id"],
      filePath: json["filePath"],
      launchActivity: json["launchActivity"],
      aaptPath: json["aaptPath"],
    );
  }

  /// Creates a new AndroidApk from an existing APK.
  static Future<AndroidApk?> fromApk(String aaptPath, String apkPath) async {
    try {
      final result = await Process.run(aaptPath, ['dump', 'badging', apkPath]);
      final data = result.stdout.toString();
      final startBefore = 'package: name=\'';
      final endBefore = '\' versionCode=\'';
      var packageName = data.substring(
          data.indexOf(startBefore) + startBefore.length,
          data.indexOf(endBefore));

      final RegExp activityNameRegex =
          RegExp(r"launchable-activity: name=\'(.*?)\'");
      String? activityName = activityNameRegex.firstMatch(data)!.group(1);

      if (activityName == null) {
        print('Unable to read activity name from $apkPath.');
        return null;
      }

      print(
          'Found package name - $packageName | Launchable Activity Name - $activityName');

      return AndroidApk(
        id: packageName,
        filePath: apkPath,
        launchActivity: activityName,
        aaptPath: aaptPath,
      );
    } on ProcessException catch (error) {
      print('Failed to extract manifest data from APK: $error.');
      return null;
    }
  }
}

class IOSApp extends ApplicationPackage {
  IOSApp({
    required String id,
    required String filePath,
  }) : super(id: id, filePath: filePath);

  @override
  String toString() {
    return 'IOSApp: id: $id, filePath:$filePath';
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "filePath": filePath,
    };
  }

  factory IOSApp.fromJson(Map<String, dynamic> json) {
    return IOSApp(
      id: json["id"],
      filePath: json["filePath"],
    );
  }

  /// Creates a new IOSApp from an existing .app build
  static Future<IOSApp?> fromApp(
    String plutilPath,
    String appPath,
  ) async {
    try {
      final result = await Process.run(
        plutilPath,
        ['-convert', 'json', '-o', '-', '$appPath/Info.plist'],
      );

      final data = result.stdout.toString();
      Map info = json.decode(data);
      final String? packageName = info['CFBundleIdentifier'];

      if (packageName == null) {
        print('Unable to read info from $appPath.');
        return null;
      }

      print('Found package name $packageName');

      return IOSApp(
        id: packageName,
        filePath: appPath,
      );
    } on ProcessException catch (error) {
      print('Failed to extract Info.plist data from the app: $error.');
      return null;
    }
  }
}
