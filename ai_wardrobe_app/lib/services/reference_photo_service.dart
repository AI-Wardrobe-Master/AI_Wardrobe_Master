import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/reference_photo.dart';
import 'reference_photo_storage_stub.dart'
    if (dart.library.io) 'reference_photo_storage_io.dart'
    as storage;

class ReferencePhotoService {
  ReferencePhotoService._();

  static const _fileName = 'reference_photos.json';
  static final ValueNotifier<ReferencePhotoLibrary> _library =
      ValueNotifier<ReferencePhotoLibrary>(const ReferencePhotoLibrary.empty());

  static bool _loaded = false;

  static ValueListenable<ReferencePhotoLibrary> get listenable => _library;

  static ReferencePhotoLibrary get currentLibrary => _library.value;
  static ReferencePhoto? get selectedPhoto => _library.value.selectedPhoto;

  static Future<ReferencePhotoLibrary> ensureLoaded() async {
    if (_loaded) {
      return _library.value;
    }

    try {
      final raw = await storage.readReferencePhotoLibrary(_fileName);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _library.value = ReferencePhotoLibrary.fromJson(decoded);
        }
      }
    } catch (_) {
      _library.value = const ReferencePhotoLibrary.empty();
    } finally {
      _loaded = true;
    }

    return _library.value;
  }

  static Future<void> addPhotos(List<String> sourcePaths) async {
    await ensureLoaded();
    if (sourcePaths.isEmpty) {
      return;
    }

    final photos = List<ReferencePhoto>.from(_library.value.photos);
    final now = DateTime.now();

    for (var index = 0; index < sourcePaths.length; index += 1) {
      final sourcePath = sourcePaths[index];
      final id = '${now.microsecondsSinceEpoch}_$index';
      final extension = _extensionFor(sourcePath);
      final storedPath = await storage.copyReferencePhoto(
        sourcePath,
        'reference_$id$extension',
      );
      photos.add(
        ReferencePhoto(
          id: id,
          label: 'Reference ${photos.length + 1}',
          imagePath: storedPath,
          createdAt: now,
        ),
      );
    }

    _library.value = ReferencePhotoLibrary(
      photos: photos,
      selectedPhotoId: _library.value.selectedPhotoId ?? photos.last.id,
    );
    await _persist();
  }

  static Future<void> selectPhoto(String? id) async {
    await ensureLoaded();
    _library.value = _library.value.copyWith(
      selectedPhotoId: id,
      clearSelectedPhoto: id == null,
    );
    await _persist();
  }

  static Future<void> removePhoto(String id) async {
    await ensureLoaded();
    final photos = List<ReferencePhoto>.from(_library.value.photos);
    ReferencePhoto? removedPhoto;
    photos.removeWhere((photo) {
      final shouldRemove = photo.id == id;
      if (shouldRemove) {
        removedPhoto = photo;
      }
      return shouldRemove;
    });
    if (removedPhoto == null) {
      return;
    }

    await storage.deleteReferencePhoto(removedPhoto!.imagePath);

    final nextSelected = _library.value.selectedPhotoId == id
        ? (photos.isEmpty ? null : photos.first.id)
        : _library.value.selectedPhotoId;
    _library.value = ReferencePhotoLibrary(
      photos: photos,
      selectedPhotoId: nextSelected,
    );
    await _persist();
  }

  @visibleForTesting
  static Future<void> resetForTest() async {
    _loaded = true;
    _library.value = const ReferencePhotoLibrary.empty();
  }

  static Future<void> _persist() async {
    try {
      final payload = jsonEncode(_library.value.toJson());
      await storage.writeReferencePhotoLibrary(_fileName, payload);
    } catch (_) {
      return;
    }
  }

  static String _extensionFor(String path) {
    final lastDot = path.lastIndexOf('.');
    if (lastDot == -1 || lastDot < path.lastIndexOf('\\')) {
      return '.jpg';
    }
    return path.substring(lastDot);
  }
}
