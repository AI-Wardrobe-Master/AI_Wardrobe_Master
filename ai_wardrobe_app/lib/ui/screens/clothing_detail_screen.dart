import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/wardrobe.dart';
import '../../services/clothing_api_service.dart';
import '../../services/local_clothing_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_remote_image.dart';

class ClothingDetailScreen extends StatefulWidget {
  const ClothingDetailScreen({
    super.key,
    required this.itemId,
    this.initialName,
    this.wardrobe,
    this.initialTags = const <String>[],
  });

  final String itemId;
  final String? initialName;
  final Wardrobe? wardrobe;
  final List<String> initialTags;

  @override
  State<ClothingDetailScreen> createState() => _ClothingDetailScreenState();
}

class _ClothingDetailScreenState extends State<ClothingDetailScreen> {
  Map<String, dynamic>? _item;
  bool _loading = true;
  bool _deleting = false;
  int _selectedSection = 0;
  int _selectedAngleIndex = 0;

  static const List<String> _angles = <String>[
    'Front',
    'Left',
    'Back',
    'Right',
  ];

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _textPrimary =>
      _isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
  Color get _textSecondary =>
      _isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
  Color get _surfaceColor => _isDark ? AppColors.darkSurface : Colors.white;
  Color get _accent =>
      _isDark ? AppColors.darkAccentBlue : AppColors.accentBlue;

  @override
  void initState() {
    super.initState();
    _loadItem();
  }

  Future<void> _loadItem() async {
    try {
      final response = await ClothingApiService.getClothingItem(widget.itemId);
      final data = response['data'] as Map<String, dynamic>? ?? response;
      if (!mounted) {
        return;
      }
      setState(() {
        _item = Map<String, dynamic>.from(data);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
    }
  }

  String get _title =>
      _item?['name'] as String? ?? widget.initialName ?? widget.itemId;

  String get _description {
    final description = _item?['description'] as String?;
    if (description != null && description.trim().isNotEmpty) {
      return description;
    }
    return 'No description yet.';
  }

  List<String> get _tags {
    final tags = <String>{...widget.initialTags};
    for (final raw
        in _item?['finalTags'] as List<dynamic>? ?? const <dynamic>[]) {
      if (raw is Map) {
        final value = raw['value']?.toString().trim();
        if (value != null && value.isNotEmpty) {
          tags.add(value);
        }
      }
    }
    for (final raw
        in _item?['customTags'] as List<dynamic>? ?? const <dynamic>[]) {
      final value = raw.toString().trim();
      if (value.isNotEmpty) {
        tags.add(value);
      }
    }
    return tags.toList();
  }

  String get _previewSvg =>
      _item?['previewSvg'] as String? ?? LocalClothingService.emptyPreviewSvg;

  String get _previewState =>
      _item?['previewSvgState'] as String? ?? 'PLACEHOLDER';

  bool get _previewAvailable => _item?['previewSvgAvailable'] as bool? ?? false;

  String? get _imageUrl {
    final images = _item?['images'] as Map? ?? const <String, dynamic>{};
    return images['processedFrontUrl'] as String? ??
        images['originalFrontUrl'] as String? ??
        _item?['imageUrl'] as String?;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            onPressed: _deleting ? null : _deleteItem,
            icon: _deleting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline_rounded),
            tooltip: 'Delete clothing card',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: _isDark
                            ? AppColors.darkBackground
                            : AppColors.background,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        children: [
                          _buildSectionButton(label: 'Info', index: 0),
                          _buildSectionButton(label: '3D Preview', index: 1),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _selectedSection == 0
                          ? _buildInfoSection()
                          : _buildPreviewSection(),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionButton({required String label, required int index}) {
    final selected = _selectedSection == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedSection = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? _surfaceColor : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: _isDark ? 0.16 : 0.05,
                      ),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? _textPrimary : _textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoSection() {
    return SingleChildScrollView(
      key: const ValueKey<String>('info'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildImageCard(),
          const SizedBox(height: 16),
          Text(
            _description,
            style: TextStyle(fontSize: 13, color: _textSecondary, height: 1.5),
          ),
          const SizedBox(height: 16),
          _DetailRow(
            label: 'Wardrobe',
            value: widget.wardrobe?.name ?? 'Unknown',
          ),
          if ((widget.wardrobe?.wid ?? '').isNotEmpty)
            _DetailRow(label: 'WID', value: widget.wardrobe!.wid),
          _DetailRow(label: 'Preview State', value: _previewState),
          _DetailRow(
            label: '3D Ready',
            value: _previewAvailable ? 'Yes' : 'Placeholder only',
          ),
          const SizedBox(height: 12),
          Text(
            'Tags',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          if (_tags.isEmpty)
            Text(
              'No tags yet.',
              style: TextStyle(fontSize: 12, color: _textSecondary),
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
                        color: _isDark
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
                          color: _textPrimary,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildPreviewSection() {
    return SingleChildScrollView(
      key: const ValueKey<String>('preview'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '3D Preview Browser',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _previewAvailable
                ? 'This item is using a blank SVG viewer placeholder so we can validate the browsing flow before the real 3D pipeline is deployed.'
                : 'The full 3D pipeline is not deployed yet, but the browsing interface is already wired and falls back to a blank SVG canvas.',
            style: TextStyle(fontSize: 13, color: _textSecondary, height: 1.5),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surfaceColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: SvgPicture.string(_previewSvg, fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _AngleButton(
                      icon: Icons.rotate_left_rounded,
                      label: 'Prev',
                      onTap: () {
                        setState(() {
                          _selectedAngleIndex =
                              (_selectedAngleIndex - 1 + _angles.length) %
                              _angles.length;
                        });
                      },
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _angles[_selectedAngleIndex],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _AngleButton(
                      icon: Icons.rotate_right_rounded,
                      label: 'Next',
                      onTap: () {
                        setState(() {
                          _selectedAngleIndex =
                              (_selectedAngleIndex + 1) % _angles.length;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List<Widget>.generate(_angles.length, (index) {
                    final selected = index == _selectedAngleIndex;
                    return ChoiceChip(
                      label: Text(_angles[index]),
                      selected: selected,
                      onSelected: (_) =>
                          setState(() => _selectedAngleIndex = index),
                    );
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageCard() {
    final imageUrl = _imageUrl;
    return Container(
      width: double.infinity,
      height: 280,
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: imageUrl == null || imageUrl.isEmpty
            ? Center(
                child: Icon(
                  Icons.checkroom_rounded,
                  size: 40,
                  color: _textSecondary,
                ),
              )
            : _buildAdaptiveImage(imageUrl),
      ),
    );
  }

  Widget _buildAdaptiveImage(String imageUrl) {
    return AppRemoteImage(
      url: imageUrl,
      fit: BoxFit.cover,
      placeholder: Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
      ),
      errorWidget: Icon(Icons.image_outlined, color: _textSecondary),
    );
  }

  Future<void> _deleteItem() async {
    if (_deleting) {
      return;
    }
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete clothing card?'),
        content: Text(
          'This will permanently remove "$_title" from your wardrobe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete != true || !mounted) {
      return;
    }

    setState(() => _deleting = true);
    try {
      await ClothingApiService.deleteClothingItem(widget.itemId);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _deleting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _AngleButton extends StatelessWidget {
  const _AngleButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
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
