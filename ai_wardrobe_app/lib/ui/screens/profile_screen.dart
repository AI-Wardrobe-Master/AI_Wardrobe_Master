import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/theme_controller.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textS = isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    final accent = isDark ? AppColors.darkAccentBlue : AppColors.accentBlue;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Profile',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: textP,
                    letterSpacing: 0.2,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => _showProfileSettingsSheet(context),
                  icon: Icon(
                    Icons.settings_outlined,
                    color: textP,
                    size: 22,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Your digital wardrobe identity.',
              style: TextStyle(fontSize: 12, color: textS),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Icon(Icons.person, size: 30, color: textP),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your name',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: textP,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap to connect accounts later',
                      style: TextStyle(fontSize: 12, color: textS),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                _ProfileStat(label: 'Clothes', value: '0'),
                const SizedBox(width: 14),
                _ProfileStat(label: 'Outfits', value: '0'),
                const SizedBox(width: 14),
                _ProfileStat(label: 'Packs', value: '0'),
              ],
            ),
            const SizedBox(height: 24),
            Card(
              color: Theme.of(context).cardColor,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Virtual wardrobes',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textP,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Keep imported looks separate from your physical wardrobe.',
                      style: TextStyle(fontSize: 12, color: textS),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkBackground
                            : AppColors.background,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.inventory_2_rounded, color: accent),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Imported looks',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: textP,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: textS,
                          ),
                        ],
                      ),
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

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textS = isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: textP,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: textS),
            ),
          ],
        ),
      ),
    );
  }
}

void _showProfileSettingsSheet(BuildContext context) {
  bool darkMode = themeController.isDark;
  String language = 'English';

  final isDark = Theme.of(context).brightness == Brightness.dark;
  final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
  final textS = isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(context).dividerColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Settings',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: textP,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Language',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: textP,
                      ),
                    ),
                    subtitle: Text(
                      language,
                      style: TextStyle(fontSize: 12, color: textS),
                    ),
                    trailing: DropdownButton<String>(
                      value: language,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(
                          value: 'English',
                          child: Text('English'),
                        ),
                        DropdownMenuItem(
                          value: '中文',
                          child: Text('中文'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setModalState(() {
                          language = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: darkMode,
                    onChanged: (value) {
                      setModalState(() {
                        darkMode = value;
                      });
                      themeController.setDark(value);
                    },
                    title: Text(
                      'Dark mode',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: textP,
                      ),
                    ),
                    subtitle: Text(
                      darkMode ? 'On' : 'Off',
                      style: TextStyle(fontSize: 12, color: textS),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}
