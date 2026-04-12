import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

class LocalClothingService {
  static const String _keyPrefix = 'local_clothing_item_';
  static const String _itemsListKey = 'local_clothing_items_list';

  static Future<String> saveSimplifiedItem({
    required Uint8List frontImageBytes,
    Uint8List? backImageBytes,
    String? name,
    String? description,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final itemId = 'local_${DateTime.now().millisecondsSinceEpoch}';

    final itemData = {
      'id': itemId,
      'name': name ?? 'Untitled Item',
      'description': description ?? '',
      'source': 'OWNED',
      'isSimplified': true,
      'frontImageBase64': base64Encode(frontImageBytes),
      'backImageBase64':
          backImageBytes != null ? base64Encode(backImageBytes) : null,
      'createdAt': DateTime.now().toIso8601String(),
      'finalTags': <Map<String, String>>[],
    };

    await prefs.setString('$_keyPrefix$itemId', jsonEncode(itemData));

    final itemsList = prefs.getStringList(_itemsListKey) ?? <String>[];
    itemsList.add(itemId);
    await prefs.setStringList(_itemsListKey, itemsList);

    return itemId;
  }

  static Future<Map<String, dynamic>?> getItem(String itemId) async {
    final prefs = await SharedPreferences.getInstance();
    final itemJson = prefs.getString('$_keyPrefix$itemId');
    if (itemJson == null) return null;

    final itemData = jsonDecode(itemJson) as Map<String, dynamic>;
    final frontBase64 = itemData['frontImageBase64'] as String;
    final backBase64 = itemData['backImageBase64'] as String?;

    return {
      ...itemData,
      'images': {
        'originalFrontUrl': 'data:image/jpeg;base64,$frontBase64',
        'processedFrontUrl': 'data:image/jpeg;base64,$frontBase64',
        if (backBase64 != null) 'originalBackUrl': 'data:image/jpeg;base64,$backBase64',
        if (backBase64 != null) 'processedBackUrl': 'data:image/jpeg;base64,$backBase64',
      },
    };
  }

  static Future<List<Map<String, dynamic>>> listItems() async {
    final prefs = await SharedPreferences.getInstance();
    final itemsList = prefs.getStringList(_itemsListKey) ?? <String>[];

    final items = <Map<String, dynamic>>[];
    for (final itemId in itemsList) {
      final item = await getItem(itemId);
      if (item != null) {
        items.add(item);
      }
    }

    items.sort((a, b) {
      final aDate = DateTime.parse(a['createdAt'] as String);
      final bDate = DateTime.parse(b['createdAt'] as String);
      return bDate.compareTo(aDate);
    });

    return items;
  }

  static Future<void> deleteItem(String itemId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_keyPrefix$itemId');

    final itemsList = prefs.getStringList(_itemsListKey) ?? <String>[];
    itemsList.remove(itemId);
    await prefs.setStringList(_itemsListKey, itemsList);
  }

  static bool isLocalItem(String itemId) {
    return itemId.startsWith('local_');
  }
}
