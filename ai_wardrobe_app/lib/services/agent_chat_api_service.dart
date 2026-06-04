import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'api_config.dart';

class AgentChatApiService {
  static final Dio _dio = buildApiDio();

  static Future<AgentChatHistoryData> loadHistory({int limit = 5}) async {
    final response = await _dio.get(
      '/agent/chat/history',
      queryParameters: {'limit': limit},
    );
    final responseData = Map<String, dynamic>.from(response.data as Map);
    final data = Map<String, dynamic>.from(responseData['data'] as Map);
    return AgentChatHistoryData.fromJson(data);
  }

  static Future<AgentChatData> sendMessage({
    required String message,
    String? conversationId,
    String? city,
  }) async {
    AgentChatData? finalData;
    await for (final event in sendMessageStream(
      message: message,
      conversationId: conversationId,
      city: city,
    )) {
      final errorMessage = event.errorMessage;
      if (errorMessage != null && errorMessage.isNotEmpty) {
        throw StateError(errorMessage);
      }
      finalData = event.finalData ?? finalData;
    }
    if (finalData == null) {
      throw StateError('Agent stream finished without a final response.');
    }
    return finalData!;
  }

  static Stream<AgentChatStreamEvent> sendMessageStream({
    required String message,
    String? conversationId,
    String? city,
  }) async* {
    final trimmedCity = city?.trim();
    final response = await _dio.post<ResponseBody>(
      '/agent/chat',
      data: {
        'message': message,
        if (conversationId != null && conversationId.isNotEmpty)
          'conversationId': conversationId,
        if (trimmedCity != null && trimmedCity.isNotEmpty) 'city': trimmedCity,
        'limit': 50,
        'generatePreview': false,
      },
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Accept': 'text/event-stream'},
      ),
    );
    final body = response.data;
    if (body == null) {
      throw StateError('Agent stream response was empty.');
    }

    var buffer = '';
    await for (final text in utf8.decoder.bind(body.stream.cast<List<int>>())) {
      buffer += text;
      while (true) {
        final separator = _nextSseSeparator(buffer);
        if (separator == null) {
          break;
        }
        final rawEvent = buffer.substring(0, separator.index);
        buffer = buffer.substring(separator.index + separator.length);
        final event = AgentChatStreamEvent.tryParse(rawEvent);
        if (event != null) {
          yield event;
        }
      }
    }
    final event = AgentChatStreamEvent.tryParse(buffer);
    if (event != null) {
      yield event;
    }
  }
}

_SseSeparator? _nextSseSeparator(String buffer) {
  final lf = buffer.indexOf('\n\n');
  final crlf = buffer.indexOf('\r\n\r\n');
  if (lf < 0 && crlf < 0) {
    return null;
  }
  if (lf >= 0 && (crlf < 0 || lf < crlf)) {
    return const _SseSeparator(index: 0, length: 2).at(lf);
  }
  return const _SseSeparator(index: 0, length: 4).at(crlf);
}

class _SseSeparator {
  const _SseSeparator({required this.index, required this.length});

  final int index;
  final int length;

  _SseSeparator at(int nextIndex) {
    return _SseSeparator(index: nextIndex, length: length);
  }
}

class AgentChatStreamEvent {
  const AgentChatStreamEvent({
    required this.type,
    required this.data,
  });

  final String type;
  final Map<String, dynamic> data;

  AgentChatStep? get step {
    if (type != 'step') {
      return null;
    }
    return AgentChatStep.fromJson(data);
  }

  AgentChatData? get finalData {
    if (type != 'final') {
      return null;
    }
    return AgentChatData.fromJson(data);
  }

  String? get errorMessage {
    if (type != 'error') {
      return null;
    }
    return data['message']?.toString();
  }

  static AgentChatStreamEvent? tryParse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    var type = 'message';
    final dataLines = <String>[];
    for (final line in trimmed.split('\n')) {
      final normalized = line.trimRight();
      if (normalized.startsWith('event:')) {
        type = normalized.substring(6).trim();
      } else if (normalized.startsWith('data:')) {
        dataLines.add(normalized.substring(5).trimLeft());
      }
    }
    if (dataLines.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(dataLines.join('\n'));
    if (decoded is! Map) {
      return null;
    }
    return AgentChatStreamEvent(
      type: type,
      data: Map<String, dynamic>.from(decoded),
    );
  }
}

class AgentChatStep {
  const AgentChatStep({
    required this.id,
    required this.label,
    required this.status,
    this.detail,
  });

  final String id;
  final String label;
  final String status;
  final String? detail;

  factory AgentChatStep.fromJson(Map<String, dynamic> json) {
    return AgentChatStep(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      status: json['status']?.toString() ?? 'running',
      detail: _nullableString(json['detail']),
    );
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

  factory AgentChatData.fromHistory({
    required String? conversationId,
    required Map<String, dynamic> json,
  }) {
    return AgentChatData.fromJson({
      ...json,
      'conversationId': conversationId,
      'assistantMessage': json['assistantMessage']?.toString() ??
          json['recommendationReason']?.toString() ??
          '',
      'preview': json['preview'] ?? const <String, dynamic>{},
      'tools': json['tools'] ?? const <String, dynamic>{},
    });
  }
}

class AgentChatHistoryData {
  const AgentChatHistoryData({
    required this.conversationId,
    required this.recentTurns,
    this.lastRecommendation,
  });

  final String? conversationId;
  final List<AgentChatHistoryTurn> recentTurns;
  final AgentChatData? lastRecommendation;

  factory AgentChatHistoryData.fromJson(Map<String, dynamic> json) {
    final conversationId = json['conversationId']?.toString();
    final turns = (json['recentTurns'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (turn) => AgentChatHistoryTurn.fromJson(
            conversationId: conversationId,
            json: Map<String, dynamic>.from(turn),
          ),
        )
        .toList();
    final lastRaw = json['lastRecommendation'];
    return AgentChatHistoryData(
      conversationId: conversationId,
      recentTurns: turns,
      lastRecommendation: lastRaw is Map
          ? AgentChatData.fromHistory(
              conversationId: conversationId,
              json: Map<String, dynamic>.from(lastRaw),
            )
          : null,
    );
  }
}

class AgentChatHistoryTurn {
  const AgentChatHistoryTurn({
    required this.userMessage,
    this.assistantMessage,
    this.recommendation,
  });

  final String? userMessage;
  final String? assistantMessage;
  final AgentChatData? recommendation;

  factory AgentChatHistoryTurn.fromJson({
    required String? conversationId,
    required Map<String, dynamic> json,
  }) {
    final assistantResult = _mapValue(json['assistantResult']);
    final assistantMessage = _nullableString(json['assistantMessage']) ??
        _nullableString(assistantResult['assistantMessage']) ??
        _nullableString(assistantResult['recommendationReason']);
    return AgentChatHistoryTurn(
      userMessage: _nullableString(json['userMessage']),
      assistantMessage: assistantMessage,
      recommendation: assistantResult.isEmpty
          ? null
          : AgentChatData.fromHistory(
              conversationId: conversationId,
              json: {
                ...assistantResult,
                if (assistantMessage != null) 'assistantMessage': assistantMessage,
              },
            ),
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
