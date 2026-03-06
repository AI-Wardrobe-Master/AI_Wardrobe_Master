import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

const _referenceImagePath =
    'assets/visualization/source/full_body_reference.jpg';
const _previewImagePath =
    'assets/visualization/preview/generated_outfit_preview.jpg';
const _downloadChannel = MethodChannel('ai_wardrobe_app/downloads');

class OutfitCanvasScreen extends StatefulWidget {
  const OutfitCanvasScreen({super.key});

  @override
  State<OutfitCanvasScreen> createState() => _OutfitCanvasScreenState();
}

class _OutfitCanvasScreenState extends State<OutfitCanvasScreen> {
  static const _maxLayerCount = 3;

  final Map<_BodyZone, List<_WornGarment>> _wornByZone = {
    for (final zone in _BodyZone.values) zone: <_WornGarment>[],
  };

  late final Map<_BodyZone, List<_GarmentItem>> _catalog = {
    _BodyZone.head: const [
      _GarmentItem(
        id: 'head_beret',
        title: 'Wool Beret',
        fitNote: 'Soft crown with a classic shape',
        material: 'Merino wool blend',
        icon: Icons.style_rounded,
        accent: Color(0xFF795548),
      ),
      _GarmentItem(
        id: 'head_cap',
        title: 'Minimal Cap',
        fitNote: 'Structured everyday profile',
        material: 'Brushed cotton twill',
        icon: Icons.sports_baseball_rounded,
        accent: Color(0xFF546E7A),
      ),
      _GarmentItem(
        id: 'head_scarf',
        title: 'Silk Head Scarf',
        fitNote: 'Lightweight wrap for the crown',
        material: 'Printed silk',
        icon: Icons.waves_rounded,
        accent: Color(0xFF8E24AA),
      ),
    ],
    _BodyZone.upper: const [
      _GarmentItem(
        id: 'upper_turtleneck',
        title: 'Ivory Turtleneck',
        fitNote: 'Close-to-body foundation layer',
        material: 'Fine rib knit',
        icon: Icons.dry_cleaning_rounded,
        accent: Color(0xFFD8C3A5),
      ),
      _GarmentItem(
        id: 'upper_oxford',
        title: 'Relaxed Oxford Shirt',
        fitNote: 'Easy mid-layer volume',
        material: 'Cotton poplin',
        icon: Icons.checkroom_rounded,
        accent: Color(0xFF64B5F6),
      ),
      _GarmentItem(
        id: 'upper_jacket',
        title: 'Dark Leather Jacket',
        fitNote: 'Cropped outer layer',
        material: 'Washed leather',
        icon: Icons.auto_awesome_mosaic_rounded,
        accent: Color(0xFF4E342E),
      ),
      _GarmentItem(
        id: 'upper_trench',
        title: 'Camel Trench Coat',
        fitNote: 'Long outer shell',
        material: 'Water-resistant cotton',
        icon: Icons.shield_moon_rounded,
        accent: Color(0xFFBCA17A),
      ),
    ],
    _BodyZone.lower: const [
      _GarmentItem(
        id: 'lower_leggings',
        title: 'Base Thermal Leggings',
        fitNote: 'Closest layer for warmth',
        material: 'Stretch jersey',
        icon: Icons.texture_rounded,
        accent: Color(0xFF5C6BC0),
      ),
      _GarmentItem(
        id: 'lower_jeans',
        title: 'Straight Blue Jeans',
        fitNote: 'Classic denim outer layer',
        material: 'Rigid denim',
        icon: Icons.straighten_rounded,
        accent: Color(0xFF1565C0),
      ),
      _GarmentItem(
        id: 'lower_trousers',
        title: 'Tailored Wool Trousers',
        fitNote: 'Sharp clean drape',
        material: 'Compact wool blend',
        icon: Icons.view_stream_rounded,
        accent: Color(0xFF455A64),
      ),
      _GarmentItem(
        id: 'lower_skirt',
        title: 'Pleated Midi Skirt',
        fitNote: 'Fluid lower-body overlay',
        material: 'Matte twill',
        icon: Icons.change_history_rounded,
        accent: Color(0xFFAD1457),
      ),
    ],
    _BodyZone.feet: const [
      _GarmentItem(
        id: 'feet_boots',
        title: 'Leather Ankle Boots',
        fitNote: 'Low shaft with a stacked heel',
        material: 'Burnished leather',
        icon: Icons.hiking_rounded,
        accent: Color(0xFF5D4037),
      ),
      _GarmentItem(
        id: 'feet_sneakers',
        title: 'White Leather Sneakers',
        fitNote: 'Minimal low-top shape',
        material: 'Smooth leather',
        icon: Icons.directions_run_rounded,
        accent: Color(0xFFB0BEC5),
      ),
      _GarmentItem(
        id: 'feet_loafers',
        title: 'Black Loafers',
        fitNote: 'Polished clean finish',
        material: 'Soft calf leather',
        icon: Icons.flutter_dash_rounded,
        accent: Color(0xFF263238),
      ),
    ],
  };

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _textPrimary =>
      _isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
  Color get _textSecondary =>
      _isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
  Color get _panelColor =>
      _isDark ? AppColors.darkSurface : Colors.white.withOpacity(0.9);
  Color get _accent =>
      _isDark ? AppColors.darkAccentBlue : AppColors.accentBlue;
  int get _selectedCount =>
      _wornByZone.values.fold<int>(0, (sum, items) => sum + items.length);
  bool get _hasSelection => _selectedCount > 0;
  bool get _canClear => _hasSelection;
  bool get _canGeneratePreview => _hasSelection;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Visualize')),
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
                        _buildInfoChip('Reference ready', _accent),
                        _buildInfoChip(
                          '$_selectedCount items selected',
                          AppColors.accentYellow,
                          darkText: true,
                        ),
                        _buildInfoChip(
                          'Layered tops and bottoms',
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
                      child: const Text('Clear'),
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
                      child: const Text('Generate Preview'),
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
          Text(
            'Reference Canvas',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap a translucent plus hotspot to open a picker. Selected garments appear as compact stack tags that stay clear of the hotspot, and each tag opens garment details.',
            style: TextStyle(fontSize: 12, height: 1.5, color: _textSecondary),
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
                            'Reference Photo',
                            style: TextStyle(
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
                          child: Image.asset(
                            _referenceImagePath,
                            fit: BoxFit.contain,
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
          Text(
            'Current Styling Map',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
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
          if (selections.isEmpty)
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
          onTap: () =>
              _showGarmentDetails(zone, worn.item, currentLayer: worn.layer),
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
        onTap: () =>
            _showGarmentDetails(zone, worn.item, currentLayer: worn.layer),
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, refreshPicker) {
            final items = _catalog[zone]!;
            final activeItems = _sortedSelections(zone);
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
                                                      _showGarmentDetails(
                                                        zone,
                                                        worn.item,
                                                        currentLayer:
                                                            worn.layer,
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
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final currentLayer = _layerFor(zone, item.id);
                            return _buildGarmentCard(
                              zone,
                              item,
                              currentLayer,
                              onOpenDetails: () => _showGarmentDetails(
                                zone,
                                item,
                                currentLayer: currentLayer,
                              ),
                              onWear: () =>
                                  _handleWearAction(zone, item, refreshPicker),
                              onRemove: currentLayer == null
                                  ? null
                                  : () {
                                      setState(() {
                                        _removeItem(zone, item.id);
                                      });
                                      refreshPicker(() {});
                                    },
                            );
                          },
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemCount: items.length,
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
        final isCompact = constraints.maxWidth < 360;

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
                child: isCompact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildGarmentPreviewBox(item),
                          const SizedBox(height: 12),
                          _buildGarmentDetails(
                            zone,
                            item,
                            currentLayer,
                            onWear,
                            onRemove,
                          ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildGarmentPreviewBox(item),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _buildGarmentDetails(
                              zone,
                              item,
                              currentLayer,
                              onWear,
                              onRemove,
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

  Widget _buildGarmentPreviewBox(_GarmentItem item) {
    return Container(
      width: 86,
      height: 86,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(item.icon, color: item.accent, size: 26),
          const SizedBox(height: 8),
          Text(
            'Image pending',
            style: TextStyle(fontSize: 10, color: _textSecondary),
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
    VoidCallback? onRemove,
  ) {
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
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          item.fitNote,
          style: TextStyle(fontSize: 12, height: 1.4, color: _textSecondary),
        ),
        const SizedBox(height: 10),
        _buildGarmentActionRow(
          onWear: onWear,
          onRemove: onRemove,
          canRemove: onRemove != null,
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _textPrimary),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGarmentActionRow({
    required VoidCallback onWear,
    required VoidCallback? onRemove,
    required bool canRemove,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackButtons = constraints.maxWidth < 330;
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

  Future<void> _showGarmentDetails(
    _BodyZone zone,
    _GarmentItem item, {
    int? currentLayer,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.68,
            child: Container(
              decoration: BoxDecoration(
                color: _isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                    const SizedBox(height: 16),
                    Text(
                      'Garment Details',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'This detail entry point is now reserved for the full garment page. It currently shows the garment summary and wearing status.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: _textSecondary,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildGarmentPreviewBox(item),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.title,
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                          color: _textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          _buildMetaPill(
                                            zone.icon,
                                            zone.title,
                                            zone.accent.withOpacity(0.14),
                                          ),
                                          _buildMetaPill(
                                            Icons.layers_rounded,
                                            currentLayer == null
                                                ? 'Not wearing'
                                                : zone.layered
                                                ? 'Wearing on L$currentLayer'
                                                : 'Wearing',
                                            item.accent.withOpacity(0.12),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Fit Note',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item.fitNote,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: _textSecondary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Material',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item.material,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: _textSecondary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: _isDark
                                    ? AppColors.darkBackground.withOpacity(0.45)
                                    : const Color(0xFFF8F5EF),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Next step: connect this sheet to the dedicated garment detail page once the detail module is ready.',
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
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: FilledButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Close'),
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

  Future<void> _handleWearAction(
    _BodyZone zone,
    _GarmentItem item,
    StateSetter refreshPicker,
  ) async {
    if (!zone.layered) {
      setState(() {
        _wearSingle(zone, item);
      });
      refreshPicker(() {});
      return;
    }

    await _showLayerPicker(zone, item, refreshPicker);
  }

  Future<void> _showLayerPicker(
    _BodyZone zone,
    _GarmentItem item,
    StateSetter refreshPicker,
  ) async {
    await showModalBottomSheet<void>(
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
                          subtitle: _buildReplacementText(zone, layer),
                          onTap: () {
                            Navigator.of(context).pop();
                            setState(() {
                              _wearLayered(zone, item, layer);
                            });
                            refreshPicker(() {});
                          },
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

  Text _buildReplacementText(_BodyZone zone, int layer) {
    final existing = _itemOnLayer(zone, layer);
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

  List<_WornGarment> _sortedSelections(_BodyZone zone) {
    final items = List<_WornGarment>.from(_wornByZone[zone]!);
    items.sort((left, right) => left.layer.compareTo(right.layer));
    return items;
  }

  int? _layerFor(_BodyZone zone, String itemId) {
    for (final worn in _wornByZone[zone]!) {
      if (worn.item.id == itemId) {
        return worn.layer;
      }
    }
    return null;
  }

  _WornGarment? _itemOnLayer(_BodyZone zone, int layer) {
    for (final worn in _wornByZone[zone]!) {
      if (worn.layer == layer) {
        return worn;
      }
    }
    return null;
  }

  void _wearSingle(_BodyZone zone, _GarmentItem item) {
    final items = _wornByZone[zone]!;
    items
      ..clear()
      ..add(_WornGarment(item: item, layer: 1));
  }

  void _wearLayered(_BodyZone zone, _GarmentItem item, int layer) {
    final items = _wornByZone[zone]!;
    items.removeWhere((worn) => worn.item.id == item.id || worn.layer == layer);
    items.add(_WornGarment(item: item, layer: layer));
  }

  void _removeItem(_BodyZone zone, String itemId) {
    _wornByZone[zone]!.removeWhere((worn) => worn.item.id == itemId);
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

class _GarmentItem {
  const _GarmentItem({
    required this.id,
    required this.title,
    required this.fitNote,
    required this.material,
    required this.icon,
    required this.accent,
  });

  final String id;
  final String title;
  final String fitNote;
  final String material;
  final IconData icon;
  final Color accent;
}

class _WornGarment {
  const _WornGarment({required this.item, required this.layer});

  final _GarmentItem item;
  final int layer;
}
