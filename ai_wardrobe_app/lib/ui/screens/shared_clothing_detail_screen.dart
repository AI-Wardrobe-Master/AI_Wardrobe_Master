import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

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

  List<String> get _tags {
    final ordered = <String>[];
    final seen = <String>{};
    for (final tag in item.tagValues) {
      final normalized = tag.trim();
      if (normalized.isEmpty) {
        continue;
      }
      final key = normalized.toLowerCase();
      if (seen.add(key)) {
        ordered.add(normalized);
      }
    }
    return ordered;
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
          return Image.memory(data.contentAsBytes(), fit: BoxFit.cover);
        }
      } catch (_) {}
      return _imageFallback(textSecondary);
    }
    if (imageUrl.startsWith('data:image')) {
      try {
        final imageBytes = base64Decode(imageUrl.split(',')[1]);
        return Image.memory(imageBytes, fit: BoxFit.cover);
      } catch (_) {
        return _imageFallback(textSecondary);
      }
    }
    return CachedNetworkImage(
      imageUrl: resolveFileUrl(imageUrl),
      httpHeaders: ApiSession.authHeaders,
      fit: BoxFit.cover,
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
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
              style: TextStyle(fontSize: 13, color: textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
