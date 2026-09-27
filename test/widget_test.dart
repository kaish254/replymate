// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crushreply/main.dart';

void main() {
  testWidgets('user can generate and copy replies from a pasted message', (tester) async {
    SharedPreferences.setMockInitialValues({});
    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
    await tester.pumpWidget(const CrushReplyApp());

    expect(find.text('CrushReply'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Why did you disappear? 😂');
    await tester.tap(find.text('Generate replies').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate replies').last);
    await tester.pumpAndSettle();

    expect(find.text('Made for your conversation'), findsOneWidget);
    expect(find.text('I was hoping you’d notice I was gone'), findsOneWidget);

    await tester.ensureVisible(find.text('Copy').first);
    await tester.tap(find.text('Copy').first);
    await tester.pumpAndSettle();
    expect(copiedText, 'I was hoping you’d notice I was gone');
  });
}
