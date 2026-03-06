import 'package:ai_wardrobe_app/ui/screens/outfit_canvas_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('picker separates garment details from wear controls', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: OutfitCanvasScreen()));
    await tester.pumpAndSettle();

    final upperHotspot = find.byTooltip('Select upper body garments');
    await tester.ensureVisible(upperHotspot);
    await tester.pumpAndSettle();
    await tester.tap(upperHotspot, warnIfMissed: false);
    await tester.pumpAndSettle();

    final oxfordTitle = find.text('Relaxed Oxford Shirt');
    await tester.ensureVisible(oxfordTitle);
    await tester.pumpAndSettle();
    await tester.tap(oxfordTitle, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Garment Details'), findsOneWidget);
    expect(find.text('Wear on Layer 1'), findsNothing);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    final wearButton = find.text('Wear').first;
    await tester.ensureVisible(wearButton);
    await tester.pumpAndSettle();
    await tester.tap(wearButton);
    await tester.pumpAndSettle();

    expect(find.text('Choose a Layer'), findsOneWidget);
    expect(find.text('Wear on Layer 1'), findsOneWidget);
    expect(find.text('Garment Details'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'generated preview is opened from the bottom action and stays responsive',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: OutfitCanvasScreen()));
      await tester.pumpAndSettle();

      final headHotspot = find.byTooltip('Select head garments');
      await tester.ensureVisible(headHotspot);
      await tester.pumpAndSettle();
      await tester.tap(headHotspot, warnIfMissed: false);
      await tester.pumpAndSettle();

      final wearButton = find.text('Wear').first;
      await tester.ensureVisible(wearButton);
      await tester.pumpAndSettle();
      await tester.tap(wearButton);
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(12, 12));
      await tester.pumpAndSettle();

      final previewButton = find.text('Generate Preview');
      await tester.ensureVisible(previewButton);
      await tester.pumpAndSettle();
      expect(previewButton, findsOneWidget);
      await tester.tap(previewButton);
      await tester.pumpAndSettle();

      expect(find.text('Generated Preview'), findsOneWidget);
      expect(find.text('Save to Gallery'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('three upper-body layers do not overflow on the canvas', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: OutfitCanvasScreen()));
    await tester.pumpAndSettle();

    final upperHotspot = find.byTooltip('Select upper body garments');
    await tester.ensureVisible(upperHotspot);
    await tester.pumpAndSettle();
    await tester.tap(upperHotspot, warnIfMissed: false);
    await tester.pumpAndSettle();

    Future<void> wearLayer(String title, int layer) async {
      final titleFinder = find.text(title);
      await tester.ensureVisible(titleFinder);
      await tester.pumpAndSettle();
      final cardFinder = find.ancestor(
        of: titleFinder,
        matching: find.byType(InkWell),
      );
      final wearButton = find.descendant(
        of: cardFinder.first,
        matching: find.widgetWithText(FilledButton, 'Wear'),
      );
      await tester.tap(wearButton.first);
      await tester.pumpAndSettle();
      final layerOption = find.text('Wear on Layer $layer');
      await tester.ensureVisible(layerOption);
      await tester.pumpAndSettle();
      await tester.tap(layerOption, warnIfMissed: false);
      await tester.pumpAndSettle();
    }

    await wearLayer('Ivory Turtleneck', 1);
    await wearLayer('Relaxed Oxford Shirt', 2);
    await wearLayer('Dark Leather Jacket', 3);

    await tester.tapAt(const Offset(12, 12));
    await tester.pumpAndSettle();

    expect(find.text('L3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
