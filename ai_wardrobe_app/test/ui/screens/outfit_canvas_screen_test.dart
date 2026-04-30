import 'package:ai_wardrobe_app/l10n/app_strings_provider.dart';
import 'package:ai_wardrobe_app/ui/screens/outfit_canvas_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _testApp(Widget child) {
  return MaterialApp(
    home: AppStringsProvider(locale: const Locale('en'), child: child),
  );
}

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('empty wardrobe does not show demo garments in the picker', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp(const OutfitCanvasScreen()));
    await tester.pumpAndSettle();

    expect(find.text('0 wardrobe items loaded'), findsOneWidget);
    expect(find.text('Ivory Turtleneck'), findsNothing);
    expect(find.text('Relaxed Oxford Shirt'), findsNothing);
    expect(find.text('Dark Leather Jacket'), findsNothing);

    final upperHotspot = find.byTooltip('Select upper body garments');
    await tester.ensureVisible(upperHotspot);
    await _pumpUi(tester);
    await tester.tap(upperHotspot, warnIfMissed: false);
    await _pumpUi(tester);

    expect(find.text('Upper Body Picker'), findsOneWidget);
    expect(find.text('No wardrobe clothing in this zone yet.'), findsOneWidget);
    expect(find.text('Wear'), findsNothing);
    expect(find.text('Garment Details'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'generated preview stays disabled when no wardrobe garment is selected',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_testApp(const OutfitCanvasScreen()));
      await tester.pumpAndSettle();

      final previewButton = find.text('Generate Preview');
      await tester.ensureVisible(previewButton);
      await _pumpUi(tester);
      expect(previewButton, findsOneWidget);
      await tester.tap(previewButton);
      await _pumpUi(tester);

      expect(find.text('Generated Preview'), findsNothing);
      expect(find.text('No wardrobe clothing selected.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty wardrobe keeps the reference photo without ghost items', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testApp(const OutfitCanvasScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Reference Photo'), findsOneWidget);
    expect(find.text('Current Styling Map'), findsOneWidget);
    expect(find.text('No item selected yet.'), findsNWidgets(4));
    expect(find.text('L3'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
