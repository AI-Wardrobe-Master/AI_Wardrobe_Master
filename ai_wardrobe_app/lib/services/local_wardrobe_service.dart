import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalWardrobeService {
  static const String _idsKey = 'local_wardrobe_v2_ids';
  static const String _recordPrefix = 'local_wardrobe_v2_';
  static const String _defaultMainId = 'local-main-wardrobe';
  static const String _defaultMainWid = 'WRD-LOCALMAIN';

  static Future<void> ensureReady() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_idsKey) ?? <String>[];
    if (ids.isEmpty) {
      final main = _buildMainWardrobe();
      await _saveRecord(main, prefs: prefs);
      await prefs.setStringList(_idsKey, <String>[main['id'] as String]);
      return;
    }

    var hasMain = false;
    for (final id in ids) {
      final record = await getWardrobe(id, prefs: prefs);
      if (record?['kind'] == 'MAIN') {
        hasMain = true;
        break;
      }
    }
    if (!hasMain) {
      final main = _buildMainWardrobe();
      ids.insert(0, main['id'] as String);
      await _saveRecord(main, prefs: prefs);
      await prefs.setStringList(_idsKey, ids);
    }
  }

  static Map<String, dynamic> _buildMainWardrobe() {
    final now = DateTime.now().toIso8601String();
    return {
      'id': _defaultMainId,
      'wid': _defaultMainWid,
      'userId': 'local_user',
      'ownerUid': 'LOCAL-USER',
      'ownerUsername': 'Local User',
      'name': 'My Wardrobe',
      'kind': 'MAIN',
      'type': 'REGULAR',
      'source': 'MANUAL',
      'isMain': true,
      'description': 'Offline main wardrobe',
      'coverImageUrl': null,
      'autoTags': <String>[],
      'manualTags': <String>[],
      'tags': <String>[],
      'isPublic': false,
      'parentWardrobeId': null,
      'outfitId': null,
      'itemCount': 0,
      'syncStatus': 'LOCAL_ONLY',
      'localOnly': true,
      'createdAt': now,
      'updatedAt': now,
    };
  }

  static Future<List<Map<String, dynamic>>> listWardrobes() async {
    await ensureReady();
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_idsKey) ?? <String>[];
    final records = <Map<String, dynamic>>[];
    for (final id in ids) {
      final record = await getWardrobe(id, prefs: prefs);
      if (record != null) {
        records.add(record);
      }
    }
    records.sort((left, right) {
      final leftMain = left['kind'] == 'MAIN' ? 0 : 1;
      final rightMain = right['kind'] == 'MAIN' ? 0 : 1;
      if (leftMain != rightMain) {
        return leftMain.compareTo(rightMain);
      }
      final leftDate =
          DateTime.tryParse(left['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final rightDate =
          DateTime.tryParse(right['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return leftDate.compareTo(rightDate);
    });
    return records;
  }

  static Future<Map<String, dynamic>?> getWardrobe(
    String wardrobeId, {
    SharedPreferences? prefs,
  }) async {
    final instance = prefs ?? await SharedPreferences.getInstance();
    final raw = instance.getString('$_recordPrefix$wardrobeId');
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  static Future<void> cacheRemoteWardrobes(
    List<Map<String, dynamic>> wardrobes,
  ) async {
    if (wardrobes.isEmpty) {
      return;
    }
    await ensureReady();
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_idsKey) ?? <String>[];
    final idSet = ids.toSet();
    for (final wardrobe in wardrobes) {
      final record = {...wardrobe, 'syncStatus': 'SYNCED', 'localOnly': false};
      await _saveRecord(record, prefs: prefs);
      final id = record['id'] as String;
      if (!idSet.contains(id)) {
        ids.add(id);
        idSet.add(id);
      }
    }
    await prefs.setStringList(_idsKey, ids);
  }

  static Future<Map<String, dynamic>> createWardrobe({
    required String name,
    String type = 'REGULAR',
    String? description,
    String? coverImageUrl,
    List<String> manualTags = const <String>[],
    bool isPublic = false,
    String? parentWardrobeId,
  }) async {
    await ensureReady();
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_idsKey) ?? <String>[];
    final now = DateTime.now().toIso8601String();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final record = {
      'id': 'local_wardrobe_$timestamp',
      'wid': 'WRD-LOCAL${timestamp.toRadixString(16).toUpperCase()}',
      'userId': 'local_user',
      'ownerUid': 'LOCAL-USER',
      'ownerUsername': 'Local User',
      'name': name,
      'kind': 'SUB',
      'type': type,
      'source': 'MANUAL',
      'isMain': false,
      'description': description,
      'coverImageUrl': coverImageUrl,
      'autoTags': <String>[],
      'manualTags': manualTags,
      'tags': manualTags,
      'isPublic': isPublic,
      'parentWardrobeId':
          parentWardrobeId ?? await getDefaultTargetWardrobeId(),
      'outfitId': null,
      'itemCount': 0,
      'syncStatus': 'LOCAL_ONLY',
      'localOnly': true,
      'createdAt': now,
      'updatedAt': now,
    };
    await _saveRecord(record, prefs: prefs);
    ids.add(record['id'] as String);
    await prefs.setStringList(_idsKey, ids);
    return record;
  }

  static Future<Map<String, dynamic>?> updateWardrobe(
    String wardrobeId, {
    String? name,
    String? description,
    String? coverImageUrl,
    List<String>? manualTags,
    bool? isPublic,
  }) async {
    await ensureReady();
    final prefs = await SharedPreferences.getInstance();
    final current = await getWardrobe(wardrobeId, prefs: prefs);
    if (current == null) {
      return null;
    }
    final updated = {
      ...current,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (coverImageUrl != null) 'coverImageUrl': coverImageUrl,
      if (manualTags != null) 'manualTags': manualTags,
      if (manualTags != null)
        'tags': <String>{
          ...((current['autoTags'] as List<dynamic>? ?? const []).map(
            (e) => e.toString(),
          )),
          ...manualTags,
        }.toList(),
      if (isPublic != null) 'isPublic': isPublic,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await _saveRecord(updated, prefs: prefs);
    return updated;
  }

  static Future<bool> deleteWardrobe(String wardrobeId) async {
    await ensureReady();
    final prefs = await SharedPreferences.getInstance();
    final current = await getWardrobe(wardrobeId, prefs: prefs);
    if (current == null || current['kind'] == 'MAIN') {
      return false;
    }
    await prefs.remove('$_recordPrefix$wardrobeId');
    final ids = prefs.getStringList(_idsKey) ?? <String>[];
    ids.remove(wardrobeId);
    await prefs.setStringList(_idsKey, ids);
    return true;
  }

  static Future<String> getDefaultTargetWardrobeId() async {
    await ensureReady();
    final wardrobes = await listWardrobes();
    final remoteMain = wardrobes.cast<Map<String, dynamic>?>().firstWhere(
      (wardrobe) =>
          wardrobe?['kind'] == 'MAIN' && wardrobe?['localOnly'] != true,
      orElse: () => null,
    );
    if (remoteMain != null) {
      return remoteMain['id'] as String;
    }
    final anyMain = wardrobes.cast<Map<String, dynamic>?>().firstWhere(
      (wardrobe) => wardrobe?['kind'] == 'MAIN',
      orElse: () => null,
    );
    if (anyMain != null) {
      return anyMain['id'] as String;
    }
    return _defaultMainId;
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
}
