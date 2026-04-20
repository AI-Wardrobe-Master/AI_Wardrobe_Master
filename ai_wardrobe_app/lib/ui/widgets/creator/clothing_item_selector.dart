import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../services/api_config.dart';
import '../../../theme/app_theme.dart';

class ClothingItemSelector extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onSelectionChanged;

  const ClothingItemSelector({
    super.key,
    required this.items,
    required this.selectedIds,
    required this.onSelectionChanged,
  });

  @override
  State<ClothingItemSelector> createState() => _ClothingItemSelectorState();
}

class _ClothingItemSelectorState extends State<ClothingItemSelector> {
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = Set<String>.from(widget.selectedIds);
  }

  void _toggleSelection(String itemId) {
    setState(() {
      if (_selectedIds.contains(itemId)) {
        _selectedIds.remove(itemId);
      } else {
        _selectedIds.add(itemId);
      }
    });
    widget.onSelectionChanged(_selectedIds);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textS = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

    if (widget.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined, size: 48, color: textS),
              const SizedBox(height: 8),
              Text(
                'No clothing items available',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textP,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please add some clothes first using the "Add clothes" option from the main menu.',
                style: TextStyle(fontSize: 12, color: textS),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemCount: widget.items.length,
      itemBuilder: (context, index) {
        final item = widget.items[index];
        final itemId = item['id'] as String? ?? item['id'].toString();
        final isSelected = _selectedIds.contains(itemId);
        final images = item['images'] as Map<String, dynamic>?;
        final imageUrl =
            images?['processedFrontUrl'] as String? ??
            images?['originalFrontUrl'] as String?;
        final name = item['name'] as String? ?? 'Unnamed';

        return GestureDetector(
          onTap: () => _toggleSelection(itemId),
          child: Stack(
            children: [
              Card(
                color: isDark ? AppColors.darkSurface : Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        child: _buildPreviewImage(imageUrl, textS),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: textP,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Positioned(top: 8, right: 8, child: _SelectedBadge()),
            ],
          ),
        );
      },
    );
  }
}

Widget _buildPreviewImage(String? imageUrl, Color textS) {
  if (imageUrl == null || imageUrl.isEmpty) {
    return Container(
      color: textS.withValues(alpha: 0.1),
      child: Icon(Icons.image_outlined, color: textS),
    );
  }

  if (imageUrl.startsWith('data:')) {
    try {
      final data = Uri.parse(imageUrl).data;
      if (data != null) {
        return Image.memory(
          data.contentAsBytes(),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: textS.withValues(alpha: 0.1),
            child: Icon(Icons.image_outlined, color: textS),
          ),
        );
      }
    } catch (_) {
      // Fall through to the placeholder below.
    }
    return Container(
      color: textS.withValues(alpha: 0.1),
      child: Icon(Icons.image_outlined, color: textS),
    );
  }

  return CachedNetworkImage(
    imageUrl: resolveFileUrl(imageUrl),
    httpHeaders: ApiSession.authHeaders,
    fit: BoxFit.cover,
    placeholder: (context, url) => Container(
      color: textS.withValues(alpha: 0.1),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    ),
    errorWidget: (context, url, error) => Container(
      color: textS.withValues(alpha: 0.1),
      child: Icon(Icons.image_outlined, color: textS),
    ),
  );
}

class _SelectedBadge extends StatelessWidget {
  const _SelectedBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.accentBlue,
        shape: BoxShape.circle,
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(Icons.check, color: Colors.white, size: 16),
      ),
    );
  }
}
