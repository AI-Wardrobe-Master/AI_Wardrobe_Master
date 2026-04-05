// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:ai_wardrobe_app/services/auth_service.dart';
import 'package:ai_wardrobe_app/services/wardrobe_service.dart';
import 'package:ai_wardrobe_app/services/reference_photo_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_wardrobe_app/main.dart';

void main() {
  setUp(() {
    AuthService.resetForTest();
    WardrobeService.resetDemoDataForTest();
    ReferencePhotoService.resetForTest();
  });

  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const WardrobeApp());
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();

    expect(find.text('Your wardrobe'), findsOneWidget);
    expect(find.text('Demo Closet'), findsWidgets);
  });

  testWidgets('Offline demo opens without backend', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const WardrobeApp());
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();

    expect(find.text('Your wardrobe'), findsOneWidget);
    expect(find.text('Demo Closet'), findsWidgets);
    expect(find.text('Relaxed Oxford Shirt'), findsWidgets);
  });
}
