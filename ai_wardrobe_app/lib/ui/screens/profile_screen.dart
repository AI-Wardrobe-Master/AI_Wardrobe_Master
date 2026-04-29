import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_strings_provider.dart';
import '../../l10n/locale_controller.dart';
import '../../services/auth_api_service.dart';
import '../../services/card_pack_api_service.dart';
import '../../services/clothing_api_service.dart';
import '../../services/face_profile_service.dart';
import '../../services/local_card_pack_service.dart';
import '../../services/local_clothing_service.dart';
import '../../services/me_api_service.dart';
import '../../services/wardrobe_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_controller.dart';
import 'face_crop_screen.dart';
import 'imported_looks_screen.dart';
import 'login_screen.dart';

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
  Map<String, dynamic>? _me;
  bool _loggingOut = false;
  FaceProfile _faceProfile = const FaceProfile(kind: FaceProfileKind.none);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStats();
    _loadFaceProfile();
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

    Map<String, dynamic>? me;
    try {
      me = await MeApiService.getMe();
    } catch (_) {}

    final clothingIds = <String>{};
    try {
      final apiItems = await ClothingApiService.listClothingItems(limit: 100);
      for (final item in apiItems) {
        final id = item['id']?.toString();
        if (id != null && id.isNotEmpty) {
          clothingIds.add(id);
        }
      }
    } catch (_) {}
    try {
      final localItems = await LocalClothingService.listItems();
      for (final item in localItems) {
        final id = item['id']?.toString();
        if (id != null && id.isNotEmpty) {
          clothingIds.add(id);
        }
      }
    } catch (_) {}
    final clothesCount = clothingIds.length;

    int packsCount = 0;
    try {
      final wardrobes = await WardrobeService.fetchWardrobes();
      packsCount += wardrobes.where((wardrobe) => !wardrobe.isMain).length;
    } catch (_) {}

    final packIds = <String>{};
    try {
      final apiPacks = await CardPackApiService.listCardPacks();
      for (final pack in apiPacks) {
        packIds.add(pack.id);
      }
      packsCount = packsCount > packIds.length ? packsCount : packIds.length;
    } catch (_) {}
    try {
      final localPacks = await LocalCardPackService.listCardPacks();
      for (final pack in localPacks) {
        if (!packIds.contains(pack.id)) {
          packIds.add(pack.id);
        }
      }
      packsCount = packsCount > packIds.length ? packsCount : packIds.length;
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _me = me;
      _clothesCount = clothesCount;
      _packsCount = packsCount;
      _loading = false;
    });
  }

  Future<void> _loadFaceProfile() async {
    final profile = await FaceProfileService.load();
    if (!mounted) return;
    setState(() => _faceProfile = profile);
  }

  Future<void> _showFacePhotoSourceSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textP = isDark
            ? AppColors.darkTextPrimary
            : AppColors.textPrimary;
        final textS = isDark
            ? AppColors.darkTextSecondary
            : AppColors.textSecondary;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose face photo source',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: textP,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Take a new photo or select one from your gallery, then crop the face area.',
                  style: TextStyle(fontSize: 12, color: textS),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Take Photo'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickFacePhoto(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Choose from Gallery'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickFacePhoto(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickFacePhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 95,
    );
    if (picked == null || !mounted) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    final cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => FaceCropScreen(imageBytes: bytes)),
    );
    if (cropped == null) return;

    await FaceProfileService.saveCustom(cropped);
    await _loadFaceProfile();
  }

  Future<void> _selectVirtualFace(FaceProfileKind kind) async {
    await FaceProfileService.saveVirtual(kind);
    await _loadFaceProfile();
  }

  Future<void> _clearFaceProfile() async {
    await FaceProfileService.clear();
    await _loadFaceProfile();
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    await AuthApiService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStringsProvider.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textS = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;
    final accent = isDark ? AppColors.darkAccentBlue : AppColors.accentBlue;

    final username = _me?['username'] as String? ?? s.yourName;
    final email = _me?['email'] as String? ?? 'Offline session';
    final uid = _me?['uid'] as String?;
    final userType = _me?['type'] as String?;

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
                  onPressed: _loggingOut ? null : _logout,
                  icon: Icon(Icons.logout_rounded, color: textP, size: 22),
                  tooltip: 'Logout',
                ),
                IconButton(
                  onPressed: () => _showProfileSettingsSheet(context),
                  icon: Icon(Icons.settings_outlined, color: textP, size: 22),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              s.profileSubtitle,
              style: TextStyle(fontSize: 12, color: textS),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 20, bottom: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _FaceAvatarPreview(profile: _faceProfile, size: 56),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                username,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: textP,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                email,
                                style: TextStyle(fontSize: 12, color: textS),
                              ),
                              if (userType != null && userType.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  userType == 'CREATOR'
                                      ? 'Creator account'
                                      : 'Standard account',
                                  style: TextStyle(fontSize: 11, color: textS),
                                ),
                              ],
                              if (uid != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'UID: $uid',
                                  style: TextStyle(fontSize: 11, color: textS),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _FaceSourceCard(
                      profile: _faceProfile,
                      onUpload: _showFacePhotoSourceSheet,
                      onSelectVirtual: _selectVirtualFace,
                      onClear: _clearFaceProfile,
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
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const ImportedLooksScreen(),
                                    ),
                                  );
                                },
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
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _loggingOut ? null : _logout,
                                icon: const Icon(Icons.logout_rounded),
                                label: Text(
                                  _loggingOut ? 'Logging out...' : 'Logout',
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
            ),
          ],
        ),
      ),
    );
  }
}

class _FaceSourceCard extends StatelessWidget {
  const _FaceSourceCard({
    required this.profile,
    required this.onUpload,
    required this.onSelectVirtual,
    required this.onClear,
  });

  final FaceProfile profile;
  final VoidCallback onUpload;
  final ValueChanged<FaceProfileKind> onSelectVirtual;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textS = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;
    final fill = isDark ? AppColors.darkBackground : AppColors.background;

    return Card(
      color: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _FaceAvatarPreview(profile: profile, size: 64),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Face photo for generation',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: textP,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _profileLabel(profile.kind),
                        style: TextStyle(fontSize: 12, color: textS),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: profile.hasSelection ? onClear : null,
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Clear face source',
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onUpload,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Add or change face photo'),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _VirtualFaceButton(
                      kind: FaceProfileKind.virtualMale,
                      selected: profile.kind == FaceProfileKind.virtualMale,
                      onTap: () => onSelectVirtual(FaceProfileKind.virtualMale),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _VirtualFaceButton(
                      kind: FaceProfileKind.virtualFemale,
                      selected: profile.kind == FaceProfileKind.virtualFemale,
                      onTap: () =>
                          onSelectVirtual(FaceProfileKind.virtualFemale),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _profileLabel(FaceProfileKind kind) {
    switch (kind) {
      case FaceProfileKind.custom:
        return 'Using cropped uploaded photo';
      case FaceProfileKind.virtualMale:
        return 'Using virtual male avatar';
      case FaceProfileKind.virtualFemale:
        return 'Using virtual female avatar';
      case FaceProfileKind.none:
        return 'No face source selected';
    }
  }
}

class _VirtualFaceButton extends StatelessWidget {
  const _VirtualFaceButton({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final FaceProfileKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textS = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;
    final selectedColor = isDark
        ? AppColors.darkAccentBlue
        : AppColors.accentBlue;
    final label = kind == FaceProfileKind.virtualMale
        ? 'Virtual male'
        : 'Virtual female';

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? selectedColor : Theme.of(context).dividerColor,
            width: selected ? 2 : 1,
          ),
          color: Theme.of(context).cardColor,
        ),
        child: Row(
          children: [
            _VirtualFaceAvatar(kind: kind, size: 42),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: textP,
                ),
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? selectedColor : textS,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _FaceAvatarPreview extends StatelessWidget {
  const _FaceAvatarPreview({required this.profile, required this.size});

  final FaceProfile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;

    Widget child;
    if (profile.kind == FaceProfileKind.custom &&
        profile.customImageBytes != null) {
      child = Image.memory(
        profile.customImageBytes!,
        fit: BoxFit.cover,
        width: size,
        height: size,
      );
    } else if (profile.kind == FaceProfileKind.virtualMale ||
        profile.kind == FaceProfileKind.virtualFemale) {
      child = _VirtualFaceAvatar(kind: profile.kind, size: size);
    } else {
      child = Icon(Icons.person, size: size * 0.54, color: textP);
    }

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: child,
    );
  }
}

class _VirtualFaceAvatar extends StatelessWidget {
  const _VirtualFaceAvatar({required this.kind, required this.size});

  final FaceProfileKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _VirtualFacePainter(kind: kind),
    );
  }
}

class _VirtualFacePainter extends CustomPainter {
  const _VirtualFacePainter({required this.kind});

  final FaceProfileKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final isFemale = kind == FaceProfileKind.virtualFemale;
    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isFemale
            ? const [Color(0xFFFFD7E5), Color(0xFFE3F2FF)]
            : const [Color(0xFFD8E8FF), Color(0xFFE9F2E5)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    final center = Offset(size.width / 2, size.height / 2);
    final skin = Paint()..color = const Color(0xFFEBC0A2);
    final hair = Paint()
      ..color = isFemale ? const Color(0xFF4B2C24) : const Color(0xFF263238);
    final shirt = Paint()
      ..color = isFemale ? const Color(0xFF8E5CF7) : const Color(0xFF1E5B8A);

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, size.height * 0.86),
        width: size.width * 0.74,
        height: size.height * 0.34,
      ),
      shirt,
    );
    canvas.drawCircle(
      Offset(center.dx, size.height * 0.45),
      size.width * 0.22,
      skin,
    );
    if (isFemale) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(center.dx, size.height * 0.43),
          width: size.width * 0.58,
          height: size.height * 0.68,
        ),
        hair,
      );
      canvas.drawCircle(
        Offset(center.dx, size.height * 0.47),
        size.width * 0.21,
        skin,
      );
    } else {
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(center.dx, size.height * 0.35),
          width: size.width * 0.48,
          height: size.height * 0.34,
        ),
        3.1,
        3.15,
        false,
        hair..strokeWidth = size.width * 0.16,
      );
    }

    final eye = Paint()..color = const Color(0xFF2A2A2A);
    canvas.drawCircle(Offset(size.width * 0.42, size.height * 0.45), 1.4, eye);
    canvas.drawCircle(Offset(size.width * 0.58, size.height * 0.45), 1.4, eye);
    final smile = Paint()
      ..color = const Color(0xFF8C4A3A)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx, size.height * 0.5),
        width: size.width * 0.16,
        height: size.height * 0.12,
      ),
      0.2,
      2.7,
      false,
      smile,
    );
  }

  @override
  bool shouldRepaint(covariant _VirtualFacePainter oldDelegate) {
    return oldDelegate.kind != kind;
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textS = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

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
            Text(label, style: TextStyle(fontSize: 11, color: textS)),
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
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.darkMode, style: TextStyle(color: textP)),
                    subtitle: Text(
                      darkMode ? s.on : s.off,
                      style: TextStyle(color: textS),
                    ),
                    value: darkMode,
                    onChanged: (value) {
                      setModalState(() => darkMode = value);
                      themeController.setDark(value);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.language, style: TextStyle(color: textP)),
                    subtitle: Text(
                      languageLabel,
                      style: TextStyle(color: textS),
                    ),
                    trailing: const Icon(Icons.language_rounded),
                    onTap: () async {
                      final next = languageCode == 'zh' ? 'en' : 'zh';
                      localeController.setLocale(Locale(next));
                      if (context.mounted) {
                        setModalState(() => languageCode = next);
                      }
                    },
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
