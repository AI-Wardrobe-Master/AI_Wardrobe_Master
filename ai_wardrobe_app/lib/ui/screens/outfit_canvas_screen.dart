import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_strings_provider.dart';
import '../../models/outfit_collection.dart';
import '../../models/reference_photo.dart';
import '../../models/wardrobe.dart';
import '../../services/outfit_collection_service.dart';
import '../../services/reference_photo_service.dart';
import '../../services/wardrobe_service.dart';
import '../../state/current_wardrobe_controller.dart';
import '../../theme/app_theme.dart';
import 'capture/clothing_result_screen.dart';
import '../widgets/adaptive_image.dart';

const _defaultReferenceImagePath =
    'assets/visualization/source/full_body_reference.jpg';
const _previewImagePath =
    'assets/visualization/preview/generated_outfit_preview.jpg';
const _downloadChannel = MethodChannel('ai_wardrobe_app/downloads');

class OutfitCanvasScreen extends StatefulWidget {
  const OutfitCanvasScreen({
    super.key,
    this.catalogItems,
    this.openDetailOverride,
    this.catalogWardrobeName,
  });

  final List<WardrobeItemWithClothing>? catalogItems;
  final Future<void> Function(BuildContext context, String clothingItemId)?
  openDetailOverride;
  final String? catalogWardrobeName;

  @override
  State<OutfitCanvasScreen> createState() => _OutfitCanvasScreenState();
}

class _OutfitCanvasScreenState extends State<OutfitCanvasScreen> {
  static const _maxLayerCount = 3;

  final Map<_BodyZone, List<_WornGarment>> _wornByZone = {
    for (final zone in _BodyZone.values) zone: <_WornGarment>[],
  };

  final Map<_BodyZone, List<_GarmentItem>> _catalog = {
    for (final zone in _BodyZone.values) zone: <_GarmentItem>[],
  };

  bool _catalogLoading = true;
  bool _catalogLoadInProgress = false;
  String? _catalogError;
  String? _catalogWardrobeName;
  String? _loadedWardrobeId;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _textPrimary =>
      _isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
  Color get _textSecondary =>
      _isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
  Color get _panelColor =>
      _isDark ? AppColors.darkSurface : Colors.white.withOpacity(0.9);
  Color get _accent =>
      _isDark ? AppColors.darkAccentBlue : AppColors.accentBlue;
  ReferencePhoto? get _selectedReferencePhoto =>
      ReferencePhotoService.selectedPhoto;
  String get _activeReferenceImagePath =>
      _selectedReferencePhoto?.imagePath ?? _defaultReferenceImagePath;
  int get _availableCatalogCount =>
      _catalog.values.fold<int>(0, (sum, items) => sum + items.length);
  int get _selectedCount =>
      _wornByZone.values.fold<int>(0, (sum, items) => sum + items.length);
  bool get _hasSelection => _selectedCount > 0;
  bool get _canClear => _hasSelection;
  bool get _canGeneratePreview => _hasSelection;

  @override
  void initState() {
    super.initState();
    CurrentWardrobeController.listenable.addListener(_handleWardrobeChanged);
    ReferencePhotoService.listenable.addListener(_handleReferencePhotoChange);
    ReferencePhotoService.ensureLoaded();
    _bootstrapCatalog();
  }

  @override
  void dispose() {
    CurrentWardrobeController.listenable.removeListener(_handleWardrobeChanged);
    ReferencePhotoService.listenable.removeListener(_handleReferencePhotoChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStringsProvider.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.visualizeTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Visualization Studio',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Use the provided full-body reference, tap a body hotspot, and assign garments with clear layer control for upper and lower body.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: _textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _buildInfoChip(
                          _catalogWardrobeName == null
                              ? 'Wardrobe pending'
                              : 'Wardrobe: ${_catalogWardrobeName!}',
                          _accent,
                        ),
                        _buildInfoChip(
                          '$_selectedCount items selected',
                          AppColors.accentYellow,
                          darkText: true,
                        ),
                        _buildInfoChip(
                          _catalogLoading
                              ? 'Loading wardrobe items'
                              : '$_availableCatalogCount wardrobe items linked',
                          const Color(0xFF3D5A80),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 900;
                        if (isWide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 6, child: _buildCanvasCard()),
                              const SizedBox(width: 16),
                              Expanded(flex: 5, child: _buildSelectionCard()),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            _buildCanvasCard(),
                            const SizedBox(height: 16),
                            _buildSelectionCard(),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(
                color: _isDark ? AppColors.darkSurface : Colors.white,
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _canClear ? _clearSelection : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _textPrimary,
                        side: BorderSide(color: Theme.of(context).dividerColor),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(s.clear),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _canGeneratePreview
                          ? _showPreviewDialog
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(s.generatePreview),
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

  Widget _buildCanvasCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panelColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(_isDark ? 0.18 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Reference Canvas',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _showReferencePhotoSheet,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _textPrimary,
                  side: BorderSide(color: Theme.of(context).dividerColor),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                icon: const Icon(Icons.photo_library_outlined, size: 16),
                label: const Text('Reference'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _selectedReferencePhoto == null
                ? 'Tap a translucent plus hotspot to open a picker. Selected garments appear as compact stack tags that stay clear of the hotspot, and each tag opens garment details.'
                : 'Using ${_selectedReferencePhoto!.label}. Tap the small reference button to switch between uploaded full-body photos.',
            style: TextStyle(fontSize: 12, height: 1.5, color: _textSecondary),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildInfoChip(
                _selectedReferencePhoto == null
                    ? 'Demo reference active'
                    : 'Custom reference active',
                _selectedReferencePhoto == null
                    ? AppColors.accentYellow
                    : _accent,
                darkText: _selectedReferencePhoto == null,
              ),
              if (_selectedReferencePhoto != null)
                _buildInfoChip(
                  _selectedReferencePhoto!.label,
                  const Color(0xFF3D5A80),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: AspectRatio(
              aspectRatio: 448 / 768,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final height = constraints.maxHeight;
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: _isDark
                                  ? const [
                                      Color(0xFF141920),
                                      Color(0xFF1D2430),
                                      Color(0xFF0F141B),
                                    ]
                                  : const [
                                      Color(0xFFF6F1E8),
                                      Color(0xFFEAE4DA),
                                      Color(0xFFF1ECE2),
                                    ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: -40,
                        right: -30,
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.accentYellow.withOpacity(0.18),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: -50,
                        left: -24,
                        child: Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _accent.withOpacity(0.12),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 14,
                        top: 14,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _selectedReferencePhoto == null
                                ? 'Reference Photo'
                                : _selectedReferencePhoto!.label,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 26,
                            vertical: 12,
                          ),
                          child: AdaptiveImage(
                            imagePath: _activeReferenceImagePath,
                            fit: BoxFit.contain,
                            alignment: Alignment.topCenter,
                          ),
                        ),
                      ),
                      for (final zone in _BodyZone.values) ...[
                        _buildCanvasTagStack(zone, width, height),
                        _buildHotspot(zone, width, height),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panelColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Current Styling Map',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
              ),
              IconButton(
                onPressed: widget.catalogItems != null ? null : _loadCatalog,
                tooltip: 'Refresh wardrobe items',
                icon: const Icon(Icons.refresh_rounded),
                color: _accent,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Layer 1 stays closest to the body. Higher layer numbers move outward for jackets, coats, trousers, or additional bottom layers.',
            style: TextStyle(fontSize: 12, height: 1.5, color: _textSecondary),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = constraints.maxWidth >= 620
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final zone in _BodyZone.values)
                    SizedBox(width: tileWidth, child: _buildZoneTile(zone)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildZoneTile(_BodyZone zone) {
    final selections = _sortedSelections(zone);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _isDark
            ? AppColors.darkBackground.withOpacity(0.45)
            : const Color(0xFFF8F5EF),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: zone.accent.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(zone.icon, color: zone.accent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      zone.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                    ),
                    Text(
                      zone.summary,
                      style: TextStyle(fontSize: 11, color: _textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _openPicker(zone),
                icon: const Icon(Icons.add_circle_outline_rounded),
                color: _accent,
                tooltip: 'Open ${zone.title.toLowerCase()} picker',
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_catalogLoading)
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: zone.accent,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Loading wardrobe items...',
                  style: TextStyle(fontSize: 12, color: _textSecondary),
                ),
              ],
            )
          else if (_catalogError != null && (_catalog[zone]?.isEmpty ?? true))
            Text(
              _catalogError!,
              style: TextStyle(fontSize: 12, color: _textSecondary),
            )
          else if (selections.isEmpty)
            Text(
              'No item selected yet.',
              style: TextStyle(fontSize: 12, color: _textSecondary),
            )
          else
            Column(
              children: [
                for (final worn in selections) _buildSelectedRow(zone, worn),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSelectedRow(_BodyZone zone, _WornGarment worn) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _isDark
            ? AppColors.darkSurface.withOpacity(0.72)
            : Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openGarmentDetail(worn.item),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: worn.item.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(worn.item.icon, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        worn.item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                      Text(
                        zone.layered
                            ? 'Layer ${worn.layer} • ${worn.item.material}'
                            : worn.item.material,
                        style: TextStyle(fontSize: 11, color: _textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _removeItem(zone, worn.item.id);
                    });
                  },
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded),
                  color: _textSecondary,
                  tooltip: 'Remove item',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHotspot(_BodyZone zone, double width, double height) {
    final config = _zoneOverlay[zone]!;
    return Positioned(
      left: width * config.hotspot.dx - 33,
      top: height * config.hotspot.dy - 34,
      child: Tooltip(
        message: 'Select ${zone.title.toLowerCase()} garments',
        child: GestureDetector(
          onTap: () => _openPicker(zone),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isDark
                      ? Colors.white.withOpacity(0.14)
                      : Colors.white.withOpacity(0.62),
                  border: Border.all(
                    color: zone.accent.withOpacity(0.85),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(_isDark ? 0.28 : 0.08),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(Icons.add_rounded, size: 28, color: zone.accent),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _isDark
                      ? Colors.black.withOpacity(0.4)
                      : Colors.white.withOpacity(0.82),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  zone.shortTitle,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCanvasTagStack(_BodyZone zone, double width, double height) {
    final selections = _sortedSelections(zone);
    if (selections.isEmpty) {
      return const SizedBox.shrink();
    }

    final config = _zoneOverlay[zone]!;
    final horizontalOffset = zone.layered ? 7.0 : 0.0;
    final verticalOffset = zone.layered ? 9.0 : 0.0;
    final cardWidth = zone.layered ? 64.0 : 96.0;
    final cardHeight = zone.layered ? 42.0 : 46.0;
    final stackWidth = cardWidth + ((selections.length - 1) * horizontalOffset);
    final stackHeight = cardHeight + ((selections.length - 1) * verticalOffset);
    final hotspotX = width * config.hotspot.dx;
    final hotspotY = height * config.hotspot.dy;
    final left = (hotspotX - stackWidth - 22)
        .clamp(10.0, width - stackWidth - 10.0)
        .toDouble();
    final topTarget = switch (zone) {
      _BodyZone.head => hotspotY - (cardHeight * 0.6),
      _BodyZone.upper => hotspotY - (stackHeight * 0.55),
      _BodyZone.lower => hotspotY - (stackHeight * 0.72),
      _BodyZone.feet => hotspotY - stackHeight - 20,
    };
    final top = topTarget.clamp(10.0, height - stackHeight - 10.0).toDouble();

    return Positioned(
      left: left,
      top: top,
      child: SizedBox(
        width: stackWidth,
        height: stackHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var index = 0; index < selections.length; index++)
              Positioned(
                left: index * horizontalOffset,
                top: index * verticalOffset,
                child: _buildCanvasTag(zone, selections[index]),
              ),
            if (zone.layered && selections.length > 1)
              Positioned(
                right: -6,
                top: -6,
                child: IgnorePointer(
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: _textPrimary,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${selections.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvasTag(_BodyZone zone, _WornGarment worn) {
    final isLayered = zone.layered;
    final surfaceColor = _isDark
        ? Colors.black.withOpacity(0.42)
        : Colors.white.withOpacity(0.9);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openGarmentDetail(worn.item),
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          width: isLayered ? 64 : 96,
          height: isLayered ? 42 : 46,
          padding: EdgeInsets.symmetric(
            horizontal: isLayered ? 5 : 6,
            vertical: isLayered ? 4 : 6,
          ),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Theme.of(context).dividerColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(_isDark ? 0.18 : 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: isLayered
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: worn.item.accent,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        worn.item.icon,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'L${worn.layer}',
                      style: TextStyle(
                        fontSize: 10,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: worn.item.accent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        worn.item.icon,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            worn.item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _textPrimary,
                            ),
                          ),
                          Text(
                            'Wearing',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9,
                              color: _textSecondary,
                            ),
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

  Future<void> _bootstrapCatalog() async {
    if (widget.catalogItems != null) {
      _applyCatalogEntries(
        widget.catalogItems!,
        wardrobeId: 'preview-catalog',
        wardrobeName: widget.catalogWardrobeName ?? 'Preview Wardrobe',
      );
      return;
    }
    await _loadCatalog();
  }

  void _handleWardrobeChanged() {
    if (widget.catalogItems != null) {
      return;
    }
    final wardrobeId = CurrentWardrobeController.currentWardrobeId;
    if (_catalogLoadInProgress || wardrobeId == _loadedWardrobeId) {
      return;
    }
    _loadCatalog();
  }

  void _handleReferencePhotoChange() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _loadCatalog() async {
    if (_catalogLoadInProgress) {
      return;
    }

    _catalogLoadInProgress = true;
    if (mounted) {
      setState(() {
        _catalogLoading = true;
        _catalogError = null;
      });
    }

    try {
      final wardrobes = await WardrobeService.fetchWardrobes();
      if (!mounted) {
        return;
      }

      if (wardrobes.isEmpty) {
        _applyCatalogEntries(
          const <WardrobeItemWithClothing>[],
          wardrobeId: null,
          wardrobeName: null,
          error: 'Create a wardrobe first to use the visualize studio.',
        );
        return;
      }

      final requestedWardrobeId = CurrentWardrobeController.currentWardrobeId;
      final selectedWardrobe =
          wardrobes.cast<Wardrobe?>().firstWhere(
            (wardrobe) => wardrobe?.id == requestedWardrobeId,
            orElse: () => null,
          ) ??
          wardrobes.first;

      _loadedWardrobeId = selectedWardrobe.id;
      CurrentWardrobeController.setCurrentWardrobeId(selectedWardrobe.id);

      final items = await WardrobeService.fetchWardrobeItems(
        selectedWardrobe.id,
      );
      if (!mounted) {
        return;
      }

      _applyCatalogEntries(
        items,
        wardrobeId: selectedWardrobe.id,
        wardrobeName: selectedWardrobe.name,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _applyCatalogEntries(
        const <WardrobeItemWithClothing>[],
        wardrobeId: CurrentWardrobeController.currentWardrobeId,
        wardrobeName: _catalogWardrobeName,
        error:
            'Unable to load wardrobe items right now. Pull down in Wardrobe or try again.',
      );
    } finally {
      _catalogLoadInProgress = false;
    }
  }

  void _applyCatalogEntries(
    List<WardrobeItemWithClothing> entries, {
    required String? wardrobeId,
    required String? wardrobeName,
    String? error,
  }) {
    final nextCatalog = {
      for (final zone in _BodyZone.values) zone: <_GarmentItem>[],
    };
    final refreshedItems = <String, _GarmentItem>{};

    for (final entry in entries) {
      final garment = _garmentFromWardrobeEntry(entry);
      if (garment == null) {
        continue;
      }
      nextCatalog[garment.zone]!.add(garment);
      refreshedItems[garment.id] = garment;
    }

    for (final zone in _BodyZone.values) {
      nextCatalog[zone]!.sort(
        (left, right) =>
            left.title.toLowerCase().compareTo(right.title.toLowerCase()),
      );
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _loadedWardrobeId = wardrobeId;
      _catalogWardrobeName = wardrobeName;
      _catalogError = error;
      _catalogLoading = false;

      for (final zone in _BodyZone.values) {
        _catalog[zone]!
          ..clear()
          ..addAll(nextCatalog[zone]!);

        final refreshedZoneSelections = <_WornGarment>[];
        for (final worn in _wornByZone[zone]!) {
          final refreshed = refreshedItems[worn.item.id];
          if (refreshed != null) {
            refreshedZoneSelections.add(
              _WornGarment(item: refreshed, layer: worn.layer),
            );
          }
        }
        _wornByZone[zone]!
          ..clear()
          ..addAll(refreshedZoneSelections);
      }
    });
  }

  _GarmentItem? _garmentFromWardrobeEntry(WardrobeItemWithClothing entry) {
    final clothing = entry.clothingItem;
    if (clothing == null) {
      return null;
    }

    final normalizedTags = _normalizeTags(clothing.finalTags);
    final zone = _inferZone(
      clothing.name ?? entry.clothingItemId,
      normalizedTags,
    );
    if (zone == null) {
      return null;
    }

    final categoryValue = _tagValue(normalizedTags, const ['category', 'type']);
    final materialValue = _tagValue(normalizedTags, const [
      'material',
      'fabric',
      'textile',
    ]);
    final styleValue = _tagValue(normalizedTags, const ['style']);
    final colorValue = _tagValue(normalizedTags, const ['color']);

    final title = (clothing.name?.trim().isNotEmpty ?? false)
        ? clothing.name!.trim()
        : _titleFromCategory(categoryValue, zone);
    final material =
        materialValue ??
        _titleFromCategory(categoryValue, zone, fallback: 'Wardrobe item');
    final fitNote = _buildFitNote(
      description: null,
      styleValue: styleValue,
      colorValue: colorValue,
      categoryValue: categoryValue,
      zone: zone,
    );

    return _GarmentItem(
      id: entry.clothingItemId,
      clothingItemId: entry.clothingItemId,
      title: title,
      fitNote: fitNote,
      material: material,
      icon: _iconFor(categoryValue, zone),
      accent: _accentFor(categoryValue, zone),
      zone: zone,
      categoryLabel: _titleFromCategory(
        categoryValue,
        zone,
        fallback: zone.title,
      ),
      sourceLabel: clothing.source == 'IMPORTED'
          ? 'Virtual item'
          : 'Owned item',
    );
  }

  List<Map<String, String>> _normalizeTags(List<dynamic> tags) {
    return tags
        .whereType<Map>()
        .map(
          (tag) => <String, String>{
            'key': tag['key']?.toString().trim().toLowerCase() ?? '',
            'value': tag['value']?.toString().trim() ?? '',
          },
        )
        .where((tag) => tag['key']!.isNotEmpty && tag['value']!.isNotEmpty)
        .toList();
  }

  String? _tagValue(List<Map<String, String>> tags, List<String> keys) {
    for (final key in keys) {
      for (final tag in tags) {
        if (tag['key'] == key && tag['value']!.isNotEmpty) {
          return tag['value'];
        }
      }
    }
    return null;
  }

  _BodyZone? _inferZone(String title, List<Map<String, String>> tags) {
    final tokens = <String>{
      _normalizeToken(title),
      for (final tag in tags) _normalizeToken(tag['value']!),
    };

    if (tokens.any(_headKeywords.contains)) {
      return _BodyZone.head;
    }
    if (tokens.any(_feetKeywords.contains)) {
      return _BodyZone.feet;
    }
    if (tokens.any(_lowerKeywords.contains)) {
      return _BodyZone.lower;
    }
    if (tokens.any(_upperKeywords.contains)) {
      return _BodyZone.upper;
    }
    return null;
  }

  String _normalizeToken(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('_', '')
        .replaceAll('-', '')
        .replaceAll(' ', '');
  }

  String _titleFromCategory(
    String? categoryValue,
    _BodyZone zone, {
    String fallback = 'Wardrobe item',
  }) {
    if (categoryValue == null || categoryValue.trim().isEmpty) {
      return fallback;
    }

    final compact = _normalizeToken(categoryValue);
    final mapped = _categoryTitles[compact];
    if (mapped != null) {
      return mapped;
    }

    final words = categoryValue
        .trim()
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map(
          (word) =>
              '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .join(' ');
    return words.isEmpty ? fallback : words;
  }

  String _buildFitNote({
    required String? description,
    required String? styleValue,
    required String? colorValue,
    required String? categoryValue,
    required _BodyZone zone,
  }) {
    if (description != null && description.trim().isNotEmpty) {
      return description.trim();
    }

    final fragments = <String>[];
    if (styleValue != null && styleValue.trim().isNotEmpty) {
      fragments.add('${_titleFromCategory(styleValue, zone)} styling');
    }
    if (colorValue != null && colorValue.trim().isNotEmpty) {
      fragments.add(_titleFromCategory(colorValue, zone));
    }
    if (categoryValue != null && categoryValue.trim().isNotEmpty) {
      fragments.add(_titleFromCategory(categoryValue, zone));
    }
    if (fragments.isNotEmpty) {
      return fragments.join(' • ');
    }
    return 'Open the wardrobe detail page to review this item.';
  }

  IconData _iconFor(String? categoryValue, _BodyZone zone) {
    final token = _normalizeToken(categoryValue ?? '');
    if (_feetKeywords.contains(token)) {
      return Icons.hiking_rounded;
    }
    if (token == 'hat' || token == 'scarf') {
      return Icons.style_rounded;
    }
    if (token == 'pants' ||
        token == 'trousers' ||
        token == 'jeans' ||
        token == 'leggings' ||
        token == 'shorts' ||
        token == 'skirt') {
      return Icons.view_stream_rounded;
    }
    if (token == 'jacket' ||
        token == 'coat' ||
        token == 'blazer' ||
        token == 'puffer' ||
        token == 'windbreaker' ||
        token == 'outwear') {
      return Icons.auto_awesome_mosaic_rounded;
    }
    return switch (zone) {
      _BodyZone.head => Icons.face_rounded,
      _BodyZone.upper => Icons.checkroom_rounded,
      _BodyZone.lower => Icons.straighten_rounded,
      _BodyZone.feet => Icons.directions_walk_rounded,
    };
  }

  Color _accentFor(String? categoryValue, _BodyZone zone) {
    final token = _normalizeToken(categoryValue ?? '');
    final mapped = _categoryAccents[token];
    return mapped ?? zone.accent;
  }

  Future<void> _openGarmentDetail(_GarmentItem item) async {
    if (widget.openDetailOverride != null) {
      await widget.openDetailOverride!(context, item.clothingItemId);
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ClothingResultScreen(itemId: item.clothingItemId),
      ),
    );
  }

  Future<void> _openDetailFromPicker(
    BuildContext sheetContext,
    _GarmentItem item,
  ) async {
    Navigator.of(sheetContext).pop();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) {
      return;
    }
    await _openGarmentDetail(item);
  }

  Future<void> _showReferencePhotoSheet() async {
    await ReferencePhotoService.ensureLoaded();
    if (!mounted) {
      return;
    }

    final library = ReferencePhotoService.currentLibrary;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        String? stagedPhotoId = library.selectedPhotoId;

        Widget buildChoiceCard({
          required String title,
          required String subtitle,
          required String imagePath,
          required bool selected,
          required VoidCallback onTap,
        }) {
          return InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _isDark
                    ? AppColors.darkBackground.withOpacity(0.6)
                    : const Color(0xFFF8F5EF),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? _accent : Theme.of(context).dividerColor,
                  width: selected ? 1.4 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 88,
                    height: 132,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _isDark
                          ? const Color(0xFF121820)
                          : const Color(0xFFF7F2EA),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: AdaptiveImage(
                      imagePath: imagePath,
                      fit: BoxFit.contain,
                      alignment: Alignment.topCenter,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            color: _textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? _accent.withOpacity(0.14)
                                : Theme.of(context)
                                    .dividerColor
                                    .withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            selected ? 'Selected' : 'Tap to choose',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: selected ? _accent : _textSecondary,
                            ),
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

        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              child: FractionallySizedBox(
                heightFactor: 0.84,
                child: Container(
                  decoration: BoxDecoration(
                    color: _isDark ? AppColors.darkSurface : Colors.white,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          width: 52,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Theme.of(context).dividerColor,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Choose Reference Photo',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: _textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Select which full-body photo should be used on the visualization canvas.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: _textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          children: [
                            buildChoiceCard(
                              title: 'Default Demo Reference',
                              subtitle:
                                  'Use the built-in mannequin-style reference that ships with the demo.',
                              imagePath: _defaultReferenceImagePath,
                              selected: stagedPhotoId == null,
                              onTap: () => setSheetState(() {
                                stagedPhotoId = null;
                              }),
                            ),
                            const SizedBox(height: 12),
                            for (final photo in library.photos) ...[
                              buildChoiceCard(
                                title: photo.label,
                                subtitle:
                                    'Saved from Profile. Tap confirm to use this reference in Visualize.',
                                imagePath: photo.imagePath,
                                selected: stagedPhotoId == photo.id,
                                onTap: () => setSheetState(() {
                                  stagedPhotoId = photo.id;
                                }),
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (library.photos.isEmpty)
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: _isDark
                                      ? AppColors.darkBackground
                                      : const Color(0xFFF8F5EF),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Text(
                                  'No personal full-body photos have been uploaded yet. Add them from Profile and they will show up here.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.5,
                                    color: _textSecondary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: () async {
                                  await ReferencePhotoService.selectPhoto(
                                    stagedPhotoId,
                                  );
                                  if (sheetContext.mounted) {
                                    Navigator.of(sheetContext).pop();
                                  }
                                },
                                child: const Text('Confirm'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInfoChip(String label, Color color, {bool darkText = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: darkText ? AppColors.textPrimary : color,
        ),
      ),
    );
  }

  void _clearSelection() {
    setState(() {
      for (final items in _wornByZone.values) {
        items.clear();
      }
    });
  }

  Future<void> _openPicker(_BodyZone zone) async {
    final draftSelections = List<_WornGarment>.from(_sortedSelections(zone));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, refreshPicker) {
            final items = _catalog[zone]!;
            final activeItems = _sortedWornItems(draftSelections);
            return SafeArea(
              child: FractionallySizedBox(
                heightFactor: 0.86,
                child: Container(
                  decoration: BoxDecoration(
                    color: _isDark ? AppColors.darkSurface : Colors.white,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          width: 52,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Theme.of(context).dividerColor,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${zone.title} Picker',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: _textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              zone.layered
                                  ? 'Tap a garment card to review it. Use the green Wear button to choose a layer, and the red Remove button to take it off.'
                                  : 'Tap a garment card to review it. Use the green Wear button to put it on, and the red Remove button to take it off.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: _textSecondary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: _isDark
                                    ? AppColors.darkBackground.withOpacity(0.5)
                                    : const Color(0xFFF7F3EB),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Theme.of(context).dividerColor,
                                ),
                              ),
                              child: activeItems.isEmpty
                                  ? Text(
                                      'No garment is being worn in this zone yet.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _textSecondary,
                                      ),
                                    )
                                  : ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxHeight: 96,
                                      ),
                                      child: SingleChildScrollView(
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            for (final worn in activeItems)
                                              Material(
                                                color: Colors.transparent,
                                                child: InkWell(
                                                  onTap: () =>
                                                      _openDetailFromPicker(
                                                        context,
                                                        worn.item,
                                                      ),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                  child: Ink(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 7,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: worn.item.accent
                                                          .withOpacity(0.15),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            999,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      zone.layered
                                                          ? 'Layer ${worn.layer}: ${worn.item.title}'
                                                          : worn.item.title,
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: worn.item.accent,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _buildPickerBody(
                          zone,
                          items,
                          draftSelections,
                          refreshPicker,
                          sheetContext: context,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: () {
                                  setState(() {
                                    _wornByZone[zone] = _sortedWornItems(
                                      draftSelections,
                                    );
                                  });
                                  Navigator.of(context).pop();
                                },
                                child: const Text('Confirm'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPickerBody(
    _BodyZone zone,
    List<_GarmentItem> items,
    List<_WornGarment> draftSelections,
    StateSetter refreshPicker, {
    required BuildContext sheetContext,
  }) {
    if (_catalogLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_catalogError != null && items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 34, color: _textSecondary),
              const SizedBox(height: 10),
              Text(
                _catalogError!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: _textSecondary),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: widget.catalogItems != null ? null : _loadCatalog,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'No compatible ${zone.shortTitle.toLowerCase()} items were found in the current wardrobe yet.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: _textSecondary),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      itemBuilder: (context, index) {
        final item = items[index];
        final currentLayer = _layerForInList(draftSelections, item.id);
        return _buildGarmentCard(
          zone,
          item,
          currentLayer,
          onOpenDetails: () => _openDetailFromPicker(sheetContext, item),
          onWear: () =>
              _handleWearAction(zone, item, draftSelections, refreshPicker),
          onRemove: currentLayer == null
              ? null
              : () {
                  refreshPicker(() {
                    _removeItemFromList(draftSelections, item.id);
                  });
                },
        );
      },
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemCount: items.length,
    );
  }

  Widget _buildGarmentCard(
    _BodyZone zone,
    _GarmentItem item,
    int? currentLayer, {
    required VoidCallback onOpenDetails,
    required VoidCallback onWear,
    required VoidCallback? onRemove,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactVisuals = constraints.maxWidth < 360;
        final useColumnLayout = constraints.maxWidth < 280;

        return Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              color: _isDark
                  ? AppColors.darkBackground.withOpacity(0.45)
                  : const Color(0xFFF8F5EF),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: currentLayer == null
                    ? Theme.of(context).dividerColor
                    : item.accent,
                width: currentLayer == null ? 1 : 1.4,
              ),
            ),
            child: InkWell(
              onTap: onOpenDetails,
              borderRadius: BorderRadius.circular(22),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: useColumnLayout
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildGarmentPreviewBox(
                            item,
                            compact: compactVisuals,
                          ),
                          const SizedBox(height: 12),
                          _buildGarmentDetails(
                            zone,
                            item,
                            currentLayer,
                            onWear,
                            onRemove,
                            compact: compactVisuals,
                          ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildGarmentPreviewBox(
                            item,
                            compact: compactVisuals,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _buildGarmentDetails(
                              zone,
                              item,
                              currentLayer,
                              onWear,
                              onRemove,
                              compact: compactVisuals,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGarmentPreviewBox(_GarmentItem item, {required bool compact}) {
    final boxSize = compact ? 72.0 : 86.0;
    return Container(
      width: boxSize,
      height: boxSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(item.icon, color: item.accent, size: compact ? 22 : 26),
          SizedBox(height: compact ? 6 : 8),
          Text(
            item.categoryLabel,
            style: TextStyle(fontSize: compact ? 9 : 10, color: _textSecondary),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildGarmentDetails(
    _BodyZone zone,
    _GarmentItem item,
    int? currentLayer,
    VoidCallback onWear,
    VoidCallback? onRemove, {
    required bool compact,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _buildMetaPill(
              Icons.layers_rounded,
              item.material,
              item.accent.withOpacity(0.12),
            ),
            _buildMetaPill(
              zone.icon,
              item.categoryLabel,
              zone.accent.withOpacity(0.14),
            ),
            if (currentLayer != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: item.accent.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  zone.layered ? 'Wearing • L$currentLayer' : 'Wearing',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: item.accent,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              item.title,
              style: TextStyle(
                fontSize: compact ? 14 : 15,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          item.fitNote,
          style: TextStyle(
            fontSize: compact ? 11 : 12,
            height: 1.4,
            color: _textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          item.sourceLabel,
          style: TextStyle(fontSize: compact ? 10 : 11, color: _textSecondary),
        ),
        const SizedBox(height: 10),
        _buildGarmentActionRow(
          onWear: onWear,
          onRemove: onRemove,
          canRemove: onRemove != null,
          compact: compact,
        ),
      ],
    );
  }

  Widget _buildMetaPill(IconData icon, String text, Color background) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 140),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: _textPrimary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGarmentActionRow({
    required VoidCallback onWear,
    required VoidCallback? onRemove,
    required bool canRemove,
    required bool compact,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackButtons = constraints.maxWidth < (compact ? 220 : 260);
        if (stackButtons) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildWearButton(onPressed: onWear),
              const SizedBox(height: 10),
              _buildRemoveButton(onPressed: onRemove, enabled: canRemove),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: _buildWearButton(onPressed: onWear)),
            const SizedBox(width: 10),
            Expanded(
              child: _buildRemoveButton(
                onPressed: onRemove,
                enabled: canRemove,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWearButton({required VoidCallback onPressed}) {
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: Size.zero,
      ),
      icon: const Icon(Icons.checkroom_rounded, size: 16),
      label: Text(
        'Wear',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildRemoveButton({
    required VoidCallback? onPressed,
    required bool enabled,
  }) {
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFC62828),
        disabledBackgroundColor: const Color(0xFFE57373),
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white70,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: Size.zero,
      ),
      icon: const Icon(Icons.remove_circle_outline_rounded, size: 16),
      label: Text(
        'Remove',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: enabled ? Colors.white : Colors.white70,
        ),
      ),
    );
  }

  Future<void> _handleWearAction(
    _BodyZone zone,
    _GarmentItem item,
    List<_WornGarment> draftSelections,
    StateSetter refreshPicker,
  ) async {
    if (!zone.layered) {
      refreshPicker(() {
        _wearSingleInList(draftSelections, item);
      });
      return;
    }

    final layer = await _showLayerPicker(zone, item, draftSelections);
    if (layer == null) {
      return;
    }
    refreshPicker(() {
      _wearLayeredInList(draftSelections, item, layer);
    });
  }

  Future<int?> _showLayerPicker(
    _BodyZone zone,
    _GarmentItem item,
    List<_WornGarment> draftSelections,
  ) async {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.52,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
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
                    'Choose a Layer',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Wear ${item.title} on one of the available layers.',
                    style: TextStyle(fontSize: 12, color: _textSecondary),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _maxLayerCount + 1,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        if (index == _maxLayerCount) {
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor: Theme.of(
                                context,
                              ).dividerColor.withOpacity(0.3),
                              child: Icon(
                                Icons.close_rounded,
                                color: _textSecondary,
                                size: 18,
                              ),
                            ),
                            title: Text(
                              'Close',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              'Cancel layer selection.',
                              style: TextStyle(color: _textSecondary),
                            ),
                            onTap: () => Navigator.of(context).pop(),
                          );
                        }

                        final layer = index + 1;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: item.accent.withOpacity(0.18),
                            child: Text(
                              '$layer',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: item.accent,
                              ),
                            ),
                          ),
                          title: Text(
                            'Wear on Layer $layer',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _textPrimary,
                            ),
                          ),
                          subtitle: _buildReplacementText(
                            _itemOnLayerInList(draftSelections, layer),
                            layer,
                          ),
                          onTap: () => Navigator.of(context).pop(layer),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Text _buildReplacementText(_WornGarment? existing, int layer) {
    return Text(
      existing == null
          ? 'Layer $layer is empty right now.'
          : 'Replace ${existing.item.title} on Layer $layer.',
      style: TextStyle(color: _textSecondary),
    );
  }

  Future<void> _showPreviewDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final size = MediaQuery.of(context).size;
        var isSaving = false;
        var isExporting = false;

        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> handleSave() async {
              if (isSaving) {
                return;
              }
              setDialogState(() => isSaving = true);
              try {
                final savedPath = await _savePreview();
                if (!mounted) {
                  return;
                }
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(content: Text('Preview saved to $savedPath')),
                );
              } on MissingPluginException {
                if (!mounted) {
                  return;
                }
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Gallery save is currently wired for Android only.',
                    ),
                  ),
                );
              } on PlatformException catch (error) {
                if (!mounted) {
                  return;
                }
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text(
                      error.message ?? 'Unable to save the preview image.',
                    ),
                  ),
                );
              } finally {
                if (dialogContext.mounted) {
                  setDialogState(() => isSaving = false);
                }
              }
            }

            Future<void> handleExport() async {
              if (isExporting) {
                return;
              }
              setDialogState(() => isExporting = true);
              try {
                final collection = await _showExportCollectionSheet();
                if (collection == null || !mounted) {
                  return;
                }
                await Clipboard.setData(
                  ClipboardData(text: collection.shareUrl),
                );
                if (!mounted) {
                  return;
                }
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Saved to Outfit Collections. Share link ${collection.shareCode} copied.',
                    ),
                  ),
                );
              } finally {
                if (dialogContext.mounted) {
                  setDialogState(() => isExporting = false);
                }
              }
            }

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 24,
              ),
              backgroundColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.min(size.width * 0.92, 520),
                  maxHeight: size.height * 0.82,
                ),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _isDark ? AppColors.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Theme.of(context).dividerColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 30,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final stackButtons = constraints.maxWidth < 360;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Generated Preview',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: _textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Review the generated outfit in this modal, then either close it or save the image to your gallery.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: _textSecondary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Container(
                                    color: _isDark
                                        ? const Color(0xFF11161E)
                                        : const Color(0xFFF6F1E8),
                                  ),
                                  Image.asset(
                                    _previewImagePath,
                                    fit: BoxFit.contain,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (stackButtons) ...[
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: isSaving ? null : handleSave,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _textPrimary,
                                  side: BorderSide(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                icon: Icon(
                                  isSaving
                                      ? Icons.photo_library_rounded
                                      : Icons.photo_library_outlined,
                                ),
                                label: Text(
                                  isSaving ? 'Saving...' : 'Save to Gallery',
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: isExporting ? null : handleExport,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _textPrimary,
                                  side: BorderSide(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                icon: Icon(
                                  isExporting
                                      ? Icons.inventory_2_rounded
                                      : Icons.inventory_2_outlined,
                                ),
                                label: Text(
                                  isExporting
                                      ? 'Exporting...'
                                      : 'Export to Collection',
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(),
                                style: FilledButton.styleFrom(
                                  backgroundColor: _accent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                child: const Text('Close'),
                              ),
                            ),
                          ] else
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: isSaving ? null : handleSave,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _textPrimary,
                                      side: BorderSide(
                                        color: Theme.of(context).dividerColor,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                    ),
                                    icon: Icon(
                                      isSaving
                                          ? Icons.photo_library_rounded
                                          : Icons.photo_library_outlined,
                                    ),
                                    label: Text(
                                      isSaving
                                          ? 'Saving...'
                                          : 'Save to Gallery',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: isExporting
                                        ? null
                                        : handleExport,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _textPrimary,
                                      side: BorderSide(
                                        color: Theme.of(context).dividerColor,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                    ),
                                    icon: Icon(
                                      isExporting
                                          ? Icons.inventory_2_rounded
                                          : Icons.inventory_2_outlined,
                                    ),
                                    label: Text(
                                      isExporting
                                          ? 'Exporting...'
                                          : 'Export to Collection',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _accent,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                    ),
                                    child: const Text('Close'),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<String> _savePreview() async {
    final byteData = await rootBundle.load(_previewImagePath);
    final fileName =
        'ai_wardrobe_preview_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final savedPath = await _downloadChannel.invokeMethod<String>(
      'saveImageToGallery',
      <String, dynamic>{
        'fileName': fileName,
        'bytes': byteData.buffer.asUint8List(),
      },
    );
    return savedPath ?? fileName;
  }

  Future<OutfitCollection?> _showExportCollectionSheet() async {
    return Navigator.of(context).push<OutfitCollection>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ExportCollectionPage(
          isDark: _isDark,
          textPrimary: _textPrimary,
          textSecondary: _textSecondary,
          previewImagePath: _previewImagePath,
          collectionItems: _buildCollectionItems(),
          zonePreviews: [
            for (final zone in _BodyZone.values)
              _CollectionZonePreviewData(
                title: zone.title,
                summary: _sortedSelections(zone).isEmpty
                    ? 'No item selected'
                    : _sortedSelections(zone)
                          .map((worn) => 'L${worn.layer} ${worn.item.title}')
                          .join(' • '),
              ),
          ],
          initialName: _defaultCollectionName(),
          initialNotes: _defaultStylingNotes(),
        ),
      ),
    );
  }

  String _defaultCollectionName() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return 'Look $month/$day';
  }

  String _defaultStylingNotes() {
    final lines = <String>[];
    for (final zone in _BodyZone.values) {
      for (final worn in _sortedSelections(zone)) {
        final layerText = zone.layered ? 'Layer ${worn.layer}' : 'Single slot';
        lines.add('${zone.title} - $layerText: ${worn.item.title}');
      }
    }
    return lines.join('\n');
  }

  List<OutfitCollectionItem> _buildCollectionItems() {
    final items = <OutfitCollectionItem>[];
    for (final zone in _BodyZone.values) {
      for (final worn in _sortedSelections(zone)) {
        items.add(
          OutfitCollectionItem(
            clothingItemId: worn.item.clothingItemId,
            title: worn.item.title,
            zone: zone.title,
            layer: worn.layer,
            categoryLabel: worn.item.categoryLabel,
            material: worn.item.material,
            sourceLabel: worn.item.sourceLabel,
          ),
        );
      }
    }
    return items;
  }

  List<_WornGarment> _sortedWornItems(List<_WornGarment> items) {
    final sorted = List<_WornGarment>.from(items);
    sorted.sort((left, right) => left.layer.compareTo(right.layer));
    return sorted;
  }

  List<_WornGarment> _sortedSelections(_BodyZone zone) {
    return _sortedWornItems(_wornByZone[zone]!);
  }

  int? _layerForInList(List<_WornGarment> items, String itemId) {
    for (final worn in items) {
      if (worn.item.id == itemId) {
        return worn.layer;
      }
    }
    return null;
  }

  _WornGarment? _itemOnLayerInList(List<_WornGarment> items, int layer) {
    for (final worn in items) {
      if (worn.layer == layer) {
        return worn;
      }
    }
    return null;
  }

  void _wearSingleInList(List<_WornGarment> items, _GarmentItem item) {
    items
      ..clear()
      ..add(_WornGarment(item: item, layer: 1));
  }

  void _wearLayeredInList(
    List<_WornGarment> items,
    _GarmentItem item,
    int layer,
  ) {
    items.removeWhere((worn) => worn.item.id == item.id || worn.layer == layer);
    items.add(_WornGarment(item: item, layer: layer));
  }

  void _removeItemFromList(List<_WornGarment> items, String itemId) {
    items.removeWhere((worn) => worn.item.id == itemId);
  }

  void _removeItem(_BodyZone zone, String itemId) {
    _removeItemFromList(_wornByZone[zone]!, itemId);
  }
}

enum _BodyZone { head, upper, lower, feet }

extension on _BodyZone {
  String get title => switch (this) {
    _BodyZone.head => 'Head',
    _BodyZone.upper => 'Upper Body',
    _BodyZone.lower => 'Lower Body',
    _BodyZone.feet => 'Feet',
  };

  String get shortTitle => switch (this) {
    _BodyZone.head => 'Head',
    _BodyZone.upper => 'Upper',
    _BodyZone.lower => 'Lower',
    _BodyZone.feet => 'Feet',
  };

  String get summary => switch (this) {
    _BodyZone.head => 'Single accessory slot',
    _BodyZone.upper => 'Up to three layers',
    _BodyZone.lower => 'Up to three layers',
    _BodyZone.feet => 'Single footwear slot',
  };

  bool get layered => this == _BodyZone.upper || this == _BodyZone.lower;

  IconData get icon => switch (this) {
    _BodyZone.head => Icons.face_rounded,
    _BodyZone.upper => Icons.checkroom_rounded,
    _BodyZone.lower => Icons.style_rounded,
    _BodyZone.feet => Icons.hiking_rounded,
  };

  Color get accent => switch (this) {
    _BodyZone.head => const Color(0xFF8E24AA),
    _BodyZone.upper => const Color(0xFF1565C0),
    _BodyZone.lower => const Color(0xFF2E7D32),
    _BodyZone.feet => const Color(0xFF5D4037),
  };
}

const _headKeywords = {'hat', 'scarf', 'beanie', 'beret', 'cap', 'headwear'};

const _upperKeywords = {
  'tshirt',
  'shirt',
  'blouse',
  'polo',
  'tanktop',
  'longsleeve',
  'sweater',
  'hoodie',
  'sweatshirt',
  'cardigan',
  'jacket',
  'coat',
  'blazer',
  'puffer',
  'windbreaker',
  'windbreakerjacket',
  'outwear',
  'outerwear',
  'vest',
  'dress',
  'jumpsuit',
  'romper',
};

const _lowerKeywords = {
  'pants',
  'trousers',
  'jeans',
  'shorts',
  'skirt',
  'leggings',
  'sweatpants',
  'belt',
};

const _feetKeywords = {
  'shoes',
  'shoe',
  'sneakers',
  'boots',
  'sandals',
  'dressshoes',
  'heels',
  'slippers',
  'loafers',
};

const _categoryTitles = {
  'tshirt': 'T-Shirt',
  'shirt': 'Shirt',
  'blouse': 'Blouse',
  'polo': 'Polo',
  'tanktop': 'Tank Top',
  'longsleeve': 'Long Sleeve',
  'sweater': 'Sweater',
  'hoodie': 'Hoodie',
  'sweatshirt': 'Sweatshirt',
  'cardigan': 'Cardigan',
  'jacket': 'Jacket',
  'coat': 'Coat',
  'blazer': 'Blazer',
  'puffer': 'Puffer',
  'windbreaker': 'Windbreaker',
  'outwear': 'Outerwear',
  'vest': 'Vest',
  'dress': 'Dress',
  'jumpsuit': 'Jumpsuit',
  'romper': 'Romper',
  'pants': 'Pants',
  'trousers': 'Trousers',
  'jeans': 'Jeans',
  'shorts': 'Shorts',
  'skirt': 'Skirt',
  'leggings': 'Leggings',
  'sweatpants': 'Sweatpants',
  'shoes': 'Shoes',
  'sneakers': 'Sneakers',
  'boots': 'Boots',
  'sandals': 'Sandals',
  'dressshoes': 'Dress Shoes',
  'heels': 'Heels',
  'slippers': 'Slippers',
  'hat': 'Hat',
  'scarf': 'Scarf',
  'belt': 'Belt',
};

const _categoryAccents = {
  'hat': Color(0xFF8E24AA),
  'scarf': Color(0xFF7B1FA2),
  'shirt': Color(0xFF42A5F5),
  'tshirt': Color(0xFF1E88E5),
  'blouse': Color(0xFF64B5F6),
  'hoodie': Color(0xFF3949AB),
  'jacket': Color(0xFF6D4C41),
  'coat': Color(0xFF8D6E63),
  'pants': Color(0xFF2E7D32),
  'jeans': Color(0xFF1565C0),
  'skirt': Color(0xFFAD1457),
  'shoes': Color(0xFF5D4037),
  'boots': Color(0xFF4E342E),
};

const _zoneOverlay = <_BodyZone, _ZoneOverlayConfig>{
  _BodyZone.head: _ZoneOverlayConfig(
    hotspot: Offset(0.72, 0.18),
    thumbnail: Offset(0.44, 0.12),
  ),
  _BodyZone.upper: _ZoneOverlayConfig(
    hotspot: Offset(0.77, 0.34),
    thumbnail: Offset(0.45, 0.29),
  ),
  _BodyZone.lower: _ZoneOverlayConfig(
    hotspot: Offset(0.77, 0.58),
    thumbnail: Offset(0.45, 0.54),
  ),
  _BodyZone.feet: _ZoneOverlayConfig(
    hotspot: Offset(0.72, 0.87),
    thumbnail: Offset(0.40, 0.82),
  ),
};

class _ZoneOverlayConfig {
  const _ZoneOverlayConfig({required this.hotspot, required this.thumbnail});

  final Offset hotspot;
  final Offset thumbnail;
}

class _CollectionZonePreviewData {
  const _CollectionZonePreviewData({
    required this.title,
    required this.summary,
  });

  final String title;
  final String summary;
}

class _ExportCollectionPage extends StatefulWidget {
  const _ExportCollectionPage({
    required this.isDark,
    required this.textPrimary,
    required this.textSecondary,
    required this.previewImagePath,
    required this.collectionItems,
    required this.zonePreviews,
    required this.initialName,
    required this.initialNotes,
  });

  final bool isDark;
  final Color textPrimary;
  final Color textSecondary;
  final String previewImagePath;
  final List<OutfitCollectionItem> collectionItems;
  final List<_CollectionZonePreviewData> zonePreviews;
  final String initialName;
  final String initialNotes;

  @override
  State<_ExportCollectionPage> createState() => _ExportCollectionPageState();
}

class _ExportCollectionPageState extends State<_ExportCollectionPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _tagController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _notesController;
  final List<String> _tags = <String>[];
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _tagController = TextEditingController();
    _descriptionController = TextEditingController();
    _notesController = TextEditingController(text: widget.initialNotes);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tagController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.isDark
          ? AppColors.darkBackground
          : const Color(0xFFF6F3EE),
      appBar: AppBar(
        title: const Text('Export to Outfit Collection'),
        backgroundColor: Colors.transparent,
        foregroundColor: widget.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Cancel',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Save this selection as a shareable collection with your own tags, an introduction, styling notes, and the current preview cover.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.55,
                  color: widget.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                height: 220,
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: widget.isDark
                      ? const Color(0xFF121820)
                      : const Color(0xFFF7F2EA),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: AdaptiveImage(
                  imagePath: widget.previewImagePath,
                  fit: BoxFit.contain,
                  alignment: Alignment.topCenter,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Body map preview',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: widget.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final zone in widget.zonePreviews)
                    SizedBox(
                      width: 148,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: widget.isDark
                              ? AppColors.darkBackground.withOpacity(0.7)
                              : const Color(0xFFF8F5EF),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              zone.title,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: widget.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              zone.summary,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.45,
                                color: widget.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              _buildFieldLabel('Collection Name'),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: _inputDecoration('Weekend smart casual'),
              ),
              const SizedBox(height: 14),
              _buildFieldLabel('Tags'),
              const SizedBox(height: 8),
              Text(
                'Add as many tags as you want. You can paste several at once using commas, semicolons, or new lines. Multi-word tags like "smart casual" stay together.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.45,
                  color: widget.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tagController,
                      minLines: 1,
                      maxLines: 3,
                      onSubmitted: (_) => _addTagsFromInput(),
                      decoration: _inputDecoration(
                        'e.g. smart casual, office, spring',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: FilledButton(
                      onPressed: _addTagsFromInput,
                      child: const Text('Add'),
                    ),
                  ),
                ],
              ),
              if (_tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in _tags)
                      InputChip(
                        label: Text(tag),
                        onDeleted: () {
                          setState(() {
                            _tags.remove(tag);
                          });
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              _buildFieldLabel('Introduction'),
              const SizedBox(height: 8),
              TextField(
                controller: _descriptionController,
                minLines: 3,
                maxLines: 4,
                decoration: _inputDecoration(
                  'A short intro for the collection card and detail page',
                ),
              ),
              const SizedBox(height: 14),
              _buildFieldLabel('How to Wear'),
              const SizedBox(height: 8),
              TextField(
                controller: _notesController,
                minLines: 4,
                maxLines: 6,
                decoration: _inputDecoration(
                  'Upper body layer order and styling note',
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isSubmitting ? null : _saveCollection,
                      icon: Icon(
                        _isSubmitting
                            ? Icons.inventory_2_rounded
                            : Icons.inventory_2_outlined,
                      ),
                      label: Text(
                        _isSubmitting ? 'Saving...' : 'Save Collection',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addTagsFromInput() {
    final nextTags = _tagController.text
        .split(RegExp(r'[,;\n，；]+'))
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
    if (nextTags.isEmpty) {
      return;
    }
    setState(() {
      for (final tag in nextTags) {
        if (!_tags.contains(tag)) {
          _tags.add(tag);
        }
      }
      _tagController.clear();
    });
  }

  Future<void> _saveCollection() async {
    if (_isSubmitting) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    _addTagsFromInput();
    setState(() => _isSubmitting = true);

    var popped = false;
    try {
      final collection = await OutfitCollectionService.saveCollection(
        title: _nameController.text,
        tags: List<String>.from(_tags),
        description: _descriptionController.text,
        stylingNotes: _notesController.text,
        previewImagePath: widget.previewImagePath,
        items: widget.collectionItems,
      );
      if (!mounted) {
        return;
      }
      popped = true;
      Navigator.of(context).pop(collection);
    } finally {
      if (!popped && mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: widget.isDark
          ? AppColors.darkBackground
          : Colors.grey.shade100,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _buildFieldLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: widget.textPrimary,
      ),
    );
  }
}

class _GarmentItem {
  const _GarmentItem({
    required this.id,
    required this.clothingItemId,
    required this.title,
    required this.fitNote,
    required this.material,
    required this.icon,
    required this.accent,
    required this.zone,
    required this.categoryLabel,
    required this.sourceLabel,
  });

  final String id;
  final String clothingItemId;
  final String title;
  final String fitNote;
  final String material;
  final IconData icon;
  final Color accent;
  final _BodyZone zone;
  final String categoryLabel;
  final String sourceLabel;
}

class _WornGarment {
  const _WornGarment({required this.item, required this.layer});

  final _GarmentItem item;
  final int layer;
}
