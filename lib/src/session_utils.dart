import 'dart:io';

import 'devices/device.dart';

class SessionUtils {
  static Future<DebugSessionInformation?> getDebugSession({
    required String adbPath,
    required String data,
    required String identifier,
    required bool isAndroidDevice,
    bool verbose = false,
  }) async {
    // Grab the first http/https url
    final debugUrlMatcher = new RegExp(
      r'(http|https)://([\w_-]+(?:(?:\.[\w_-]+)+))([\w.,@?^=%&:/~+#-]*[\w@?^=%&/~+#-])',
    );
    final match = debugUrlMatcher.allMatches(data).first;
    String debugUrl = data.substring(match.start, match.end);

    if (verbose) {
      stdout.writeln('🤖 Found debugUrl at $debugUrl');
    }

    // The debugUrl is local to the device running the app. This means that this machine running
    // sweetcore is unaware of this url and its port. FlutterDriver will be unable to connect to the app.
    // To solve this, we need to choose any local port F do port forwarding so that all connections
    // and requests to the local port are relayed to the remote port in debugUrl.
    // The local port is then the one we pass to FlutterDriver

    final localPort = await findUnusedPort();
    final portMatcher = new RegExp(r':[0-9]+');
    final portMatch = portMatcher.allMatches(debugUrl).first;
    final remotePort = debugUrl.substring(portMatch.start + 1, portMatch.end);

    if (verbose) {
      stdout.writeln(
        '🤖 Forwarding local port $localPort to remote port $remotePort',
      );
    }

    try {
      if (isAndroidDevice) {
        final process = await Process.run(adbPath, [
          '-s',
          identifier,
          'forward',
          'tcp:$localPort',
          'tcp:$remotePort',
        ]);

        if (verbose) {
          stdout.writeln('${process.stdout}');
        }

        if (process.exitCode != 0 && verbose) {
          stdout.writeln('🔴 ${process.stderr}');
        }
      }
    } catch (e, s) {
      stdout.writeln('🔴 Error:${e.toString()} StackTrace:\n$s');
    }

    return DebugSessionInformation(
      debugUrl: debugUrl,
      localPort: localPort,
      remotePort: remotePort,
    );
  }

  static Future<String> findUnusedPort() {
    return ServerSocket.bind(InternetAddress.anyIPv4, 0).then((socket) {
      var port = socket.port;
      socket.close();
      return port.toString();
    });
  }
}
