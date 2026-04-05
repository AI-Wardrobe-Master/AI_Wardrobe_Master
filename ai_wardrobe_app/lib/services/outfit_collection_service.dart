import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/outfit_collection.dart';
import 'outfit_collection_storage_stub.dart'
    if (dart.library.io) 'outfit_collection_storage_io.dart'
    as storage;

class OutfitCollectionService {
  OutfitCollectionService._();

  static const _fileName = 'outfit_collections.json';
  static final ValueNotifier<List<OutfitCollection>> _collections =
      ValueNotifier<List<OutfitCollection>>(<OutfitCollection>[]);

  static bool _loaded = false;

  static ValueListenable<List<OutfitCollection>> get listenable => _collections;

  static Future<List<OutfitCollection>> ensureLoaded() async {
    if (_loaded) {
      return _collections.value;
    }

    try {
      final raw = await storage.readCollections(_fileName);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _collections.value =
              decoded
                  .whereType<Map<String, dynamic>>()
                  .map(OutfitCollection.fromJson)
                  .toList()
                ..sort(
                  (left, right) => right.createdAt.compareTo(left.createdAt),
                );
        }
      }
    } catch (_) {
      _collections.value = List<OutfitCollection>.from(_collections.value);
    } finally {
      _loaded = true;
    }

    return _collections.value;
  }

  static Future<OutfitCollection> saveCollection({
    required String title,
    required List<String> tags,
    required String description,
    required String stylingNotes,
    required String previewImagePath,
    required List<OutfitCollectionItem> items,
    bool isShareable = true,
  }) async {
    await ensureLoaded();

    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch.toString();
    final shareCode = 'COL-${id.substring(id.length - 6)}';
    final collection = OutfitCollection(
      id: id,
      title: title.trim().isEmpty ? 'Untitled collection' : title.trim(),
      tags: tags
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toSet()
          .toList(),
      description: description.trim(),
      stylingNotes: stylingNotes.trim(),
      previewImagePath: previewImagePath,
      shareCode: shareCode,
      shareUrl: 'aiwardrobe://collections/$shareCode',
      isShareable: isShareable,
      createdAt: now,
      items: items,
    );

    _collections.value = <OutfitCollection>[collection, ..._collections.value];
    await _persist();
    return collection;
  }

  @visibleForTesting
  static Future<void> resetForTest() async {
    _loaded = true;
    _collections.value = <OutfitCollection>[];
  }

  static Future<void> _persist() async {
    try {
      final payload = jsonEncode(
        _collections.value.map((collection) => collection.toJson()).toList(),
      );
      await storage.writeCollections(_fileName, payload);
    } catch (_) {
      return;
    }
  }
}
