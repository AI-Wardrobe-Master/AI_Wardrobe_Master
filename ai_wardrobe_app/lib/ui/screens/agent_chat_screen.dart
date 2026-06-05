import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_strings_provider.dart';
import '../../services/agent_chat_api_service.dart';
import '../../services/clothing_api_service.dart';
import '../../services/outfit_preview_api_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_remote_image.dart';

class AgentChatScreen extends StatefulWidget {
  const AgentChatScreen({super.key});

  @override
  State<AgentChatScreen> createState() => _AgentChatScreenState();
}

class _AgentChatScreenState extends State<AgentChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  final Map<String, Map<String, dynamic>> _itemDetails = {};
  final List<AgentChatStep> _agentSteps = [];

  String? _conversationId;
  AgentChatData? _latestRecommendation;
  bool _historyLoading = true;
  bool _sending = false;
  int? _streamingMessageIndex;
  Map<String, dynamic>? _agentPreviewTask;
  bool _previewPolling = false;
  String? _previewError;
  int _previewPollToken = 0;
  String? _error;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _textPrimary =>
      _isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
  Color get _textSecondary =>
      _isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
  Color get _surface => _isDark ? AppColors.darkSurface : Colors.white;
  Color get _accent =>
      _isDark ? AppColors.darkAccentBlue : AppColors.accentBlue;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _previewPollToken++;
    _messageController.dispose();
    _cityController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final history = await AgentChatApiService.loadHistory();
      if (!mounted) {
        return;
      }

      final loadedMessages = <_ChatMessage>[];
      final historicalRecommendations = <AgentChatData>[];
      for (final turn in history.recentTurns) {
        final userMessage = turn.userMessage;
        if (userMessage != null && userMessage.isNotEmpty) {
          loadedMessages.add(_ChatMessage.user(userMessage));
        }
        final assistantMessage = turn.assistantMessage;
        if (assistantMessage != null && assistantMessage.isNotEmpty) {
          loadedMessages.add(
            _ChatMessage.assistant(
              assistantMessage,
              recommendation: turn.recommendation,
            ),
          );
        }
        final recommendation = turn.recommendation;
        if (recommendation != null) {
          historicalRecommendations.add(recommendation);
        }
      }

      final latest = history.lastRecommendation ??
          (historicalRecommendations.isNotEmpty
              ? historicalRecommendations.last
              : null);
      setState(() {
        _conversationId = history.conversationId;
        _messages
          ..clear()
          ..addAll(loadedMessages);
        _latestRecommendation = latest;
        _historyLoading = false;
      });
      if (latest != null) {
        await _loadRecommendedItemDetails(latest.outfit.items);
      }
      _scrollToBottom();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _historyLoading = false;
        _error = _formatError(error);
      });
    }
  }

  Future<void> _sendCurrentMessage() async {
    await _sendMessage(_messageController.text);
  }

  Future<void> _sendMessage(String rawMessage) async {
    final message = rawMessage.trim();
    if (message.isEmpty || _sending) {
      return;
    }

    setState(() {
      _messages.add(_ChatMessage.user(message));
      _messages.add(const _ChatMessage.assistant('', isStreaming: true));
      _streamingMessageIndex = _messages.length - 1;
      _agentSteps
        ..clear()
        ..add(_initialAgentSteps.first);
      _messageController.clear();
      _sending = true;
      _error = null;
    });
    _scrollToBottom();

    try {
      AgentChatData? finalData;
      await for (final event in AgentChatApiService.sendMessageStream(
        message: message,
        conversationId: _conversationId,
        city: _cityController.text,
      )) {
        if (!mounted) {
          return;
        }
        final step = event.step;
        if (step != null) {
          setState(() => _upsertAgentStep(step));
          _scrollToBottom();
          continue;
        }
        final errorMessage = event.errorMessage;
        if (errorMessage != null && errorMessage.isNotEmpty) {
          throw StateError(errorMessage);
        }
        final data = event.finalData;
        if (data != null) {
          finalData = data;
        }
      }
      if (!mounted) {
        return;
      }
      final data = finalData;
      if (data == null) {
        throw StateError('Agent stream finished without a final response.');
      }
      setState(() {
        _conversationId = data.conversationId;
        _latestRecommendation = data;
      });
      _activateAgentPreview(data);
      await _typeAssistantMessage(data);
      await _loadRecommendedItemDetails(data.outfit.items);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _formatError(error);
        _clearStreamingMessage();
      });
    } finally {
      if (mounted) {
        if (_sending) {
          setState(() {
            _sending = false;
            _streamingMessageIndex = null;
            _agentSteps.clear();
          });
        }
        _scrollToBottom();
      }
    }
  }

  void _upsertAgentStep(AgentChatStep step) {
    final index = _agentSteps.indexWhere((item) => item.id == step.id);
    if (index >= 0) {
      _agentSteps[index] = step;
    } else {
      _agentSteps.add(step);
    }
    _agentSteps.sort(
      (left, right) => _agentStepOrder(left.id).compareTo(
        _agentStepOrder(right.id),
      ),
    );
  }

  void _clearStreamingMessage() {
    final index = _streamingMessageIndex;
    if (index != null && index >= 0 && index < _messages.length) {
      _messages.removeAt(index);
    }
    _streamingMessageIndex = null;
    _sending = false;
    _agentSteps.clear();
  }

  Future<void> _typeAssistantMessage(AgentChatData data) async {
    final index = _streamingMessageIndex;
    if (index == null || index < 0 || index >= _messages.length) {
      setState(() {
        _messages.add(
          _ChatMessage.assistant(data.assistantMessage, recommendation: data),
        );
      });
      return;
    }

    const chunkSize = 3;
    const typingDelay = Duration(milliseconds: 8);
    for (
      var i = chunkSize;
      i <= data.assistantMessage.length + chunkSize;
      i += chunkSize
    ) {
      if (!mounted) {
        return;
      }
      final end = i.clamp(0, data.assistantMessage.length);
      setState(() {
        _messages[index] = _ChatMessage.assistant(
          data.assistantMessage.substring(0, end),
          recommendation: end == data.assistantMessage.length ? data : null,
          isStreaming: end != data.assistantMessage.length,
        );
      });
      if (end % 12 == 0 || end == data.assistantMessage.length) {
        _scrollToBottom();
      }
      if (end == data.assistantMessage.length) {
        break;
      }
      await Future<void>.delayed(typingDelay);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _sending = false;
      _streamingMessageIndex = null;
      _agentSteps.clear();
    });
  }

  void _selectRecommendation(AgentChatData data) {
    setState(() => _latestRecommendation = data);
    _activateAgentPreview(data);
    _loadRecommendedItemDetails(data.outfit.items);
  }

  void _activateAgentPreview(AgentChatData data) {
    final previewData = _previewData(data.preview);
    final taskId = previewData?['taskId']?.toString();
    _previewPollToken++;
    if (taskId == null || taskId.isEmpty) {
      setState(() {
        _agentPreviewTask = null;
        _previewPolling = false;
        _previewError = null;
      });
      return;
    }

    final token = _previewPollToken;
    setState(() {
      _agentPreviewTask = {
        'id': taskId,
        'status': previewData?['taskStatus']?.toString() ?? 'PENDING',
        'previewImageUrl': previewData?['previewImageUrl']?.toString(),
      };
      _previewPolling = true;
      _previewError = null;
    });
    unawaited(_pollAgentPreviewTask(taskId, token));
  }

  Map<String, dynamic>? _previewData(Map<String, dynamic> preview) {
    final data = preview['data'];
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return null;
  }

  Future<void> _pollAgentPreviewTask(String taskId, int token) async {
    for (var attempt = 0; attempt < 80; attempt++) {
      if (!mounted || token != _previewPollToken) {
        return;
      }
      try {
        final response = await OutfitPreviewApiService.getTask(taskId);
        final rawData = response['data'] ?? response;
        final task = rawData is Map
            ? Map<String, dynamic>.from(rawData)
            : <String, dynamic>{};
        final status = task['status']?.toString() ?? 'PENDING';
        if (!mounted || token != _previewPollToken) {
          return;
        }
        setState(() {
          _agentPreviewTask = task;
          _previewPolling = status == 'PENDING' || status == 'PROCESSING';
          _previewError = status == 'FAILED'
              ? task['errorMessage']?.toString() ?? 'Preview generation failed.'
              : null;
        });
        if (status == 'COMPLETED' || status == 'FAILED') {
          return;
        }
      } catch (error) {
        if (!mounted || token != _previewPollToken) {
          return;
        }
        setState(() {
          _previewPolling = false;
          _previewError = _formatError(error);
        });
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    if (!mounted || token != _previewPollToken) {
      return;
    }
    setState(() {
      _previewPolling = false;
      _previewError = 'Preview generation timed out.';
    });
  }

  Future<void> _loadRecommendedItemDetails(
    List<AgentOutfitItem> outfitItems,
  ) async {
    final missingIds = outfitItems
        .map((item) => item.clothingItemId)
        .where((id) => id.isNotEmpty && !_itemDetails.containsKey(id))
        .toSet();
    if (missingIds.isEmpty) {
      return;
    }

    final loaded = <String, Map<String, dynamic>>{};
    for (final id in missingIds) {
      try {
        final response = await ClothingApiService.getClothingItem(id);
        final payload = response['data'];
        loaded[id] = payload is Map
            ? Map<String, dynamic>.from(payload)
            : Map<String, dynamic>.from(response);
      } catch (_) {}
    }
    if (!mounted || loaded.isEmpty) {
      return;
    }
    setState(() => _itemDetails.addAll(loaded));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  String _formatError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['detail'] != null) {
        return data['detail'].toString();
      }
      if (error.message != null && error.message!.isNotEmpty) {
        return error.message!;
      }
    }
    return error.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 960;
            final content = wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: _buildChatColumn(wide: true)),
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: Theme.of(context).dividerColor,
                      ),
                      SizedBox(
                        width: 390,
                        child: _buildRecommendationPanel(compact: false),
                      ),
                    ],
                  )
                : _buildChatColumn(wide: false);
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: content,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildChatColumn({required bool wide}) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(child: _buildMessageList(includeRecommendation: !wide)),
        _buildComposer(),
      ],
    );
  }

  Widget _buildHeader() {
    final s = AppStringsProvider.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.agentTitle,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary,
                      ),
                    ),
                    if (_conversationId != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _conversationId!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: _textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _cityController,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: s.agentCityHint,
                    prefixIcon: Icon(
                      Icons.location_city_rounded,
                      size: 18,
                      color: _textSecondary,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: _surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide(
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide(
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide(color: _accent),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            _buildErrorBanner(),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: _textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(fontSize: 12, color: _textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList({required bool includeRecommendation}) {
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      children: [
        if (_historyLoading && _messages.isEmpty) _buildHistoryLoading(),
        if (!_historyLoading && _messages.isEmpty) _buildEmptyState(),
        for (final message in _messages) _buildMessageBubble(message),
        if (_sending && _streamingMessageIndex == null) _buildSendingBubble(),
        if (includeRecommendation && _latestRecommendation != null) ...[
          const SizedBox(height: 12),
          _buildRecommendationPanel(compact: true),
        ],
      ],
    );
  }

  Widget _buildHistoryLoading() {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
      ),
    );
  }

  Widget _buildEmptyState() {
    final s = AppStringsProvider.of(context);
    final suggestions = [
      s.agentSuggestionCommute,
      s.agentSuggestionRain,
      s.agentSuggestionCasual,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(Icons.auto_awesome_rounded, size: 42, color: _textSecondary),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final suggestion in suggestions)
                ActionChip(
                  avatar: const Icon(Icons.chat_bubble_outline, size: 16),
                  label: Text(suggestion),
                  onPressed: () => _sendMessage(suggestion),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(_ChatMessage message) {
    final isUser = message.role == _ChatRole.user;
    final canSelect = !isUser && message.recommendation != null;
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 680),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isUser ? AppColors.accentYellow : _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isUser
              ? AppColors.accentYellow
              : Theme.of(context).dividerColor,
        ),
      ),
      child: message.isStreaming && message.text.isEmpty
          ? _buildAgentTimeline()
          : Text(
              message.text,
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: isUser ? AppColors.textPrimary : _textPrimary,
              ),
            ),
    );
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: canSelect
          ? InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _selectRecommendation(message.recommendation!),
              child: bubble,
            )
          : bubble,
    );
  }

  Widget _buildAgentTimeline() {
    final steps = _visibleAgentSteps();
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 260),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final step in steps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: _buildStepIcon(step.status),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _textPrimary,
                          ),
                        ),
                        if (step.detail != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            step.detail!,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.25,
                              color: _textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<AgentChatStep> _visibleAgentSteps() {
    final startedSteps = _agentSteps
        .where((step) => step.status != 'pending')
        .toList(growable: false);
    if (startedSteps.isNotEmpty) {
      return startedSteps;
    }
    return const [
      AgentChatStep(id: 'queued', label: 'Start Agent', status: 'running'),
    ];
  }

  Widget _buildStepIcon(String status) {
    if (status == 'running') {
      return SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
      );
    }
    final icon = switch (status) {
      'success' => Icons.check_circle_rounded,
      'skipped' => Icons.remove_circle_outline_rounded,
      'failed' => Icons.error_outline_rounded,
      _ => Icons.circle_outlined,
    };
    final color = switch (status) {
      'success' => Colors.green,
      'failed' => Colors.redAccent,
      _ => _textSecondary,
    };
    return Icon(icon, size: 16, color: color);
  }

  Widget _buildSendingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
        ),
      ),
    );
  }

  Widget _buildComposer() {
    final s = AppStringsProvider.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendCurrentMessage(),
              enabled: !_sending,
              decoration: InputDecoration(
                hintText: s.agentInputHint,
                filled: true,
                fillColor: _surface,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Theme.of(context).dividerColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Theme.of(context).dividerColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: _accent),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            height: 44,
            child: FilledButton(
              onPressed: _sending ? null : _sendCurrentMessage,
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Icon(Icons.send_rounded, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationPanel({required bool compact}) {
    final data = _latestRecommendation;
    if (data == null) {
      return Padding(
        padding: EdgeInsets.fromLTRB(20, compact ? 0 : 12, 20, 20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Icon(Icons.checkroom_rounded, size: 36, color: _textSecondary),
        ),
      );
    }

    final content = ListView(
      padding: EdgeInsets.fromLTRB(20, compact ? 0 : 12, 20, 20),
      shrinkWrap: compact,
      physics: compact ? const NeverScrollableScrollPhysics() : null,
      children: [
        Text(
          data.outfit.name,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: _textPrimary,
          ),
        ),
        if (data.weatherReason != null) ...[
          const SizedBox(height: 10),
          _buildReasonBlock(data.weatherReason!),
        ],
        if (data.preferenceReason != null) ...[
          const SizedBox(height: 8),
          _buildReasonBlock(data.preferenceReason!),
        ],
        if (_shouldShowAgentPreview(data)) ...[
          const SizedBox(height: 10),
          _buildAgentPreviewBlock(data),
        ],
        const SizedBox(height: 14),
        for (final item in data.outfit.items) _buildOutfitItemTile(item),
        if (data.missingItems.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final item in data.missingItems)
                Chip(label: Text(item), visualDensity: VisualDensity.compact),
            ],
          ),
        ],
      ],
    );

    if (compact) {
      return Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: content,
      );
    }
    return content;
  }

  Widget _buildReasonBlock(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isDark ? AppColors.darkBackground : AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, height: 1.35, color: _textSecondary),
      ),
    );
  }

  bool _shouldShowAgentPreview(AgentChatData data) {
    final previewStatus = data.preview['status']?.toString();
    return _agentPreviewTask != null ||
        previewStatus == 'success' ||
        previewStatus == 'failed';
  }

  Widget _buildAgentPreviewBlock(AgentChatData data) {
    final task = _agentPreviewTask;
    final status =
        task?['status']?.toString() ??
        data.preview['status']?.toString()?.toUpperCase() ??
        'PENDING';
    final imageUrl = task?['previewImageUrl']?.toString();
    final message =
        _previewError ??
        data.preview['messageForUser']?.toString() ??
        'Generating outfit preview...';
    final completed =
        status == 'COMPLETED' && imageUrl != null && imageUrl.isNotEmpty;
    final failed = status == 'FAILED' || data.preview['status'] == 'failed';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                completed
                    ? Icons.image_rounded
                    : failed
                    ? Icons.error_outline_rounded
                    : Icons.auto_awesome_motion_rounded,
                size: 18,
                color: failed ? Colors.redAccent : _accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Outfit preview',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
              ),
              if (_previewPolling)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (completed)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 260,
                width: double.infinity,
                child: AppRemoteImage(
                  url: imageUrl,
                  fit: BoxFit.contain,
                  placeholder: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _accent,
                    ),
                  ),
                  errorWidget: Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: _textSecondary,
                    ),
                  ),
                ),
              ),
            )
          else
            Text(
              failed ? message : 'Preview task is ${status.toLowerCase()}.',
              style: TextStyle(fontSize: 12, height: 1.3, color: _textSecondary),
            ),
        ],
      ),
    );
  }

  Widget _buildOutfitItemTile(AgentOutfitItem item) {
    final detail = _itemDetails[item.clothingItemId];
    final name = detail?['name']?.toString();
    final imageUrl = _imageUrlFromDetail(detail);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 54,
              height: 54,
              child: imageUrl == null
                  ? Container(
                      color: _isDark
                          ? AppColors.darkBackground
                          : AppColors.background,
                      child: Icon(
                        Icons.checkroom_rounded,
                        color: _textSecondary,
                      ),
                    )
                  : AppRemoteImage(
                      url: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: Container(
                        color: _isDark
                            ? AppColors.darkBackground
                            : AppColors.background,
                      ),
                      errorWidget: Container(
                        color: _isDark
                            ? AppColors.darkBackground
                            : AppColors.background,
                        child: Icon(Icons.image_outlined, color: _textSecondary),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name?.trim().isNotEmpty == true
                      ? name!
                      : item.clothingItemId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.slot ?? 'item',
                  style: TextStyle(fontSize: 12, color: _textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _imageUrlFromDetail(Map<String, dynamic>? detail) {
    if (detail == null) {
      return null;
    }
    final images = detail['images'];
    if (images is Map) {
      final processed = images['processedFrontUrl']?.toString();
      if (processed != null && processed.isNotEmpty) {
        return processed;
      }
      final original = images['originalFrontUrl']?.toString();
      if (original != null && original.isNotEmpty) {
        return original;
      }
    }
    final imageUrl = detail['imageUrl']?.toString();
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return imageUrl;
    }
    return null;
  }
}

const List<AgentChatStep> _initialAgentSteps = [
  AgentChatStep(id: 'queued', label: 'Start Agent', status: 'running'),
  AgentChatStep(
    id: 'understand_request',
    label: 'Understand request',
    status: 'pending',
  ),
  AgentChatStep(id: 'get_weather', label: 'Get weather', status: 'pending'),
  AgentChatStep(
    id: 'get_clothing_taxonomy',
    label: 'Read wardrobe tags',
    status: 'pending',
  ),
  AgentChatStep(
    id: 'search_wardrobe_items',
    label: 'Search wardrobe',
    status: 'pending',
  ),
  AgentChatStep(
    id: 'outfit_agent_loop',
    label: 'Generate outfit',
    status: 'pending',
  ),
  AgentChatStep(
    id: 'generate_outfit_preview',
    label: 'Generate preview',
    status: 'pending',
  ),
  AgentChatStep(id: 'final_response', label: 'Complete', status: 'pending'),
];

int _agentStepOrder(String id) {
  final index = _initialAgentSteps.indexWhere((step) => step.id == id);
  return index >= 0 ? index : _initialAgentSteps.length;
}

enum _ChatRole { user, assistant }

class _ChatMessage {
  const _ChatMessage({
    required this.role,
    required this.text,
    this.recommendation,
    this.isStreaming = false,
  });

  const _ChatMessage.user(String text) : this(role: _ChatRole.user, text: text);
  const _ChatMessage.assistant(
    String text, {
    AgentChatData? recommendation,
    bool isStreaming = false,
  })
    : this(
        role: _ChatRole.assistant,
        text: text,
        recommendation: recommendation,
        isStreaming: isStreaming,
      );

  final _ChatRole role;
  final String text;
  final AgentChatData? recommendation;
  final bool isStreaming;
}
