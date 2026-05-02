import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';

class LocalClothingService {
  static const String _idsKey = 'local_clothing_v2_ids';
  static const String _recordPrefix = 'local_clothing_v2_';
  static const String _legacyIdsKey = 'local_clothing_items_list';
  static const String _legacyPrefix = 'local_clothing_item_';
  static const String _cleanupFlagKey = 'local_clothing_cleanup_20260418';
  static const String _demoItemKey = 'local_clothing_3d_demo_item';
  static const String blankPreviewSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256"><rect width="256" height="256" rx="24" fill="#F5F1E8"/><path d="M92 74h72l18 36-16 72H90l-16-72 18-36Z" fill="#D9E3F0" stroke="#A7B6C8" stroke-width="8"/><path d="M110 74c0 10 8 18 18 18s18-8 18-18" fill="none" stroke="#A7B6C8" stroke-width="8" stroke-linecap="round"/></svg>';
  static const String emptyPreviewSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512"><rect width="512" height="512" fill="#FFFFFF"/></svg>';
  static final Uint8List _demoCardImageBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAACFSURBVHhe7dAhAQAADITA719681SAk0h2cmOwaQCDTQMYbBrAYNMABpsGMNg0gMGmAQw2DWCwaQCDTQMYbBrAYNMABpsGMNg0gMGmAQw2DWCwaQCDTQMYbBrAYNMABpsGMNg0gMGmAQw2DWCwaQCDTQMYbBrAYNMABpsGMNg0gMGmAQw2D0bQw7Koj1gSAAAAAElFTkSuQmCC',
  );
  static final Dio _dio = buildApiDio();

  static Future<void> ensureReady() async {
    await ApiSession.loadToken();
    await _cleanupLegacyResidue();
    await _cleanupOversizedWebImageCache();
    await _cleanupDemoPreviewItems();
    await _cleanupPresentationResidueItems();
    await _cleanupForeignUserItems();
    await _migrateLegacyItems();
  }

  static Future<String> saveItem({
    required Uint8List frontImageBytes,
    Uint8List? backImageBytes,
    required String name,
    String? description,
    List<Map<String, String>> autoTags = const <Map<String, String>>[],
    List<String> manualTags = const <String>[],
    List<Map<String, String>> mergedTags = const <Map<String, String>>[],
    String? category,
    String? material,
    String? style,
    List<String> wardrobeIds = const <String>[],
    String source = 'OWNED',
    String sourceType = 'MANUAL_CAPTURE',
    String syncStatus = 'LOCAL_ONLY',
    String? preferredId,
    bool localOnly = true,
    String previewSvgState = 'PLACEHOLDER',
    bool previewSvgAvailable = false,
    String? previewSvg,
    Map<dynamic, dynamic> angleViews = const <dynamic, dynamic>{},
    String? model3dUrl,
  }) async {
    await ensureReady();
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_idsKey) ?? <String>[];
    final now = DateTime.now();
    final itemId = preferredId ?? 'local_${now.millisecondsSinceEpoch}';
    final imageCache = await _persistLocalImages(
      itemId: itemId,
      frontImageBytes: frontImageBytes,
      backImageBytes: backImageBytes,
    );

    final normalizedAutoTags = _normalizeStructuredTags(autoTags);
    final normalizedManualTags = _normalizeStringList(manualTags);
    final normalizedMergedTags = _normalizeStructuredTags(
      mergedTags.isEmpty
          ? _mergeTagMaps(
              normalizedAutoTags,
              normalizedManualTags,
              category: category,
              material: material,
              style: style,
            )
          : mergedTags,
    );

    final record = {
      'id': itemId,
      'name': name.isEmpty ? 'Untitled Item' : name,
      'description': description ?? '',
      'source': source,
      'sourceType': sourceType,
      'syncStatus': syncStatus,
      'localOnly': localOnly,
      'autoTags': normalizedAutoTags,
      'manualTags': normalizedManualTags,
      'mergedTags': normalizedMergedTags,
      'category': category ?? _pickTagValue(normalizedMergedTags, 'category'),
      'material': material ?? _pickTagValue(normalizedMergedTags, 'material'),
      'style': style ?? _pickTagValue(normalizedMergedTags, 'style'),
      'previewSvgState': previewSvgState,
      'previewSvgAvailable': previewSvgAvailable,
      'previewSvgStoredLocally': previewSvg != null,
      'previewSvg': previewSvg,
      'model3dUrl': model3dUrl,
      'angleViews': Map<String, dynamic>.fromEntries(
        angleViews.entries.map(
          (entry) => MapEntry(entry.key.toString(), entry.value),
        ),
      ),
      'wardrobeIds': _normalizeStringList(wardrobeIds),
      ...imageCache,
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'ownerUserId': ApiSession.currentUserId ?? 'local_user',
    };

    await _saveRecord(record, prefs: prefs);
    if (!ids.contains(itemId)) {
      ids.add(itemId);
      await prefs.setStringList(_idsKey, ids);
    }
    return itemId;
  }

  static Future<void> cacheRemoteItem(
    Map<String, dynamic> item, {
    List<String> wardrobeIds = const <String>[],
  }) async {
    await ensureReady();
    final itemId = item['id']?.toString();
    if (itemId == null || itemId.isEmpty) {
      return;
    }
    final images = Map<String, dynamic>.from(
      item['images'] as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
    final angleViews = Map<String, dynamic>.from(
      images['angleViews'] as Map? ?? const <String, dynamic>{},
    );
    final autoTags = _normalizeStructuredTags(item['predictedTags']);
    final manualTags = _normalizeStringList(item['customTags']);
    final mergedTags = _normalizeStructuredTags(item['finalTags']);

    final existing = await getRecord(itemId);
    final originalFrontPath = await _cacheImageReference(
      itemId: itemId,
      existingPath: existing?['originalFrontPath'] as String?,
      existingUrl: existing?['originalFrontUrl'] as String?,
      filename: 'original_front.png',
      source: images['originalFrontUrl'] as String?,
    );
    final processedFrontPath = await _cacheImageReference(
      itemId: itemId,
      existingPath: existing?['processedFrontPath'] as String?,
      existingUrl: existing?['processedFrontUrl'] as String?,
      filename: 'processed_front.png',
      source:
          images['processedFrontUrl'] as String? ??
          images['originalFrontUrl'] as String?,
    );
    final originalBackPath = await _cacheImageReference(
      itemId: itemId,
      existingPath: existing?['originalBackPath'] as String?,
      existingUrl: existing?['originalBackUrl'] as String?,
      filename: 'original_back.png',
      source: images['originalBackUrl'] as String?,
    );
    final processedBackPath = await _cacheImageReference(
      itemId: itemId,
      existingPath: existing?['processedBackPath'] as String?,
      existingUrl: existing?['processedBackUrl'] as String?,
      filename: 'processed_back.png',
      source:
          images['processedBackUrl'] as String? ??
          images['originalBackUrl'] as String?,
    );

    final mergedWardrobeIds = <String>{
      ..._normalizeStringList(existing?['wardrobeIds']),
      ..._normalizeStringList(wardrobeIds),
    }.toList();

    final record = {
      'id': itemId,
      'name': item['name'] as String? ?? existing?['name'] ?? 'Untitled Item',
      'description':
          item['description'] as String? ?? existing?['description'] ?? '',
      'source': item['source'] as String? ?? existing?['source'] ?? 'OWNED',
      'sourceType':
          item['sourceType'] as String? ??
          existing?['sourceType'] ??
          'REMOTE_CACHE',
      'syncStatus': 'SYNCED',
      'localOnly': false,
      'autoTags': autoTags,
      'manualTags': manualTags,
      'mergedTags': mergedTags,
      'category':
          item['category'] as String? ??
          _pickTagValue(mergedTags, 'category') ??
          existing?['category'],
      'material':
          item['material'] as String? ??
          _pickTagValue(mergedTags, 'material') ??
          existing?['material'],
      'style':
          item['style'] as String? ??
          _pickTagValue(mergedTags, 'style') ??
          existing?['style'],
      'previewSvgState':
          item['previewSvgState'] as String? ??
          existing?['previewSvgState'] ??
          'PLACEHOLDER',
      'previewSvgAvailable':
          item['previewSvgAvailable'] as bool? ??
          existing?['previewSvgAvailable'] ??
          false,
      'previewSvgStoredLocally':
          item['previewSvg'] != null ||
          existing?['previewSvgStoredLocally'] == true,
      'previewSvg':
          item['previewSvg'] as String? ?? existing?['previewSvg'] as String?,
      'model3dUrl':
          item['model3dUrl'] as String? ?? existing?['model3dUrl'] as String?,
      'angleViews': angleViews.isNotEmpty
          ? angleViews
          : Map<String, dynamic>.from(
              existing?['angleViews'] as Map? ?? const <String, dynamic>{},
            ),
      'wardrobeIds': mergedWardrobeIds,
      if (kIsWeb) ...{
        'originalFrontUrl': originalFrontPath,
        'processedFrontUrl': processedFrontPath,
        'originalBackUrl': originalBackPath,
        'processedBackUrl': processedBackPath,
      } else ...{
        'originalFrontPath': originalFrontPath,
        'processedFrontPath': processedFrontPath,
        'originalBackPath': originalBackPath,
        'processedBackPath': processedBackPath,
      },
      'createdAt':
          item['createdAt'] as String? ??
          existing?['createdAt'] ??
          DateTime.now().toIso8601String(),
      'updatedAt':
          item['updatedAt'] as String? ?? DateTime.now().toIso8601String(),
      'ownerUserId':
          item['userId']?.toString() ??
          existing?['ownerUserId'] ??
          'local_user',
    };

    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_idsKey) ?? <String>[];
    await _saveRecord(record, prefs: prefs);
    if (!ids.contains(itemId)) {
      ids.add(itemId);
      await prefs.setStringList(_idsKey, ids);
    }
  }

  static Future<Map<String, dynamic>?> getItem(String itemId) async {
    await ensureReady();
    final record = await getRecord(itemId);
    if (record == null) {
      return null;
    }
    return _recordToRuntimeItem(record);
  }

  static Future<Map<String, dynamic>?> getRecord(String itemId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_recordPrefix$itemId');
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  static Future<List<Map<String, dynamic>>> listItems({
    String? wardrobeId,
    bool includeCachedRemote = true,
  }) async {
    await ensureReady();
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_idsKey) ?? <String>[];
    final items = <Map<String, dynamic>>[];
    for (final itemId in ids) {
      final record = await getRecord(itemId);
      if (record == null) {
        continue;
      }
      if (!includeCachedRemote && record['localOnly'] != true) {
        continue;
      }
      if (wardrobeId != null) {
        final wardrobeIds = _normalizeStringList(record['wardrobeIds']);
        if (!wardrobeIds.contains(wardrobeId)) {
          continue;
        }
      }
      items.add(_recordToRuntimeItem(record));
    }
    items.sort((left, right) {
      final leftDate =
          DateTime.tryParse(left['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final rightDate =
          DateTime.tryParse(right['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return rightDate.compareTo(leftDate);
    });
    return items;
  }

  static Future<void> assignItemToWardrobe(
    String itemId,
    String wardrobeId,
  ) async {
    final record = await getRecord(itemId);
    if (record == null) {
      return;
    }
    final wardrobeIds = <String>{
      ..._normalizeStringList(record['wardrobeIds']),
      wardrobeId,
    }.toList();
    await _saveRecord({
      ...record,
      'wardrobeIds': wardrobeIds,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> removeItemFromWardrobe(
    String itemId,
    String wardrobeId,
  ) async {
    final record = await getRecord(itemId);
    if (record == null) {
      return;
    }
    final wardrobeIds = _normalizeStringList(record['wardrobeIds'])
      ..remove(wardrobeId);
    await _saveRecord({
      ...record,
      'wardrobeIds': wardrobeIds,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> replaceWardrobeMembership(
    String itemId, {
    required String fromWardrobeId,
    required String toWardrobeId,
  }) async {
    final record = await getRecord(itemId);
    if (record == null) {
      return;
    }
    final wardrobeIds = _normalizeStringList(record['wardrobeIds']);
    wardrobeIds.remove(fromWardrobeId);
    if (!wardrobeIds.contains(toWardrobeId)) {
      wardrobeIds.add(toWardrobeId);
    }
    await _saveRecord({
      ...record,
      'wardrobeIds': wardrobeIds,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> updateItem(
    String itemId, {
    String? name,
    String? description,
    List<String>? manualTags,
    List<Map<String, String>>? mergedTags,
    String? category,
    String? material,
    String? style,
    List<String>? wardrobeIds,
  }) async {
    final record = await getRecord(itemId);
    if (record == null) {
      return;
    }
    final nextManualTags = manualTags != null
        ? _normalizeStringList(manualTags)
        : _normalizeStringList(record['manualTags']);
    final nextMergedTags = mergedTags != null
        ? _normalizeStructuredTags(mergedTags)
        : _normalizeStructuredTags(record['mergedTags']);
    await _saveRecord({
      ...record,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      'manualTags': nextManualTags,
      'mergedTags': nextMergedTags,
      'category':
          category ??
          _pickTagValue(nextMergedTags, 'category') ??
          record['category'],
      'material':
          material ??
          _pickTagValue(nextMergedTags, 'material') ??
          record['material'],
      'style':
          style ?? _pickTagValue(nextMergedTags, 'style') ?? record['style'],
      if (wardrobeIds != null) 'wardrobeIds': _normalizeStringList(wardrobeIds),
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> deleteItem(String itemId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_recordPrefix$itemId');
    final ids = prefs.getStringList(_idsKey) ?? <String>[];
    ids.remove(itemId);
    await prefs.setStringList(_idsKey, ids);
    if (kIsWeb) {
      return;
    }
    final directory = await _itemDirectory(itemId, create: false);
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  static Future<String> createImportedSnapshot({
    required Map<String, dynamic> sourceItem,
    required String targetWardrobeId,
    String? preferredId,
  }) async {
    final images = Map<String, dynamic>.from(
      sourceItem['images'] as Map<String, dynamic>? ??
          const <String, dynamic>{},
    );
    final frontSource =
        images['processedFrontUrl'] as String? ??
        images['originalFrontUrl'] as String? ??
        sourceItem['imageUrl'] as String?;
    if (frontSource == null || frontSource.isEmpty) {
      throw Exception('Imported card item is missing a preview image.');
    }

    final backSource =
        images['processedBackUrl'] as String? ??
        images['originalBackUrl'] as String?;
    final mergedTags = _normalizeStructuredTags(sourceItem['finalTags']);
    final previewSvg = sourceItem['previewSvg'] as String?;
    final angleViews = Map<dynamic, dynamic>.from(
      images['angleViews'] as Map? ?? const <dynamic, dynamic>{},
    );

    return saveItem(
      frontImageBytes: await _loadBytes(frontSource),
      backImageBytes: backSource == null || backSource.isEmpty
          ? null
          : await _loadBytes(backSource),
      name: sourceItem['name'] as String? ?? 'Imported Card Item',
      description: sourceItem['description'] as String?,
      manualTags: _normalizeStringList(sourceItem['customTags']),
      mergedTags: mergedTags,
      category:
          sourceItem['category'] as String? ??
          _pickTagValue(mergedTags, 'category'),
      material:
          sourceItem['material'] as String? ??
          _pickTagValue(mergedTags, 'material'),
      style:
          sourceItem['style'] as String? ?? _pickTagValue(mergedTags, 'style'),
      wardrobeIds: <String>[targetWardrobeId],
      source: 'IMPORTED',
      sourceType: 'CARD_PACK_IMPORT',
      preferredId: preferredId,
      previewSvgState:
          sourceItem['previewSvgState'] as String? ?? 'PLACEHOLDER',
      previewSvgAvailable: sourceItem['previewSvgAvailable'] as bool? ?? false,
      previewSvg: previewSvg,
      angleViews: angleViews,
      model3dUrl: sourceItem['model3dUrl'] as String?,
    );
  }

  static Future<void> ensure3dPreviewDemoItem({
    required String wardrobeId,
  }) async {
    await ensureReady();
    final prefs = await SharedPreferences.getInstance();

    Future<bool> ensureAssignment(String itemId) async {
      final record = await getRecord(itemId);
      if (record == null) {
        return false;
      }
      if (record['sourceType'] != 'DEMO_3D_PREVIEW') {
        return false;
      }
      final wardrobeIds = <String>{
        ..._normalizeStringList(record['wardrobeIds']),
        wardrobeId,
      }.toList();
      await saveItem(
        frontImageBytes: _demoCardImageBytes,
        name: '3D Preview Demo Card',
        description:
            'Blank SVG placeholder used to validate the clothing detail 3D preview UI.',
        manualTags: const <String>['demo', '3d-preview'],
        mergedTags: const <Map<String, String>>[
          {'key': 'category', 'value': 'demo'},
          {'key': 'style', 'value': 'preview'},
          {'key': 'mode', 'value': 'placeholder'},
        ],
        category: 'demo',
        style: 'preview',
        wardrobeIds: wardrobeIds,
        sourceType: 'DEMO_3D_PREVIEW',
        preferredId: itemId,
        previewSvgState: 'GENERATED',
        previewSvgAvailable: true,
        previewSvg: emptyPreviewSvg,
      );
      await prefs.setString(_demoItemKey, itemId);
      return true;
    }

    final preferredId = prefs.getString(_demoItemKey);
    if (preferredId != null && await ensureAssignment(preferredId)) {
      return;
    }

    final ids = prefs.getStringList(_idsKey) ?? <String>[];
    for (final itemId in ids) {
      if (await ensureAssignment(itemId)) {
        return;
      }
    }

    final demoId = await saveItem(
      frontImageBytes: _demoCardImageBytes,
      name: '3D Preview Demo Card',
      description:
          'Blank SVG placeholder used to validate the clothing detail 3D preview UI.',
      manualTags: const <String>['demo', '3d-preview'],
      mergedTags: const <Map<String, String>>[
        {'key': 'category', 'value': 'demo'},
        {'key': 'style', 'value': 'preview'},
        {'key': 'mode', 'value': 'placeholder'},
      ],
      category: 'demo',
      style: 'preview',
      wardrobeIds: <String>[wardrobeId],
      sourceType: 'DEMO_3D_PREVIEW',
      previewSvgState: 'GENERATED',
      previewSvgAvailable: true,
      previewSvg: emptyPreviewSvg,
    );
    await prefs.setString(_demoItemKey, demoId);
  }

  static bool isLocalItem(String itemId) {
    return itemId.startsWith('local_');
  }

  static Future<void> _cleanupLegacyResidue() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_cleanupFlagKey) == true) {
      return;
    }

    final legacyIds = prefs.getStringList(_legacyIdsKey) ?? <String>[];
    for (final legacyId in legacyIds) {
      await prefs.remove('$_legacyPrefix$legacyId');
    }
    await prefs.remove(_legacyIdsKey);
    await prefs.setBool(_cleanupFlagKey, true);
  }

  static Future<void> _cleanupOversizedWebImageCache() async {
    if (!kIsWeb) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_idsKey) ?? <String>[];
    final keptIds = <String>[];
    for (final itemId in ids) {
      final key = '$_recordPrefix$itemId';
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) {
        continue;
      }
      if (!raw.contains('DataUri') && raw.length < 500000) {
        keptIds.add(itemId);
        continue;
      }

      await prefs.remove(key);
      try {
        final record = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        record
          ..remove('originalFrontDataUri')
          ..remove('processedFrontDataUri')
          ..remove('originalBackDataUri')
          ..remove('processedBackDataUri');

        // A purely local Web item with embedded image bytes cannot be kept
        // without consuming quota. Remote items are recreated from backend data.
        if (record['localOnly'] == true) {
          continue;
        }
        await prefs.setString(key, jsonEncode(record));
        keptIds.add(itemId);
      } catch (_) {
        // Drop malformed or oversized records; backend remains source of truth.
      }
    }
    if (keptIds.length != ids.length) {
      await prefs.setStringList(_idsKey, keptIds);
    }
  }

  static Future<void> _cleanupDemoPreviewItems() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_idsKey) ?? <String>[];
    final keptIds = <String>[];

    for (final itemId in ids) {
      final key = '$_recordPrefix$itemId';
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) {
        continue;
      }

      try {
        final record = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        if (record['sourceType'] == 'DEMO_3D_PREVIEW' ||
            record['name'] == '3D Preview Demo Card') {
          await prefs.remove(key);
          continue;
        }
      } catch (_) {
        // Keep records we cannot classify; other cleanup paths handle corruption.
      }

      keptIds.add(itemId);
    }

    if (keptIds.length != ids.length) {
      await prefs.setStringList(_idsKey, keptIds);
    }
    await prefs.remove(_demoItemKey);
  }

  static Future<void> _cleanupPresentationResidueItems() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_idsKey) ?? <String>[];
    final keptIds = <String>[];

    for (final itemId in ids) {
      final key = '$_recordPrefix$itemId';
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) {
        continue;
      }

      try {
        final record = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        if (record['localOnly'] == true &&
            _containsPresentationResidue(record)) {
          await prefs.remove(key);
          continue;
        }
      } catch (_) {
        await prefs.remove(key);
        continue;
      }

      keptIds.add(itemId);
    }

    if (keptIds.length != ids.length) {
      await prefs.setStringList(_idsKey, keptIds);
    }
  }

  static bool _containsPresentationResidue(Map<String, dynamic> record) {
    final buffer = StringBuffer()
      ..write(record['name'])
      ..write(' ')
      ..write(record['description'])
      ..write(' ')
      ..write(record['category'])
      ..write(' ')
      ..write(record['material'])
      ..write(' ')
      ..write(record['style']);
    for (final collectionName in ['manualTags', 'mergedTags', 'autoTags']) {
      final raw = record[collectionName];
      if (raw is Iterable) {
        for (final entry in raw) {
          if (entry is Map) {
            buffer
              ..write(' ')
              ..write(entry['value']);
          } else {
            buffer
              ..write(' ')
              ..write(entry);
          }
        }
      }
    }
    final text = buffer.toString().toLowerCase();
    return text.contains('demo') ||
        text.contains('a.zip') ||
        text.contains('8-view');
  }

  static Future<void> _cleanupForeignUserItems() async {
    final currentUserId = ApiSession.currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_idsKey) ?? <String>[];
    final keptIds = <String>[];

    for (final itemId in ids) {
      final key = '$_recordPrefix$itemId';
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) {
        continue;
      }

      try {
        final record = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        final ownerUserId = record['ownerUserId']?.toString();
        if (ownerUserId != null &&
            ownerUserId.isNotEmpty &&
            ownerUserId != currentUserId) {
          await prefs.remove(key);
          continue;
        }
      } catch (_) {
        await prefs.remove(key);
        continue;
      }

      keptIds.add(itemId);
    }

    if (keptIds.length != ids.length) {
      await prefs.setStringList(_idsKey, keptIds);
    }
  }

  static Future<void> _migrateLegacyItems() async {
    final prefs = await SharedPreferences.getInstance();
    final legacyIds = prefs.getStringList(_legacyIdsKey) ?? <String>[];
    if (legacyIds.isEmpty) {
      return;
    }
    for (final legacyId in legacyIds) {
      final raw = prefs.getString('$_legacyPrefix$legacyId');
      if (raw == null || raw.isEmpty) {
        continue;
      }
      final legacy = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final front = _bytesFromDataUri(
        'data:image/jpeg;base64,${legacy['frontImageBase64']}',
      );
      final backRaw = legacy['backImageBase64'] as String?;
      final back = backRaw == null ? null : base64Decode(backRaw);
      await saveItem(
        frontImageBytes: front,
        backImageBytes: back,
        name: legacy['name'] as String? ?? 'Imported Item',
        description: legacy['description'] as String?,
        manualTags: _normalizeStringList(legacy['customTags']),
        mergedTags: _normalizeStructuredTags(legacy['finalTags']),
        preferredId: legacyId,
      );
      await prefs.remove('$_legacyPrefix$legacyId');
    }
    await prefs.remove(_legacyIdsKey);
  }

  static Map<String, dynamic> _recordToRuntimeItem(
    Map<String, dynamic> record,
  ) {
    final mergedTags = _normalizeStructuredTags(record['mergedTags']);
    final manualTags = _normalizeStringList(record['manualTags']);
    return {
      'id': record['id'],
      'name': record['name'],
      'description': record['description'],
      'source': record['source'] ?? 'OWNED',
      'sourceType': record['sourceType'] ?? 'MANUAL_CAPTURE',
      'syncStatus': record['syncStatus'] ?? 'LOCAL_ONLY',
      'ownerUserId': record['ownerUserId'] ?? 'local_user',
      'category': record['category'],
      'material': record['material'],
      'style': record['style'],
      'previewSvgState': record['previewSvgState'] ?? 'PLACEHOLDER',
      'previewSvg': record['previewSvg'] as String? ?? emptyPreviewSvg,
      'previewSvgAvailable': record['previewSvgAvailable'] ?? false,
      'previewSvgStoredLocally': record['previewSvgStoredLocally'] ?? false,
      'model3dUrl': record['model3dUrl'],
      'imageUrl':
          record['processedFrontUrl'] as String? ??
          record['originalFrontUrl'] as String? ??
          record['processedFrontDataUri'] as String? ??
          record['originalFrontDataUri'] as String? ??
          _filePathToDataUri(record['processedFrontPath'] as String?) ??
          _filePathToDataUri(record['originalFrontPath'] as String?),
      'predictedTags': _normalizeStructuredTags(record['autoTags']),
      'finalTags': mergedTags,
      'customTags': manualTags,
      'wardrobeIds': _normalizeStringList(record['wardrobeIds']),
      'createdAt': record['createdAt'],
      'updatedAt': record['updatedAt'],
      'images': {
        'originalFrontUrl':
            record['originalFrontUrl'] as String? ??
            record['originalFrontDataUri'] as String? ??
            _filePathToDataUri(record['originalFrontPath'] as String?),
        'processedFrontUrl':
            record['processedFrontUrl'] as String? ??
            record['processedFrontDataUri'] as String? ??
            _filePathToDataUri(record['processedFrontPath'] as String?),
        'originalBackUrl':
            record['originalBackUrl'] as String? ??
            record['originalBackDataUri'] as String? ??
            _filePathToDataUri(record['originalBackPath'] as String?),
        'processedBackUrl':
            record['processedBackUrl'] as String? ??
            record['processedBackDataUri'] as String? ??
            _filePathToDataUri(record['processedBackPath'] as String?),
        'angleViews': Map<String, dynamic>.from(
          record['angleViews'] as Map? ?? const <String, dynamic>{},
        ),
        if (record['model3dUrl'] != null) 'model3dUrl': record['model3dUrl'],
      },
    };
  }

  static Future<Map<String, String?>> _persistLocalImages({
    required String itemId,
    required Uint8List frontImageBytes,
    Uint8List? backImageBytes,
  }) async {
    if (kIsWeb) {
      return const <String, String?>{};
    }

    final directory = (await _itemDirectory(itemId, create: true))!;
    final originalFrontPath = await _writeImage(
      File('${directory.path}/original_front.png'),
      frontImageBytes,
    );
    final processedFrontPath = await _writeImage(
      File('${directory.path}/processed_front.png'),
      frontImageBytes,
    );
    String? originalBackPath;
    String? processedBackPath;
    if (backImageBytes != null) {
      originalBackPath = await _writeImage(
        File('${directory.path}/original_back.png'),
        backImageBytes,
      );
      processedBackPath = await _writeImage(
        File('${directory.path}/processed_back.png'),
        backImageBytes,
      );
    }

    return {
      'originalFrontPath': originalFrontPath,
      'processedFrontPath': processedFrontPath,
      'originalBackPath': originalBackPath,
      'processedBackPath': processedBackPath,
    };
  }

  static Future<String?> _cacheImageReference({
    required String itemId,
    required String filename,
    required String? source,
    required String? existingPath,
    required String? existingUrl,
  }) async {
    if (source == null || source.isEmpty) {
      return kIsWeb ? existingUrl : existingPath;
    }
    if (kIsWeb) {
      return source;
    }
    try {
      final bytes = await _loadBytes(source);
      final directory = (await _itemDirectory(itemId, create: true))!;
      return _writeImage(File('${directory.path}/$filename'), bytes);
    } catch (_) {
      return existingPath;
    }
  }

  static Future<Directory?> _itemDirectory(
    String itemId, {
    required bool create,
  }) async {
    if (kIsWeb) {
      return null;
    }
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}/offline_clothing/$itemId');
    if (create && !await directory.exists()) {
      await directory.create(recursive: true);
    }
    if (!create && !await directory.exists()) {
      return null;
    }
    return directory;
  }

  static Future<String> _writeImage(File file, Uint8List bytes) async {
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<Uint8List> _loadBytes(String source) async {
    if (source.startsWith('data:')) {
      return _bytesFromDataUri(source);
    }
    final response = await _dio.get<List<int>>(
      resolveFileUrl(source),
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data ?? const <int>[]);
  }

  static Uint8List _bytesFromDataUri(String source) {
    final uri = Uri.parse(source);
    final data = uri.data;
    if (data == null) {
      return Uint8List(0);
    }
    return Uint8List.fromList(data.contentAsBytes());
  }

  static String? _filePathToDataUri(String? path) {
    if (path == null || path.isEmpty) {
      return null;
    }
    if (path.startsWith('data:')) {
      return path;
    }
    final file = File(path);
    if (!file.existsSync()) {
      return null;
    }
    final bytes = file.readAsBytesSync();
    return 'data:image/png;base64,${base64Encode(bytes)}';
  }

  static Future<void> _saveRecord(
    Map<String, dynamic> record, {
    SharedPreferences? prefs,
  }) async {
    final instance = prefs ?? await SharedPreferences.getInstance();
    await instance.setString(
      '$_recordPrefix${record['id']}',
      jsonEncode(record),
    );
  }

  static List<Map<String, String>> _normalizeStructuredTags(dynamic raw) {
    final result = <Map<String, String>>[];
    for (final item in raw as List<dynamic>? ?? const <dynamic>[]) {
      if (item is Map) {
        final key = item['key']?.toString().trim();
        final value = item['value']?.toString().trim();
        if ((key ?? '').isEmpty && (value ?? '').isEmpty) {
          continue;
        }
        result.add({
          'key': key?.isNotEmpty == true ? key! : 'tag',
          'value': value?.isNotEmpty == true ? value! : key ?? 'tag',
        });
      } else if (item != null) {
        final value = item.toString().trim();
        if (value.isNotEmpty) {
          result.add({'key': 'tag', 'value': value});
        }
      }
    }
    final seen = <String>{};
    return result.where((tag) {
      final identity = '${tag['key']}:${tag['value']}'.toLowerCase();
      if (seen.contains(identity)) {
        return false;
      }
      seen.add(identity);
      return true;
    }).toList();
  }

  static List<String> _normalizeStringList(dynamic raw) {
    final result = <String>[];
    for (final item in raw as List<dynamic>? ?? const <dynamic>[]) {
      final value = item.toString().trim();
      if (value.isNotEmpty && !result.contains(value)) {
        result.add(value);
      }
    }
    return result;
  }

  static List<Map<String, String>> _mergeTagMaps(
    List<Map<String, String>> autoTags,
    List<String> manualTags, {
    String? category,
    String? material,
    String? style,
  }) {
    final merged = <Map<String, String>>[
      ...autoTags,
      ...manualTags.map((tag) => {'key': 'manual', 'value': tag}),
    ];
    if (category != null && category.trim().isNotEmpty) {
      merged.add({'key': 'category', 'value': category.trim()});
    }
    if (material != null && material.trim().isNotEmpty) {
      merged.add({'key': 'material', 'value': material.trim()});
    }
    if (style != null && style.trim().isNotEmpty) {
      merged.add({'key': 'style', 'value': style.trim()});
    }
    return merged;
  }

  static String? _pickTagValue(List<Map<String, String>> tags, String key) {
    for (final tag in tags) {
      if (tag['key']?.toLowerCase() == key.toLowerCase()) {
        return tag['value'];
      }
    }
    return null;
  }
}
