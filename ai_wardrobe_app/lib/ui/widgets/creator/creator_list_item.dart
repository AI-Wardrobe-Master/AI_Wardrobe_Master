import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../models/creator.dart';
import '../../../services/api_config.dart';
import '../../../theme/app_theme.dart';

class CreatorListItem extends StatelessWidget {
  final Creator creator;
  final VoidCallback onTap;

  const CreatorListItem({
    super.key,
    required this.creator,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textS = isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDark ? AppColors.darkSurface : Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: textS.withValues(alpha: 0.1),
                backgroundImage: creator.avatarUrl != null
                    ? CachedNetworkImageProvider(
                        creator.avatarUrl!.startsWith('http')
                            ? creator.avatarUrl!
                            : '$fileBaseUrl${creator.avatarUrl}',
                      )
                    : null,
                child: creator.avatarUrl == null
                    ? Text(
                        creator.displayName.isNotEmpty
                            ? creator.displayName[0].toUpperCase()
                            : '?',
                        style: TextStyle(color: textP, fontSize: 18),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            creator.displayName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: textP,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (creator.isVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified, size: 16, color: Colors.blue),
                        ],
                      ],
                    ),
                    if (creator.brandName != null && creator.brandName!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        creator.brandName!,
                        style: TextStyle(fontSize: 12, color: textS),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (creator.bio != null && creator.bio!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        creator.bio!,
                        style: TextStyle(fontSize: 12, color: textS),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.people_outline, size: 14, color: textS),
                        const SizedBox(width: 4),
                        Text(
                          '${creator.followerCount}',
                          style: TextStyle(fontSize: 12, color: textS),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.style_outlined, size: 14, color: textS),
                        const SizedBox(width: 4),
                        Text(
                          '${creator.packCount} packs',
                          style: TextStyle(fontSize: 12, color: textS),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
