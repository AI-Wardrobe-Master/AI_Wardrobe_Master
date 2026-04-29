import '../models/card_pack.dart';
import 'api_config.dart';

class CardPackApiService {
  static final _dio = buildApiDio();

  static Future<CardPack> createCardPack({
    required String name,
    String? description,
    required String type,
    required List<String> itemIds,
    String? coverImageBase64,
  }) async {
    if (type != 'CLOTHING_COLLECTION') {
      throw ArgumentError.value(
        type,
        'type',
        'Backend currently supports CLOTHING_COLLECTION only.',
      );
    }
    final data = <String, dynamic>{
      'name': name,
      'type': type,
      'itemIds': itemIds,
    };
    if (description != null) data['description'] = description;
    if (coverImageBase64 != null) data['coverImage'] = coverImageBase64;

    final resp = await _dio.post('/card-packs', data: data);
    final responseData = resp.data as Map<String, dynamic>;
    return CardPack.fromJson(responseData['data'] as Map<String, dynamic>);
  }

  static Future<CardPack> getCardPack(String id) async {
    final resp = await _dio.get('/card-packs/$id');
    final responseData = resp.data as Map<String, dynamic>;
    return CardPack.fromJson(responseData['data'] as Map<String, dynamic>);
  }

  static Future<List<CardPack>> listCardPacks({
    String? creatorId,
    String? search,
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    final queryParams = <String, dynamic>{'page': page, 'limit': limit};
    if (status != null) queryParams['status'] = status;
    if (search != null && search.trim().isNotEmpty) {
      queryParams['search'] = search.trim();
    }

    final endpoint = creatorId != null
        ? '/creators/$creatorId/card-packs'
        : '/card-packs';
    final resp = await _dio.get(endpoint, queryParameters: queryParams);
    final responseData = resp.data as Map<String, dynamic>;
    final data = responseData['data'] as Map<String, dynamic>;
    final packs =
        data['items'] as List<dynamic>? ??
        data['packs'] as List<dynamic>? ??
        data['cardPacks'] as List<dynamic>? ??
        const [];
    return packs
        .map((e) => CardPack.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<List<CardPack>> listPopularCardPacks({int limit = 10}) async {
    final resp = await _dio.get(
      '/card-packs/popular',
      queryParameters: {'limit': limit},
    );
    return _cardPacksFromListResponse(resp.data as Map<String, dynamic>);
  }

  static Future<CardPack> getCardPackByShareId(String shareId) async {
    final resp = await _dio.get('/card-packs/share/$shareId');
    final responseData = resp.data as Map<String, dynamic>;
    return CardPack.fromJson(responseData['data'] as Map<String, dynamic>);
  }

  static Future<CardPack> updateCardPack(
    String id, {
    String? name,
    String? description,
    List<String>? itemIds,
    String? coverImageBase64,
  }) async {
    final data = <String, dynamic>{
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (itemIds != null) 'itemIds': itemIds,
      if (coverImageBase64 != null) 'coverImage': coverImageBase64,
    };
    final resp = await _dio.patch('/card-packs/$id', data: data);
    final responseData = resp.data as Map<String, dynamic>;
    return CardPack.fromJson(responseData['data'] as Map<String, dynamic>);
  }

  static Future<CardPack> publishCardPack(String id) async {
    final resp = await _dio.post('/card-packs/$id/publish');
    final responseData = resp.data as Map<String, dynamic>;
    return CardPack.fromJson(responseData['data'] as Map<String, dynamic>);
  }

  static Future<CardPack> archiveCardPack(String id) async {
    final resp = await _dio.post('/card-packs/$id/archive');
    final responseData = resp.data as Map<String, dynamic>;
    return CardPack.fromJson(responseData['data'] as Map<String, dynamic>);
  }

  static Future<void> deleteCardPack(String id) async {
    await _dio.delete('/card-packs/$id');
  }

  static List<CardPack> _cardPacksFromListResponse(
    Map<String, dynamic> responseData,
  ) {
    final data = responseData['data'] as Map<String, dynamic>;
    final packs =
        data['items'] as List<dynamic>? ??
        data['packs'] as List<dynamic>? ??
        data['cardPacks'] as List<dynamic>? ??
        const [];
    return packs
        .map((e) => CardPack.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}
