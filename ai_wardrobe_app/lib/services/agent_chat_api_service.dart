import 'package:dio/dio.dart';

import 'api_config.dart';

class AgentChatApiService {
  static final Dio _dio = buildApiDio();

  static Future<AgentChatData> sendMessage({
    required String message,
    String? conversationId,
    String? city,
  }) async {
    final trimmedCity = city?.trim();
    final response = await _dio.post(
      '/agent/chat',
      data: {
        'message': message,
        if (conversationId != null && conversationId.isNotEmpty)
          'conversationId': conversationId,
        if (trimmedCity != null && trimmedCity.isNotEmpty) 'city': trimmedCity,
        'limit': 50,
        'generatePreview': false,
      },
    );
    final responseData = Map<String, dynamic>.from(response.data as Map);
    final data = Map<String, dynamic>.from(responseData['data'] as Map);
    return AgentChatData.fromJson(data);
  }
}

class AgentChatData {
  const AgentChatData({
    required this.conversationId,
    required this.assistantMessage,
    required this.outfit,
    required this.recommendationReason,
    this.weatherReason,
    this.preferenceReason,
    this.missingItems = const <String>[],
    this.preview = const <String, dynamic>{},
    this.tools = const <String, dynamic>{},
  });

  final String? conversationId;
  final String assistantMessage;
  final AgentOutfit outfit;
  final String recommendationReason;
  final String? weatherReason;
  final String? preferenceReason;
  final List<String> missingItems;
  final Map<String, dynamic> preview;
  final Map<String, dynamic> tools;

  factory AgentChatData.fromJson(Map<String, dynamic> json) {
    return AgentChatData(
      conversationId: json['conversationId']?.toString(),
      assistantMessage: json['assistantMessage']?.toString() ?? '',
      outfit: AgentOutfit.fromJson(_mapValue(json['outfit'])),
      recommendationReason: json['recommendationReason']?.toString() ?? '',
      weatherReason: _nullableString(json['weatherReason']),
      preferenceReason: _nullableString(json['preferenceReason']),
      missingItems: (json['missingItems'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      preview: _mapValue(json['preview']),
      tools: _mapValue(json['tools']),
    );
  }
}

class AgentOutfit {
  const AgentOutfit({required this.name, required this.items});

  final String name;
  final List<AgentOutfitItem> items;

  factory AgentOutfit.fromJson(Map<String, dynamic> json) {
    final rawName = json['name']?.toString().trim();
    return AgentOutfit(
      name: rawName != null && rawName.isNotEmpty ? rawName : '穿搭推荐',
      items: (json['items'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                AgentOutfitItem.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((item) => item.clothingItemId.isNotEmpty)
          .toList(),
    );
  }
}

class AgentOutfitItem {
  const AgentOutfitItem({required this.clothingItemId, this.slot});

  final String clothingItemId;
  final String? slot;

  factory AgentOutfitItem.fromJson(Map<String, dynamic> json) {
    return AgentOutfitItem(
      clothingItemId: json['clothingItemId']?.toString() ?? '',
      slot: _nullableString(json['slot']),
    );
  }
}

Map<String, dynamic> _mapValue(dynamic raw) {
  if (raw is Map) {
    return Map<String, dynamic>.from(raw);
  }
  return const <String, dynamic>{};
}

String? _nullableString(dynamic raw) {
  final value = raw?.toString().trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  return value;
}
