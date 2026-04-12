import 'package:flutter/material.dart';

import '../../l10n/app_strings_provider.dart';
import '../../l10n/locale_controller.dart';
import '../../services/card_pack_api_service.dart';
import '../../services/clothing_api_service.dart';
import '../../services/local_card_pack_service.dart';
import '../../services/local_clothing_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_controller.dart';
import 'imported_looks_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
  int _clothesCount = 0;
  int _packsCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStats();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted) {
      _loadStats();
    }
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);

    int clothesCount = 0;
    try {
      final apiItems = await ClothingApiService.listClothingItems(limit: 100);
      clothesCount += apiItems.length;
    } catch (_) {}
    try {
      final localItems = await LocalClothingService.listItems();
      clothesCount += localItems.length;
    } catch (_) {}

    int packsCount = 0;
    final packIds = <String>{};
    try {
      final apiPacks = await CardPackApiService.listCardPacks();
      for (final pack in apiPacks) {
        packIds.add(pack.id);
      }
      packsCount = packIds.length;
    } catch (_) {}
    try {
      final localPacks = await LocalCardPackService.listCardPacks();
      for (final pack in localPacks) {
        if (!packIds.contains(pack.id)) {
          packIds.add(pack.id);
          packsCount++;
        }
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _clothesCount = clothesCount;
      _packsCount = packsCount;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStringsProvider.of(context);
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
                  s.profileTitle,
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
              s.profileSubtitle,
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
                      s.yourName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: textP,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.tapToConnectAccounts,
                      style: TextStyle(fontSize: 12, color: textS),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                _ProfileStat(
                  label: s.statClothes,
                  value: _loading ? '...' : '$_clothesCount',
                ),
                const SizedBox(width: 14),
                _ProfileStat(label: s.statOutfits, value: '0'),
                const SizedBox(width: 14),
                _ProfileStat(
                  label: s.statPacks,
                  value: _loading ? '...' : '$_packsCount',
                ),
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
                      s.virtualWardrobes,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textP,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.keepImportedSeparate,
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
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ImportedLooksScreen(),
                            ),
                          );
                        },
                        child: Row(
                          children: [
                            Icon(Icons.inventory_2_rounded, color: accent),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                s.importedLooks,
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
  final s = AppStringsProvider.of(context);
  String languageCode = localeController.locale.languageCode;

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
              final languageLabel = languageCode == 'zh' ? s.languageZh : s.languageEnglish;
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
                    s.settings,
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
                      s.language,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: textP,
                      ),
                    ),
                    subtitle: Text(
                      languageLabel,
                      style: TextStyle(fontSize: 12, color: textS),
                    ),
                    trailing: DropdownButton<String>(
                      value: languageCode,
                      underline: const SizedBox.shrink(),
                      items: [
                        DropdownMenuItem(
                          value: 'en',
                          child: Text(s.languageEnglish),
                        ),
                        DropdownMenuItem(
                          value: 'zh',
                          child: Text(s.languageZh),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setModalState(() {
                          languageCode = value;
                        });
                        localeController.setLocale(Locale(value));
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
                      s.darkMode,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: textP,
                      ),
                    ),
                    subtitle: Text(
                      darkMode ? s.on : s.off,
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
