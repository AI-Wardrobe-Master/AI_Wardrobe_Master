import 'package:dio/dio.dart';

import '../models/card_pack.dart';
import 'api_config.dart';

class CardPackApiService {
  static final _dio = Dio(BaseOptions(baseUrl: apiBaseUrl));

  static Future<CardPack> createCardPack({
    required String name,
    String? description,
    required String type,
    required List<String> itemIds,
    String? coverImageBase64,
  }) async {
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
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    final queryParams = <String, dynamic>{
      'page': page,
      'limit': limit,
    };
    if (status != null) queryParams['status'] = status;

    final endpoint =
        creatorId != null ? '/creators/$creatorId/card-packs' : '/card-packs';
    final resp = await _dio.get(endpoint, queryParameters: queryParams);
    final responseData = resp.data as Map<String, dynamic>;
    final data = responseData['data'] as Map<String, dynamic>;
    final packs = data['packs'] as List<dynamic>? ??
        data['cardPacks'] as List<dynamic>? ??
        const [];
    return packs
        .map((e) => CardPack.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<CardPack> publishCardPack(String id) async {
    final resp = await _dio.post('/card-packs/$id/publish');
    final responseData = resp.data as Map<String, dynamic>;
    return CardPack.fromJson(responseData['data'] as Map<String, dynamic>);
  }
}
