import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Types [value] into every stack's filled-trays field: the blind manual count
/// starts empty and refuses to save while a reachable stack is uncounted.
Future<void> countEveryStack(WidgetTester tester, [String value = '20']) async {
  final fields = find.byWidgetPredicate((w) {
    final key = w.key;
    return key is ValueKey<String> && key.value.startsWith('filled-');
  });
  for (final element in fields.evaluate().toList()) {
    await tester.enterText(find.byWidget(element.widget), value);
  }
}
