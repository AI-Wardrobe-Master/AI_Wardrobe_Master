import 'package:flutter/material.dart';

import '../../l10n/app_strings_provider.dart';
import '../../theme/app_theme.dart';

class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStringsProvider.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textS = isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.discoverTitle,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: textP,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              s.discoverSubtitle,
              style: TextStyle(
                fontSize: 12,
                color: textS,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.local_fire_department_outlined,
                      size: 40,
                      color: textS,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s.noCreatorPacksYet,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textP,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.onceCreatorsShare,
                      style: TextStyle(
                        fontSize: 12,
                        color: textS,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
