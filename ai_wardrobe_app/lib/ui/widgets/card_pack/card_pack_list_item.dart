import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../models/card_pack.dart';
import '../../../services/api_config.dart';
import '../../../theme/app_theme.dart';

class CardPackListItem extends StatelessWidget {
  final CardPack pack;
  final VoidCallback onTap;

  const CardPackListItem({super.key, required this.pack, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textS = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDark ? AppColors.darkSurface : Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _buildCover(textS),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pack.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textP,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (pack.description != null &&
                        pack.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        pack.description!,
                        style: TextStyle(fontSize: 12, color: textS),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 14,
                          color: textS,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${pack.itemCount} items',
                          style: TextStyle(fontSize: 12, color: textS),
                        ),
                        if (pack.importCount > 0) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.download_outlined, size: 14, color: textS),
                          const SizedBox(width: 4),
                          Text(
                            '${pack.importCount} imports',
                            style: TextStyle(fontSize: 12, color: textS),
                          ),
                        ],
                      ],
                    ),
                    if (pack.creatorUid != null ||
                        pack.wardrobeWid != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        [
                          if (pack.creatorUid?.isNotEmpty == true)
                            'UID: ${pack.creatorUid}',
                          if (pack.wardrobeWid?.isNotEmpty == true)
                            'WID: ${pack.wardrobeWid}',
                        ].join('  •  '),
                        style: TextStyle(fontSize: 11, color: textS),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCover(Color textS) {
    if (pack.coverImageUrl == null || pack.coverImageUrl!.isEmpty) {
      return Container(
        width: 80,
        height: 80,
        color: textS.withValues(alpha: 0.1),
        child: Icon(Icons.style_outlined, color: textS),
      );
    }

    if (pack.coverImageUrl!.startsWith('data:image')) {
      try {
        final imageBytes = base64Decode(pack.coverImageUrl!.split(',')[1]);
        return Image.memory(
          imageBytes,
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            width: 80,
            height: 80,
            color: textS.withValues(alpha: 0.1),
            child: Icon(Icons.image_outlined, color: textS),
          ),
        );
      } catch (_) {
        return Container(
          width: 80,
          height: 80,
          color: textS.withValues(alpha: 0.1),
          child: Icon(Icons.image_outlined, color: textS),
        );
      }
    }

    return CachedNetworkImage(
      imageUrl: resolveFileUrl(pack.coverImageUrl!),
      httpHeaders: ApiSession.authHeaders,
      width: 80,
      height: 80,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        width: 80,
        height: 80,
        color: textS.withValues(alpha: 0.1),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      errorWidget: (context, url, error) => Container(
        width: 80,
        height: 80,
        color: textS.withValues(alpha: 0.1),
        child: Icon(Icons.image_outlined, color: textS),
      ),
    );
  }
}
