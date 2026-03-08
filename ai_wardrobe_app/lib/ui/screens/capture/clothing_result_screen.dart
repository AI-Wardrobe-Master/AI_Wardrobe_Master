import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../services/api_config.dart';
import '../../../services/clothing_api_service.dart';
import '../../../theme/app_theme.dart';

class ClothingResultScreen extends StatefulWidget {
  final String itemId;

  const ClothingResultScreen({super.key, required this.itemId});

  @override
  State<ClothingResultScreen> createState() => _ClothingResultScreenState();
}

class _ClothingResultScreenState extends State<ClothingResultScreen> {
  Map<String, dynamic>? _item;
  List<dynamic> _angleViews = [];
  int _selectedAngle = 0;
  bool _loading = true;
  Map<String, List<String>> _attributeOptions = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        ClothingApiService.getClothingItem(widget.itemId),
        ClothingApiService.getAngleViews(widget.itemId),
        ClothingApiService.getAttributeOptions().catchError((_) => <String, List<String>>{}),
      ]);
      setState(() {
        _item = results[0];
        _angleViews = (results[1] as Map)['angleViews'] as List? ?? [];
        _attributeOptions = results[2] as Map<String, List<String>>;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  List<Map<String, String>> _getFinalTags() {
    final list = _item?['finalTags'] as List? ?? [];
    return list
        .map((e) => Map<String, String>.from(e as Map))
        .toList();
  }

  void _openTagEditor() {
    List<Map<String, String>> tags = _getFinalTags();
    if (tags.isEmpty) {
      final pred = _item?['predictedTags'] as List? ?? [];
      tags = pred.map((e) => Map<String, String>.from(e as Map)).toList();
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => _TagEditScreen(
          itemId: widget.itemId,
          initialTags: tags,
          options: _attributeOptions,
          onSaved: () => _loadData(),
        ),
      ),
    );
  }

  Widget _buildTagsSection(Color textP, Color textS) {
    final tags = _getFinalTags();
    if (tags.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            Text('Tags', style: TextStyle(fontWeight: FontWeight.w600, color: textP)),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _openTagEditor,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add tags'),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Tags', style: TextStyle(fontWeight: FontWeight.w600, color: textP)),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _openTagEditor,
                child: const Text('Edit'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: tags.map((t) {
              final k = t['key'] ?? '';
              final v = t['value'] ?? '';
              return Chip(
                label: Text('$k: $v', style: const TextStyle(fontSize: 12)),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _fullUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    return '$fileBaseUrl$url';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textS = isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final name = _item?['name'] as String? ?? 'Clothing Item';
    final isConfirmed = _item?['isConfirmed'] as bool? ?? false;
    final _isConfirmed = isConfirmed;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // AppBar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: textP,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: _openTagEditor,
                    tooltip: 'Edit tags',
                  ),
                  Icon(
                    _isConfirmed ? Icons.check_circle : Icons.pending,
                    color: _isConfirmed ? Colors.green : Colors.orange,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            const Divider(height: 1),

            // Main image viewer
            Expanded(
              flex: 5,
              child: _angleViews.isNotEmpty
                  ? _buildAngleViewer()
                  : _buildOriginalImages(),
            ),

            // Angle selector thumbnails
            if (_angleViews.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    Icon(Icons.rotate_90_degrees_ccw,
                        size: 18, color: textS),
                    const SizedBox(width: 6),
                    Text(
                      '${_selectedAngle * 45}°',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: textP,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_angleViews.length} angles',
                      style: TextStyle(fontSize: 12, color: textS),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 74,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _angleViews.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final view = _angleViews[i] as Map;
                    final url = _fullUrl(view['url'] as String?);
                    final selected = i == _selectedAngle;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedAngle = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 64,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected
                                ? AppColors.accentBlue
                                : Theme.of(context).dividerColor,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: isDark
                                  ? Colors.white10
                                  : Colors.black.withValues(alpha: 0.05),
                            ),
                            errorWidget: (_, __, ___) => const Icon(
                              Icons.broken_image,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],

            // Tags section (2.3.3)
            _buildTagsSection(textP, textS),

            const SizedBox(height: 16),

            // Action buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                  child: const Text('Done'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAngleViewer() {
    final view = _angleViews[_selectedAngle] as Map;
    final url = _fullUrl(view['url'] as String?);
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        setState(() {
          if (details.primaryVelocity! < 0) {
            _selectedAngle = (_selectedAngle + 1) % _angleViews.length;
          } else {
            _selectedAngle =
                (_selectedAngle - 1 + _angleViews.length) % _angleViews.length;
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.contain,
          placeholder: (_, __) =>
              const Center(child: CircularProgressIndicator()),
          errorWidget: (_, __, ___) =>
              const Center(child: Icon(Icons.broken_image, size: 48)),
        ),
      ),
    );
  }

  Widget _buildOriginalImages() {
    final images = _item?['images'] as Map? ?? {};
    final front = _fullUrl(images['processedFrontUrl'] as String?);
    final back = _fullUrl(images['processedBackUrl'] as String?);

    return PageView(
      children: [
        if (front.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: CachedNetworkImage(
              imageUrl: front,
              fit: BoxFit.contain,
            ),
          ),
        if (back.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: CachedNetworkImage(
              imageUrl: back,
              fit: BoxFit.contain,
            ),
          ),
      ],
    );
  }
}

/// Tag edit screen - 2.3.3 手动调整 style/season/audience 等属性
class _TagEditScreen extends StatefulWidget {
  final String itemId;
  final List<Map<String, String>> initialTags;
  final Map<String, List<String>> options;
  final VoidCallback onSaved;

  const _TagEditScreen({
    required this.itemId,
    required this.initialTags,
    required this.options,
    required this.onSaved,
  });

  @override
  State<_TagEditScreen> createState() => _TagEditScreenState();
}

class _TagEditScreenState extends State<_TagEditScreen> {
  late Map<String, String> _singleValue; // category, pattern, style, season, audience
  late List<String> _colors;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _singleValue = {};
    _colors = [];
    for (final t in widget.initialTags) {
      final k = t['key'] ?? '';
      final v = t['value'] ?? '';
      if (k == 'color') {
        _colors.add(v);
      } else {
        _singleValue[k] = v;
      }
    }
    // Ensure all keys have a value
    for (final k in ['category', 'pattern', 'style', 'season', 'audience']) {
      _singleValue.putIfAbsent(k, () => widget.options[k]?.first ?? '');
    }
    if (_colors.isEmpty && (widget.options['color']?.isNotEmpty ?? false)) {
      _colors = [widget.options['color']!.first];
    }
  }

  List<Map<String, String>> _toFinalTags() {
    final out = <Map<String, String>>[];
    for (final e in _singleValue.entries) {
      if (e.value.isNotEmpty) out.add({'key': e.key, 'value': e.value});
    }
    for (final c in _colors) {
      if (c.isNotEmpty) out.add({'key': 'color', 'value': c});
    }
    return out;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ClothingApiService.updateClothingItem(
        widget.itemId,
        finalTags: _toFinalTags(),
        isConfirmed: true,
      );
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Tags'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildDropdown('Category', 'category'),
          _buildDropdown('Pattern', 'pattern'),
          _buildColorSection(),
          _buildDropdown('Style', 'style'),
          _buildDropdown('Season', 'season'),
          _buildDropdown('Audience', 'audience'),
        ],
      ),
    );
  }

  Widget _buildDropdown(String label, String key) {
    final opts = widget.options[key] ?? [];
    final val = _singleValue[key] ?? opts.firstOrNull ?? '';
    if (opts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        value: opts.contains(val) ? val : opts.first,
        decoration: InputDecoration(labelText: label),
        items: opts.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
        onChanged: (v) => setState(() => _singleValue[key] = v ?? ''),
      ),
    );
  }

  Widget _buildColorSection() {
    final opts = widget.options['color'] ?? [];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Colors (can select multiple)', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: opts.map((c) {
              final selected = _colors.contains(c);
              return FilterChip(
                label: Text(c),
                selected: selected,
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      _colors.add(c);
                    } else {
                      _colors.remove(c);
                    }
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
