import 'package:device_finder/src/command_line_output_parser.dart';
import 'package:test/test.dart';

import 'test_data.dart';

void main() {
  group('CommandLineOutputParserTest -', () {
    group('parseDeviceListing -', () {
      test(
          'When given the test output with simulator with iPhone 12 Pro Max simulator booted, should return iPhone 12 Pro Max',
          () {
        final parser = CommandLineOutputParser();
        final result = parser.parseDeviceListing(OutputWithiPhone12Booted);
        expect(result.first.name, 'iPhone 12 Pro Max');
      });

      test(
          'When given the test output with NO simulator booted, should return empty list',
          () {
        final parser = CommandLineOutputParser();
        final result = parser.parseDeviceListing(OutputWithNoneBooted);
        expect(result.isEmpty, isTrue);
      });
    });
  });
}
