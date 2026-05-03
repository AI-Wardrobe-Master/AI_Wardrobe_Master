import 'package:dio/dio.dart';

import '../models/wardrobe.dart';
import 'api_config.dart';
import 'local_clothing_service.dart';
import 'local_wardrobe_service.dart';

/// Unified wardrobe service: remote first, then local cache/offline fallback.
class WardrobeService {
  static final Dio _dio = buildApiDio();

  static Future<List<Wardrobe>> fetchWardrobes() async {
    await LocalWardrobeService.ensureReady();
    try {
      final resp = await _dio.get('/wardrobes');
      final raw = resp.data;
      final list = (raw is Map && raw['items'] != null)
          ? (raw['items'] as List<dynamic>)
                .map((entry) => Map<String, dynamic>.from(entry as Map))
                .toList()
          : <Map<String, dynamic>>[];
      await LocalWardrobeService.cacheRemoteWardrobes(list);
    } on DioException {
      // Read cached wardrobes below.
    }
    return _readCachedWardrobes();
  }

  static Future<Wardrobe?> fetchWardrobeByWid(
    String wid, {
    bool cacheRemote = true,
  }) async {
    final normalizedWid = wid.trim().toUpperCase();
    if (normalizedWid.isEmpty) {
      return null;
    }
    try {
      final resp = await _dio.get('/wardrobes/by-wid/$normalizedWid');
      final raw = resp.data;
      if (raw is! Map<String, dynamic>) {
        return null;
      }
      if (cacheRemote) {
        await LocalWardrobeService.cacheRemoteWardrobes(<Map<String, dynamic>>[
          raw,
        ]);
      }
      return _wardrobeFromRecord(raw);
    } on DioException {
      if (!cacheRemote) {
        return null;
      }
      final wardrobes = await _readCachedWardrobes();
      return wardrobes.cast<Wardrobe?>().firstWhere(
        (wardrobe) => wardrobe?.wid.toUpperCase() == normalizedWid,
        orElse: () => null,
      );
    }
  }

  static Future<List<Wardrobe>> listPublicWardrobes({
    String? search,
    int page = 1,
    int limit = 20,
  }) async {
    final queryParams = <String, dynamic>{'page': page, 'limit': limit};
    if (search != null && search.trim().isNotEmpty) {
      queryParams['search'] = search.trim();
    }

    final resp = await _dio.get(
      '/wardrobes/public',
      queryParameters: queryParams,
    );
    final raw = resp.data;
    final list = (raw is Map && raw['items'] != null)
        ? (raw['items'] as List<dynamic>)
              .map((entry) => Map<String, dynamic>.from(entry as Map))
              .toList()
        : <Map<String, dynamic>>[];
    return list.map(_wardrobeFromRecord).toList();
  }

  static Future<List<WardrobeItemWithClothing>> fetchWardrobeItems(
    String wardrobeId,
  ) async {
    final localItems = await _localWardrobeItems(wardrobeId);
    try {
      final resp = await _dio.get('/wardrobes/$wardrobeId/items');
      final raw = resp.data;
      final list = (raw is Map && raw['items'] != null)
          ? raw['items'] as List<dynamic>
          : <dynamic>[];
      final remoteItems = <WardrobeItemWithClothing>[];
      for (final entry in list) {
        final item = Map<String, dynamic>.from(entry as Map);
        final clothing = item['clothingItem'] as Map<String, dynamic>?;
        if (clothing != null) {
          await LocalClothingService.cacheRemoteItem(
            <String, dynamic>{
              ...clothing,
              'images': {
                'processedFrontUrl': clothing['imageUrl'],
                'originalFrontUrl': clothing['imageUrl'],
              },
            },
            wardrobeIds: <String>[wardrobeId],
          );
        }
        remoteItems.add(WardrobeItemWithClothing.fromJson(item));
      }

      final merged = <String, WardrobeItemWithClothing>{
        for (final item in localItems) item.clothingItemId: item,
        for (final item in remoteItems) item.clothingItemId: item,
      };
      return merged.values.toList();
    } on DioException {
      return localItems;
    }
  }

  static Future<List<WardrobeItemWithClothing>> fetchPublicWardrobeItemsByWid(
    String wid,
  ) async {
    final resp = await _dio.get('/wardrobes/by-wid/$wid/items');
    final raw = resp.data;
    final list = (raw is Map && raw['items'] != null)
        ? raw['items'] as List<dynamic>
        : <dynamic>[];
    return list
        .map(
          (entry) => WardrobeItemWithClothing.fromJson(
            Map<String, dynamic>.from(entry as Map),
          ),
        )
        .toList();
  }

  static Future<Wardrobe> createWardrobe({
    required String name,
    String type = 'REGULAR',
    String? description,
    String? coverImageUrl,
    List<String> manualTags = const <String>[],
    bool isPublic = false,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'type': type,
      if (description != null && description.isNotEmpty)
        'description': description,
      if (coverImageUrl != null && coverImageUrl.isNotEmpty)
        'coverImageUrl': coverImageUrl,
      'manualTags': manualTags,
      'isPublic': isPublic,
    };

    try {
      final resp = await _dio.post('/wardrobes', data: body);
      final record = Map<String, dynamic>.from(resp.data as Map);
      await LocalWardrobeService.cacheRemoteWardrobes(<Map<String, dynamic>>[
        record,
      ]);
      return _wardrobeFromRecord(record);
    } on DioException {
      final record = await LocalWardrobeService.createWardrobe(
        name: name,
        type: type,
        description: description,
        coverImageUrl: coverImageUrl,
        manualTags: manualTags,
        isPublic: isPublic,
      );
      return _wardrobeFromRecord(record);
    }
  }

  static Future<Wardrobe> exportSelectionToWardrobe({
    required List<String> clothingItemIds,
    String? name,
    String? description,
    String? coverImageUrl,
    List<String> manualTags = const <String>[],
  }) async {
    try {
      final resp = await _dio.post(
        '/wardrobes/export-selection',
        data: {
          'clothingItemIds': clothingItemIds,
          if (name != null && name.isNotEmpty) 'name': name,
          if (description != null && description.isNotEmpty)
            'description': description,
          if (coverImageUrl != null && coverImageUrl.isNotEmpty)
            'coverImageUrl': coverImageUrl,
          'manualTags': manualTags,
        },
      );
      final record = Map<String, dynamic>.from(resp.data as Map);
      await LocalWardrobeService.cacheRemoteWardrobes(<Map<String, dynamic>>[
        record,
      ]);
      for (final clothingItemId in clothingItemIds) {
        await LocalClothingService.assignItemToWardrobe(
          clothingItemId,
          record['id'].toString(),
        );
      }
      return _wardrobeFromRecord(record);
    } on DioException {
      final record = await LocalWardrobeService.createWardrobe(
        name: name ?? 'Styled Look',
        type: 'VIRTUAL',
        description: description,
        coverImageUrl: coverImageUrl,
        manualTags: manualTags,
      );
      for (final clothingItemId in clothingItemIds) {
        await LocalClothingService.assignItemToWardrobe(
          clothingItemId,
          record['id'].toString(),
        );
      }
      return _wardrobeFromRecord({...record, 'source': 'OUTFIT_EXPORT'});
    }
  }

  static Future<Wardrobe> importSharedWardrobe({
    required String wardrobeWid,
  }) async {
    final resp = await _dio.post(
      '/imports/wardrobe',
      data: {'wardrobeWid': wardrobeWid},
    );
    final raw = Map<String, dynamic>.from(resp.data as Map);
    final importedWid = raw['wardrobeWid']?.toString();
    if (importedWid == null || importedWid.isEmpty) {
      throw Exception('Imported wardrobe did not return a WID');
    }
    final wardrobe = await fetchWardrobeByWid(importedWid);
    if (wardrobe == null) {
      throw Exception('Imported wardrobe could not be loaded');
    }
    return wardrobe;
  }

  static Future<Wardrobe> updateWardrobe(
    String wardrobeId, {
    String? name,
    String? description,
    String? coverImageUrl,
    List<String>? manualTags,
    bool? isPublic,
  }) async {
    final body = <String, dynamic>{
      ...?(name != null ? <String, dynamic>{'name': name} : null),
      ...?(description != null
          ? <String, dynamic>{'description': description}
          : null),
      ...?(coverImageUrl != null
          ? <String, dynamic>{'coverImageUrl': coverImageUrl}
          : null),
      ...?(manualTags != null
          ? <String, dynamic>{'manualTags': manualTags}
          : null),
      ...?(isPublic != null ? <String, dynamic>{'isPublic': isPublic} : null),
    };
    try {
      final resp = await _dio.patch('/wardrobes/$wardrobeId', data: body);
      final record = Map<String, dynamic>.from(resp.data as Map);
      await LocalWardrobeService.cacheRemoteWardrobes(<Map<String, dynamic>>[
        record,
      ]);
      return _wardrobeFromRecord(record);
    } on DioException {
      final record = await LocalWardrobeService.updateWardrobe(
        wardrobeId,
        name: name,
        description: description,
        coverImageUrl: coverImageUrl,
        manualTags: manualTags,
        isPublic: isPublic,
      );
      if (record == null) {
        throw Exception('Wardrobe not found');
      }
      return _wardrobeFromRecord(record);
    }
  }

  static Future<void> deleteWardrobe(String wardrobeId) async {
    try {
      await _dio.delete('/wardrobes/$wardrobeId');
    } on DioException {
      final deleted = await LocalWardrobeService.deleteWardrobe(wardrobeId);
      if (!deleted) {
        rethrow;
      }
      return;
    }
    await LocalWardrobeService.deleteWardrobe(wardrobeId);
  }

  static Future<void> addItemToWardrobe(
    String wardrobeId,
    String clothingItemId,
  ) async {
    try {
      await _dio.post(
        '/wardrobes/$wardrobeId/items',
        data: {'clothingItemId': clothingItemId},
      );
    } on DioException {
      await LocalClothingService.assignItemToWardrobe(
        clothingItemId,
        wardrobeId,
      );
      return;
    }
    await LocalClothingService.assignItemToWardrobe(clothingItemId, wardrobeId);
  }

  static Future<void> removeItemFromWardrobe(
    String wardrobeId,
    String clothingItemId,
  ) async {
    try {
      await _dio.delete('/wardrobes/$wardrobeId/items/$clothingItemId');
    } on DioException {
      await LocalClothingService.removeItemFromWardrobe(
        clothingItemId,
        wardrobeId,
      );
      return;
    }
    await LocalClothingService.removeItemFromWardrobe(
      clothingItemId,
      wardrobeId,
    );
  }

  static Future<void> moveItemBetweenWardrobes({
    required String clothingItemId,
    required String fromWardrobeId,
    required String toWardrobeId,
  }) async {
    try {
      await _dio.post(
        '/wardrobes/$fromWardrobeId/items/$clothingItemId/move',
        data: {'targetWardrobeId': toWardrobeId},
      );
    } on DioException {
      await LocalClothingService.replaceWardrobeMembership(
        clothingItemId,
        fromWardrobeId: fromWardrobeId,
        toWardrobeId: toWardrobeId,
      );
      return;
    }
    await LocalClothingService.replaceWardrobeMembership(
      clothingItemId,
      fromWardrobeId: fromWardrobeId,
      toWardrobeId: toWardrobeId,
    );
  }

  static Future<void> copyItemToWardrobe({
    required String clothingItemId,
    required String toWardrobeId,
  }) async {
    try {
      await _dio.post('/wardrobes/$toWardrobeId/items/$clothingItemId/copy');
    } on DioException {
      await LocalClothingService.assignItemToWardrobe(
        clothingItemId,
        toWardrobeId,
      );
      return;
    }
    await LocalClothingService.assignItemToWardrobe(
      clothingItemId,
      toWardrobeId,
    );
  }

  static Future<List<Wardrobe>> _readCachedWardrobes() async {
    var records = await LocalWardrobeService.listWardrobes();
    final items = await LocalClothingService.listItems();

    final hasRemoteMain = records.any(
      (record) => record['kind'] == 'MAIN' && record['localOnly'] != true,
    );
    if (hasRemoteMain) {
      records = records
          .where(
            (record) =>
                !(record['kind'] == 'MAIN' && record['localOnly'] == true),
          )
          .toList();
    }

    return records.map((record) {
      final localCount = items.where((item) {
        final ids = (item['wardrobeIds'] as List<dynamic>? ?? const <dynamic>[])
            .map((entry) => entry.toString())
            .toList();
        return ids.contains(record['id'].toString());
      }).length;
      final fallbackCount = (record['itemCount'] as num?)?.toInt() ?? 0;
      return _wardrobeFromRecord({
        ...record,
        'itemCount': localCount > 0 ? localCount : fallbackCount,
      });
    }).toList();
  }

  static Wardrobe _wardrobeFromRecord(Map<String, dynamic> record) {
    return Wardrobe.fromJson(Map<String, dynamic>.from(record));
  }

  static Future<List<WardrobeItemWithClothing>> _localWardrobeItems(
    String wardrobeId,
  ) async {
    final items = await LocalClothingService.listItems(wardrobeId: wardrobeId);
    return items.map((item) {
      final clothing = ClothingItemBrief.fromJson(item);
      return WardrobeItemWithClothing(
        id: 'local_link_${wardrobeId}_${item['id']}',
        wardrobeId: wardrobeId,
        clothingItemId: item['id'].toString(),
        addedAt: DateTime.tryParse(item['createdAt'] as String? ?? ''),
        displayOrder: null,
        clothingItem: clothing,
      );
    }).toList();
  }
}
