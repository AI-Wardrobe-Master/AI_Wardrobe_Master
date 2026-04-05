import 'package:ai_wardrobe_app/l10n/app_strings_provider.dart';
import 'package:ai_wardrobe_app/models/wardrobe.dart';
import 'package:ai_wardrobe_app/services/outfit_collection_service.dart';
import 'package:ai_wardrobe_app/ui/screens/outfit_canvas_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
    await OutfitCollectionService.resetForTest();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required Size size,
    required List<WardrobeItemWithClothing> catalogItems,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: AppStringsProvider(
          locale: const Locale('en'),
          child: OutfitCanvasScreen(
            catalogItems: catalogItems,
            catalogWardrobeName: 'Test Wardrobe',
            openDetailOverride: (context, clothingItemId) async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    body: Center(child: Text('Detail $clothingItemId')),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('picker card opens linked clothing detail page', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      size: const Size(360, 740),
      catalogItems: _detailCatalogItems,
    );

    final upperPickerButton = find.byTooltip('Open upper body picker');
    await tester.ensureVisible(upperPickerButton);
    await tester.tap(upperPickerButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    final oxfordTitle = find.text('Relaxed Oxford Shirt');
    expect(oxfordTitle, findsOneWidget);
    final oxfordCard = find.ancestor(
      of: oxfordTitle,
      matching: find.byType(InkWell),
    );
    await tester.tap(oxfordCard.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text('Detail upper_oxford'), findsOneWidget);
    expect(find.text('Choose a Layer'), findsNothing);

    Navigator.of(tester.element(find.text('Detail upper_oxford'))).pop();
    await tester.pumpAndSettle();

    expect(find.text('Detail upper_oxford'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'wear button still opens layer picker and preview modal remains responsive',
    (WidgetTester tester) async {
      await pumpScreen(
        tester,
        size: const Size(320, 640),
        catalogItems: _previewCatalogItems,
      );

      final headPickerButton = find.byTooltip('Open head picker');
      await tester.ensureVisible(headPickerButton);
      await tester.tap(headPickerButton, warnIfMissed: false);
      await tester.pumpAndSettle();

      final wearButton = find.widgetWithText(FilledButton, 'Wear').first;
      await tester.ensureVisible(wearButton);
      await tester.tap(wearButton, warnIfMissed: false);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      final previewButton = find.text('Generate Preview');
      await tester.ensureVisible(previewButton);
      await tester.tap(previewButton);
      await tester.pumpAndSettle();

      expect(find.text('Generated Preview'), findsOneWidget);
      expect(find.text('Save to Gallery'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('preview flow can export a shareable outfit collection', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      size: const Size(360, 740),
      catalogItems: _previewCatalogItems,
    );

    final headPickerButton = find.byTooltip('Open head picker');
    await tester.ensureVisible(headPickerButton);
    await tester.tap(headPickerButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    final wearButton = find.widgetWithText(FilledButton, 'Wear').first;
    await tester.ensureVisible(wearButton);
    await tester.tap(wearButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    final previewButton = find.text('Generate Preview');
    await tester.ensureVisible(previewButton);
    await tester.tap(previewButton);
    await tester.pumpAndSettle();

    final exportButton = find.text('Export to Collection');
    await tester.ensureVisible(exportButton);
    await tester.tap(exportButton);
    await tester.pumpAndSettle();

    expect(find.text('Export to Outfit Collection'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField).at(1),
      'smart casual, office, spring edit',
    );
    final addTagButton = find.widgetWithText(FilledButton, 'Add');
    await tester.ensureVisible(addTagButton);
    await tester.tap(addTagButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('smart casual'), findsOneWidget);
    expect(find.text('office'), findsOneWidget);
    expect(find.text('spring edit'), findsOneWidget);

    final saveCollection = find
        .widgetWithText(FilledButton, 'Save Collection')
        .last;
    await tester.ensureVisible(saveCollection);
    await tester.tap(saveCollection, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(OutfitCollectionService.listenable.value.length, 1);
    expect(
      OutfitCollectionService.listenable.value.first.tags,
      containsAll(<String>['smart casual', 'office', 'spring edit']),
    );
    expect(
      OutfitCollectionService.listenable.value.first.items.first.title,
      'Wool Beret',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('three upper-body layers do not overflow on the canvas', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      size: const Size(360, 740),
      catalogItems: _layeringCatalogItems,
    );

    final upperPickerButton = find.byTooltip('Open upper body picker');
    await tester.ensureVisible(upperPickerButton);
    await tester.tap(upperPickerButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    Future<void> wearLayer(String title, int layer) async {
      final pickerList = find.byType(ListView).last;
      if (find.text(title).evaluate().isEmpty) {
        await tester.drag(pickerList, const Offset(0, -220));
        await tester.pumpAndSettle();
      }

      final titleFinder = find.text(title);
      expect(titleFinder, findsOneWidget);
      final cardFinder = find.ancestor(
        of: titleFinder,
        matching: find.byType(InkWell),
      );
      final wearButton = find.descendant(
        of: cardFinder.first,
        matching: find.widgetWithText(FilledButton, 'Wear'),
      );
      await tester.ensureVisible(wearButton.first);
      await tester.pumpAndSettle();
      await tester.tap(wearButton.first, warnIfMissed: false);
      await tester.pumpAndSettle();
      final layerOption = find.text('Wear on Layer $layer');
      await tester.ensureVisible(layerOption);
      await tester.tap(layerOption, warnIfMissed: false);
      await tester.pumpAndSettle();
    }

    await wearLayer('Dark Leather Jacket', 3);
    await wearLayer('Ivory Turtleneck', 1);
    await wearLayer('Relaxed Oxford Shirt', 2);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(find.text('L3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _detailCatalogItems = <WardrobeItemWithClothing>[
  WardrobeItemWithClothing(
    id: 'wardrobe-item-upper-2',
    wardrobeId: 'wardrobe-1',
    clothingItemId: 'upper_oxford',
    clothingItem: ClothingItemBrief(
      id: 'upper_oxford',
      name: 'Relaxed Oxford Shirt',
      source: 'OWNED',
      finalTags: [
        {'key': 'category', 'value': 'shirt'},
        {'key': 'material', 'value': 'Cotton poplin'},
      ],
    ),
  ),
];

const _previewCatalogItems = <WardrobeItemWithClothing>[
  WardrobeItemWithClothing(
    id: 'wardrobe-item-head',
    wardrobeId: 'wardrobe-1',
    clothingItemId: 'head_beret',
    clothingItem: ClothingItemBrief(
      id: 'head_beret',
      name: 'Wool Beret',
      source: 'OWNED',
      finalTags: [
        {'key': 'category', 'value': 'hat'},
        {'key': 'material', 'value': 'Merino wool blend'},
      ],
    ),
  ),
];

const _layeringCatalogItems = <WardrobeItemWithClothing>[
  WardrobeItemWithClothing(
    id: 'wardrobe-item-upper-1',
    wardrobeId: 'wardrobe-1',
    clothingItemId: 'upper_turtleneck',
    clothingItem: ClothingItemBrief(
      id: 'upper_turtleneck',
      name: 'Ivory Turtleneck',
      source: 'OWNED',
      finalTags: [
        {'key': 'category', 'value': 'longsleeve'},
        {'key': 'material', 'value': 'Fine rib knit'},
      ],
    ),
  ),
  WardrobeItemWithClothing(
    id: 'wardrobe-item-upper-2',
    wardrobeId: 'wardrobe-1',
    clothingItemId: 'upper_oxford',
    clothingItem: ClothingItemBrief(
      id: 'upper_oxford',
      name: 'Relaxed Oxford Shirt',
      source: 'OWNED',
      finalTags: [
        {'key': 'category', 'value': 'shirt'},
        {'key': 'material', 'value': 'Cotton poplin'},
      ],
    ),
  ),
  WardrobeItemWithClothing(
    id: 'wardrobe-item-upper-3',
    wardrobeId: 'wardrobe-1',
    clothingItemId: 'upper_jacket',
    clothingItem: ClothingItemBrief(
      id: 'upper_jacket',
      name: 'Dark Leather Jacket',
      source: 'IMPORTED',
      finalTags: [
        {'key': 'category', 'value': 'jacket'},
        {'key': 'material', 'value': 'Washed leather'},
      ],
    ),
  ),
];
