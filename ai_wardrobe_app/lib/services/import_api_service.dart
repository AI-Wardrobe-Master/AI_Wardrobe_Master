import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/import_history.dart';
import 'api_config.dart';
import 'card_pack_api_service.dart';
import 'creator_api_service.dart';
import 'local_card_pack_service.dart';
import 'local_clothing_service.dart';
import 'clothing_api_service.dart';
import 'local_wardrobe_service.dart';

class ImportApiService {
  static final _dio = buildApiDio();

  static const String _historyIdsKey = 'local_import_history_ids';
  static const String _historyPrefix = 'local_import_history_';

  static Future<Map<String, dynamic>> importCardPack(String cardPackId) async {
    try {
      final resp = await _dio.post(
        '/imports/card-pack',
        data: {'card_pack_id': cardPackId},
      );
      return resp.data as Map<String, dynamic>;
    } catch (_) {
      // The current backend does not fully cover module 4 yet, so keep the
      // import flow testable by persisting a local import record.
      final importedRecord = await _importLocally(cardPackId);
      return {'message': 'Imported locally', 'data': importedRecord};
    }
  }

  static Future<List<ImportHistory>> getImportHistory({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final resp = await _dio.get(
        '/imports/history',
        queryParameters: {'page': page, 'limit': limit},
      );
      final responseData = resp.data as Map<String, dynamic>;
      final data = responseData['data'] as Map<String, dynamic>;
      final imports = data['imports'] as List<dynamic>;
      return imports
          .map(
            (e) => ImportHistory.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(_historyIdsKey) ?? <String>[];
      final histories = <ImportHistory>[];
      for (final id in ids.reversed) {
        final raw = prefs.getString('$_historyPrefix$id');
        if (raw == null) continue;
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        histories.add(ImportHistory.fromJson(decoded));
      }
      return histories.take(limit).toList();
    }
  }

  static Future<void> unimportCardPack(String cardPackId) async {
    await _dio.delete('/imports/card-pack/$cardPackId');
  }

  static Future<List<Map<String, dynamic>>> getImportedItems() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_historyIdsKey) ?? <String>[];
    final importedItems = <Map<String, dynamic>>[];

    for (final id in ids) {
      final raw = prefs.getString('$_historyPrefix$id');
      if (raw == null) continue;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final items = decoded['items'] as List<dynamic>? ?? const [];
      for (final item in items) {
        importedItems.add(Map<String, dynamic>.from(item as Map));
      }
    }

    importedItems.sort((a, b) {
      final aDate =
          DateTime.tryParse(a['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate =
          DateTime.tryParse(b['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return importedItems;
  }

  static Future<Map<String, dynamic>> _importLocally(String cardPackId) async {
    final prefs = await SharedPreferences.getInstance();
    final pack = await _resolvePack(cardPackId);
    final items = await _resolveItemsForPack(pack);
    final creator = await CreatorApiService.getCreator(pack.creatorId);
    final targetWardrobeId =
        await LocalWardrobeService.getDefaultTargetWardrobeId();

    final historyId = 'import_${DateTime.now().millisecondsSinceEpoch}';
    final importedAt = DateTime.now();
    final ownedItems = <Map<String, dynamic>>[];
    for (var index = 0; index < items.length; index++) {
      final snapshot = Map<String, dynamic>.from(items[index]);
      final generatedId = await LocalClothingService.createImportedSnapshot(
        sourceItem: snapshot,
        targetWardrobeId: targetWardrobeId,
        preferredId: 'imported_${historyId}_$index',
      );
      ownedItems.add({
        ...snapshot,
        'id': generatedId,
        'source': 'IMPORTED',
        'wardrobeIds': <String>[targetWardrobeId],
        'createdAt': importedAt.toIso8601String(),
      });
    }

    final history = ImportHistory(
      id: historyId,
      userId: 'local_user',
      cardPackId: pack.id,
      cardPackName: pack.name,
      creatorId: pack.creatorId,
      creatorName: creator.displayName,
      itemCount: ownedItems.length,
      importedAt: importedAt,
    );

    final record = {
      ...history.toJson(),
      // Store a snapshot of the imported items so the virtual wardrobe can
      // render them later without depending on a platform API.
      'items': ownedItems,
      'targetWardrobeId': targetWardrobeId,
    };

    await prefs.setString('$_historyPrefix$historyId', jsonEncode(record));
    final ids = prefs.getStringList(_historyIdsKey) ?? <String>[];
    ids.add(historyId);
    await prefs.setStringList(_historyIdsKey, ids);

    return record;
  }

  static Future<dynamic> _resolvePack(String cardPackId) async {
    if (LocalCardPackService.isLocalPack(cardPackId)) {
      final localPack = await LocalCardPackService.getCardPack(cardPackId);
      if (localPack != null) return localPack;
    }

    try {
      return await CardPackApiService.getCardPack(cardPackId);
    } catch (_) {
      final localPack = await LocalCardPackService.getCardPack(cardPackId);
      if (localPack != null) return localPack;
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> _resolveItemsForPack(
    dynamic pack,
  ) async {
    if (pack.items != null && (pack.items as List).isNotEmpty) {
      return (pack.items as List<Map<String, dynamic>>)
          .map(
            (item) => {
              ...item,
              'source': 'IMPORTED',
              'createdAt':
                  item['createdAt'] as String? ??
                  DateTime.now().toIso8601String(),
            },
          )
          .toList();
    }

    final allItems = <Map<String, dynamic>>[];
    try {
      allItems.addAll(await ClothingApiService.listClothingItems(limit: 100));
    } catch (_) {}
    try {
      allItems.addAll(await LocalClothingService.listItems());
    } catch (_) {}

    final byId = <String, Map<String, dynamic>>{};
    for (final item in allItems) {
      byId[item['id'].toString()] = item;
    }

    final importedItems = <Map<String, dynamic>>[];
    for (final itemId in pack.itemIds as List<String>) {
      final item = byId[itemId];
      if (item == null) continue;
      importedItems.add({
        ...item,
        'source': 'IMPORTED',
        'createdAt': DateTime.now().toIso8601String(),
      });
    }
    return importedItems;
  }
}
