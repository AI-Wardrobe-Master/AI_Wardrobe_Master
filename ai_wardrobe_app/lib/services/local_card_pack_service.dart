import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/card_pack.dart';

class LocalCardPackService {
  static const String _keyPrefix = 'local_card_pack_';
  static const String _packsListKey = 'local_card_packs_list';

  static Future<CardPack> saveCardPack({
    required String name,
    String? description,
    required String type,
    required List<String> itemIds,
    String? coverImageBase64,
    bool published = false,
    List<Map<String, dynamic>>? items,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final packId = 'local_${DateTime.now().millisecondsSinceEpoch}';

    final packData = {
      'id': packId,
      'creatorId': 'local_user',
      'name': name,
      'description': description ?? '',
      'type': type,
      'itemIds': itemIds,
      'itemCount': itemIds.length,
      'coverImageUrl': coverImageBase64 != null
          ? 'data:image/jpeg;base64,$coverImageBase64'
          : null,
      'status': published ? 'PUBLISHED' : 'DRAFT',
      'shareLink': 'local://pack/$packId',
      'importCount': 0,
      'createdAt': DateTime.now().toIso8601String(),
      'publishedAt': published ? DateTime.now().toIso8601String() : null,
      'updatedAt': DateTime.now().toIso8601String(),
      'items': items,
      'isLocal': true,
    };

    await prefs.setString('$_keyPrefix$packId', jsonEncode(packData));

    final packsList = prefs.getStringList(_packsListKey) ?? <String>[];
    packsList.add(packId);
    await prefs.setStringList(_packsListKey, packsList);

    return CardPack.fromJson(packData);
  }

  static Future<CardPack?> getCardPack(String packId) async {
    final prefs = await SharedPreferences.getInstance();
    final packJson = prefs.getString('$_keyPrefix$packId');
    if (packJson == null) return null;

    final packData = jsonDecode(packJson) as Map<String, dynamic>;
    return CardPack.fromJson(packData);
  }

  static Future<List<CardPack>> listCardPacks({String? status}) async {
    final prefs = await SharedPreferences.getInstance();
    final packsList = prefs.getStringList(_packsListKey) ?? <String>[];

    final packs = <CardPack>[];
    for (final packId in packsList) {
      final pack = await getCardPack(packId);
      if (pack == null) continue;

      if (status == null) {
        packs.add(pack);
        continue;
      }

      final packStatus = pack.status.toString().split('.').last.toUpperCase();
      if (packStatus == status.toUpperCase()) {
        packs.add(pack);
      }
    }

    packs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return packs;
  }

  static Future<void> deleteCardPack(String packId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_keyPrefix$packId');

    final packsList = prefs.getStringList(_packsListKey) ?? <String>[];
    packsList.remove(packId);
    await prefs.setStringList(_packsListKey, packsList);
  }

  static bool isLocalPack(String packId) {
    return packId.startsWith('local_');
  }
}
