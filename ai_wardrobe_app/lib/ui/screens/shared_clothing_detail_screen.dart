import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../../models/wardrobe.dart';
import '../../services/api_config.dart';
import '../../theme/app_theme.dart';

class SharedClothingDetailScreen extends StatelessWidget {
  const SharedClothingDetailScreen({
    super.key,
    required this.item,
    required this.wardrobe,
  });

  final ClothingItemBrief item;
  final Wardrobe wardrobe;

  String? get _imageUrl => item.previewImageUrl;

  Map<int, String> get _angleViews {
    final raw = item.images['angleViews'];
    if (raw is! Map) {
      return const <int, String>{};
    }
    final views = <int, String>{};
    for (final entry in raw.entries) {
      final angle = int.tryParse(entry.key.toString());
      final url = entry.value?.toString();
      if (angle != null && url != null && url.isNotEmpty) {
        views[angle] = url;
      }
    }
    return Map<int, String>.fromEntries(
      views.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  String? get _model3dUrl {
    final value = item.images['model3dUrl']?.toString();
    return value == null || value.isEmpty ? null : value;
  }

  List<String> get _tags {
    final ordered = <String>[];
    final seen = <String>{};
    for (final tag in item.tagValues) {
      final normalized = tag.trim();
      if (!_isPresentationTag(normalized)) {
        continue;
      }
      final key = normalized.toLowerCase();
      if (seen.add(key)) {
        ordered.add(normalized);
      }
    }
    return ordered.take(8).toList();
  }

  bool _isPresentationTag(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    const hidden = {
      '3d demo',
      '8-view',
      'a.zip demo',
      'demo',
      'pipeline',
      'source',
    };
    if (hidden.contains(normalized)) {
      return false;
    }
    return !normalized.contains('demo') &&
        !normalized.contains('a.zip') &&
        !normalized.startsWith('pack:');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.textPrimary;
    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;
    final surfaceColor = isDark ? AppColors.darkSurface : Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          item.name?.trim().isNotEmpty == true ? item.name! : 'Shared Item',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                height: 280,
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: _buildItemImage(textSecondary),
                ),
              ),
              const SizedBox(height: 16),
              if (item.description?.trim().isNotEmpty == true)
                Text(
                  item.description!,
                  style: TextStyle(
                    fontSize: 13,
                    color: textSecondary,
                    height: 1.5,
                  ),
                ),
              if (item.description?.trim().isNotEmpty == true)
                const SizedBox(height: 16),
              _DetailRow(label: 'Wardrobe', value: wardrobe.name),
              _DetailRow(label: 'WID', value: wardrobe.wid),
              if (wardrobe.ownerUid?.trim().isNotEmpty == true)
                _DetailRow(label: 'Publisher UID', value: wardrobe.ownerUid!),
              if (wardrobe.ownerUsername?.trim().isNotEmpty == true)
                _DetailRow(label: 'Publisher', value: wardrobe.ownerUsername!),
              if (item.category?.trim().isNotEmpty == true)
                _DetailRow(label: 'Category', value: item.category!),
              if (item.material?.trim().isNotEmpty == true)
                _DetailRow(label: 'Material', value: item.material!),
              if (item.style?.trim().isNotEmpty == true)
                _DetailRow(label: 'Style', value: item.style!),
              if (_model3dUrl != null)
                _DetailRow(label: '3D Model', value: 'GLB available'),
              if (_angleViews.isNotEmpty)
                _DetailRow(
                  label: 'Angle Views',
                  value: '${_angleViews.length} images',
                ),
              const SizedBox(height: 12),
              Text(
                'Tags',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              if (_tags.isEmpty)
                Text(
                  'No tags available.',
                  style: TextStyle(fontSize: 12, color: textSecondary),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _tags
                      .map(
                        (tag) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.darkBackground
                                : AppColors.background,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              if (_model3dUrl != null) ...[
                const SizedBox(height: 20),
                Text(
                  '3D Model',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Drag to rotate the garment model and pinch to zoom.',
                  style: TextStyle(
                    fontSize: 12,
                    color: textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  height: 360,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: ModelViewer(
                    src: resolveFileUrl(_model3dUrl!),
                    alt: '3D garment model for ${item.name ?? 'shared item'}',
                    cameraControls: true,
                    autoRotate: true,
                    autoRotateDelay: 2500,
                    interactionPrompt: InteractionPrompt.auto,
                    loading: Loading.eager,
                    reveal: Reveal.auto,
                    backgroundColor: Colors.white,
                    ar: false,
                    disableTap: true,
                  ),
                ),
              ] else if (_angleViews.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'Reference Views',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                _AngleViewStrip(
                  angleViews: _angleViews,
                  textSecondary: textSecondary,
                  surfaceColor: surfaceColor,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemImage(Color textSecondary) {
    final imageUrl = _imageUrl;
    if (imageUrl == null || imageUrl.isEmpty) {
      return _imageFallback(textSecondary);
    }
    if (imageUrl.startsWith('data:')) {
      try {
        final uri = Uri.parse(imageUrl);
        final data = uri.data;
        if (data != null) {
          return Image.memory(data.contentAsBytes(), fit: BoxFit.contain);
        }
      } catch (_) {}
      return _imageFallback(textSecondary);
    }
    if (imageUrl.startsWith('data:image')) {
      try {
        final imageBytes = base64Decode(imageUrl.split(',')[1]);
        return Image.memory(imageBytes, fit: BoxFit.contain);
      } catch (_) {
        return _imageFallback(textSecondary);
      }
    }
    return CachedNetworkImage(
      imageUrl: resolveFileUrl(imageUrl),
      httpHeaders: ApiSession.authHeaders,
      fit: BoxFit.contain,
      placeholder: (context, url) =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      errorWidget: (context, url, error) => _imageFallback(textSecondary),
    );
  }

  Widget _imageFallback(Color textSecondary) {
    return Container(
      color: textSecondary.withValues(alpha: 0.1),
      child: Icon(Icons.checkroom_rounded, color: textSecondary, size: 40),
    );
  }
}

class _AngleViewStrip extends StatefulWidget {
  const _AngleViewStrip({
    required this.angleViews,
    required this.textSecondary,
    required this.surfaceColor,
  });

  final Map<int, String> angleViews;
  final Color textSecondary;
  final Color surfaceColor;

  @override
  State<_AngleViewStrip> createState() => _AngleViewStripState();
}

class _AngleViewStripState extends State<_AngleViewStrip> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final entries = widget.angleViews.entries.toList();
    final safeIndex = _index.clamp(0, entries.length - 1).toInt();
    final entry = entries[safeIndex];
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: widget.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 260, child: _buildImage(entry.value)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: entries.length <= 1
                      ? null
                      : () => setState(
                          () => _index =
                              (_index - 1 + entries.length) % entries.length,
                        ),
                  icon: const Icon(Icons.rotate_left_rounded, size: 16),
                  label: const Text('Prev'),
                ),
                Expanded(
                  child: Text(
                    _labelForAngle(entry.key),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: widget.textSecondary,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: entries.length <= 1
                      ? null
                      : () => setState(
                          () => _index = (_index + 1) % entries.length,
                        ),
                  icon: const Icon(Icons.rotate_right_rounded, size: 16),
                  label: const Text('Next'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _labelForAngle(int angle) {
    return switch (angle) {
      0 => 'Front',
      45 => 'Front-left',
      90 => 'Left',
      135 => 'Back-left',
      180 => 'Back',
      225 => 'Back-right',
      270 => 'Right',
      315 => 'Front-right',
      _ => '$angle deg',
    };
  }

  Widget _buildImage(String imageUrl) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: CachedNetworkImage(
        imageUrl: resolveFileUrl(imageUrl),
        httpHeaders: ApiSession.authHeaders,
        fit: BoxFit.contain,
        placeholder: (context, url) =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        errorWidget: (context, url, error) =>
            Icon(Icons.image_outlined, color: widget.textSecondary),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.textPrimary;
    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12, color: textPrimary, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
