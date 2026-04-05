import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_strings_provider.dart';
import '../../l10n/locale_controller.dart';
import '../../models/outfit_collection.dart';
import '../../models/reference_photo.dart';
import '../../services/outfit_collection_service.dart';
import '../../services/reference_photo_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_controller.dart';
import '../widgets/adaptive_image.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _picker = ImagePicker();
  late final Future<void> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = Future.wait<void>([
      ReferencePhotoService.ensureLoaded(),
      OutfitCollectionService.ensureLoaded(),
    ]).then((_) {});
  }

  Future<void> _pickReferencePhotos() async {
    try {
      final picked = await _picker.pickMultiImage(
        imageQuality: 90,
        maxWidth: 1400,
      );
      if (picked.isEmpty) {
        return;
      }
      await ReferencePhotoService.addPhotos(
        picked.map((image) => image.path).toList(),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${picked.length} reference photo(s) added to Profile.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to add reference photos: $error')),
      );
    }
  }

  Future<void> _selectPhoto(String? photoId) async {
    await ReferencePhotoService.selectPhoto(photoId);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          photoId == null
              ? 'Default demo reference is now active.'
              : 'Reference photo updated for Visualize.',
        ),
      ),
    );
  }

  Future<void> _removePhoto(ReferencePhoto photo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remove reference photo?'),
          content: Text(
            'Delete ${photo.label} from Profile and from the Visualize selector?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (ok != true) {
      return;
    }

    await ReferencePhotoService.removePhoto(photo.id);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${photo.label} removed.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStringsProvider.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textS = isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    final accent = isDark ? AppColors.darkAccentBlue : AppColors.accentBlue;

    return SafeArea(
      child: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, _) {
          return ValueListenableBuilder<List<OutfitCollection>>(
            valueListenable: OutfitCollectionService.listenable,
            builder: (context, collections, __) {
              final shareableCount = collections
                  .where((collection) => collection.isShareable)
                  .length;
              return ValueListenableBuilder<ReferencePhotoLibrary>(
                valueListenable: ReferencePhotoService.listenable,
                builder: (context, library, ___) {
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
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
                              border: Border.all(
                                color: Theme.of(context).dividerColor,
                              ),
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
                            label: 'References',
                            value: library.photos.length.toString(),
                          ),
                          const SizedBox(width: 14),
                          _ProfileStat(
                            label: s.statOutfits,
                            value: collections.length.toString(),
                          ),
                          const SizedBox(width: 14),
                          _ProfileStat(
                            label: 'Share Ready',
                            value: shareableCount.toString(),
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
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Full-Body Reference Photos',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: textP,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Upload one or more full-body photos here. The selected one will appear in Visualize.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: textS,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  FilledButton.icon(
                                    onPressed: _pickReferencePhotos,
                                    icon: const Icon(
                                      Icons.add_photo_alternate_outlined,
                                    ),
                                    label: const Text('Add Photos'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  _buildModeChip(
                                    label: library.selectedPhoto == null
                                        ? 'Using demo reference'
                                        : 'Using ${library.selectedPhoto!.label}',
                                    accent: accent,
                                    darkText: false,
                                  ),
                                  _buildModeChip(
                                    label:
                                        '${library.photos.length} personal photo(s)',
                                    accent: AppColors.accentYellow,
                                    darkText: true,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: () => _selectPhoto(null),
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Use Default Demo Reference'),
                              ),
                              const SizedBox(height: 16),
                              if (library.photos.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? AppColors.darkBackground
                                        : AppColors.background,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.accessibility_new_rounded,
                                        color: accent,
                                        size: 34,
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        'No personal full-body photos yet.',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: textP,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Add a few front-facing full-body references so Visualize can switch between them.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: textS,
                                          height: 1.5,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                )
                              else
                                SizedBox(
                                  height: 244,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: library.photos.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(width: 12),
                                    itemBuilder: (context, index) {
                                      final photo = library.photos[index];
                                      final isSelected =
                                          photo.id == library.selectedPhotoId;
                                      return _ReferencePhotoCard(
                                        photo: photo,
                                        isSelected: isSelected,
                                        textP: textP,
                                        textS: textS,
                                        onUse: () => _selectPhoto(photo.id),
                                        onDelete: () => _removePhoto(photo),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
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
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.inventory_2_rounded,
                                      color: accent,
                                    ),
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
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildModeChip({
    required String label,
    required Color accent,
    required bool darkText,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: darkText ? AppColors.textPrimary : accent,
        ),
      ),
    );
  }
}

class _ReferencePhotoCard extends StatelessWidget {
  const _ReferencePhotoCard({
    required this.photo,
    required this.isSelected,
    required this.textP,
    required this.textS,
    required this.onUse,
    required this.onDelete,
  });

  final ReferencePhoto photo;
  final bool isSelected;
  final Color textP;
  final Color textS;
  final VoidCallback onUse;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 164,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? AppColors.accentBlue : Theme.of(context).dividerColor,
          width: isSelected ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: const Color(0xFFF7F3EB)),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: AdaptiveImage(
                      imagePath: photo.imagePath,
                      fit: BoxFit.contain,
                      alignment: Alignment.topCenter,
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        isSelected ? 'Active' : 'Saved',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  photo.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: textP,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap Use to make this photo available in Visualize.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: textS,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onUse,
                        child: Text(isSelected ? 'Using' : 'Use'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline_rounded),
                      tooltip: 'Remove reference photo',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
              final languageLabel = languageCode == 'zh'
                  ? s.languageZh
                  : s.languageEnglish;
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
                        if (value == null) {
                          return;
                        }
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
