import 'package:flutter/material.dart';

import '../../../l10n/app_strings_provider.dart';
import '../../../services/clothing_api_service.dart';
import '../../../services/wardrobe_service.dart';
import '../../../state/current_wardrobe_controller.dart';
import '../../../state/wardrobe_refresh_notifier.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/app_remote_image.dart';

class ClothingResultScreen extends StatefulWidget {
  final String itemId;

  const ClothingResultScreen({super.key, required this.itemId});

  @override
  State<ClothingResultScreen> createState() => _ClothingResultScreenState();
}

class _ClothingResultScreenState extends State<ClothingResultScreen> {
  Map<String, dynamic>? _item;
  List<dynamic> _angleViews = [];
  int _selectedAngle = 0;
  bool _loading = true;
  bool _addingToWardrobe = false;
  bool _addedToWardrobe = false;
  String? _currentWardrobeId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        ClothingApiService.getClothingItem(widget.itemId),
        ClothingApiService.getAngleViews(widget.itemId),
      ]);
      final item = Map<String, dynamic>.from(results[0] as Map);
      final angleViews = _normalizeAngleViews((results[1] as Map)['angleViews']);

      String? currentWardrobeId = CurrentWardrobeController.currentWardrobeId;
      if (currentWardrobeId == null) {
        try {
          final wardrobes = await WardrobeService.fetchWardrobes();
          if (wardrobes.isNotEmpty) {
            currentWardrobeId = wardrobes.first.id;
            CurrentWardrobeController.setCurrentWardrobeId(currentWardrobeId);
          }
        } catch (_) {
          // Keep the add button available when wardrobe lookup is unavailable.
        }
      }

      final wardrobeIds = ((item['wardrobeIds'] as List?) ?? const <dynamic>[])
          .map((id) => id.toString())
          .toSet();

      setState(() {
        _item = item;
        _angleViews = angleViews;
        _currentWardrobeId = currentWardrobeId;
        _addedToWardrobe =
            currentWardrobeId != null &&
            wardrobeIds.contains(currentWardrobeId);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _addToCurrentWardrobe() async {
    if (_addingToWardrobe || _addedToWardrobe) return;
    String? wardrobeId = CurrentWardrobeController.currentWardrobeId;
    if (wardrobeId == null) {
      try {
        final list = await WardrobeService.fetchWardrobes();
        if (list.isEmpty) {
          if (mounted) {
            final s = AppStringsProvider.of(context);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(s.createWardrobeFirst)));
          }
          return;
        }
        wardrobeId = list.first.id;
        CurrentWardrobeController.setCurrentWardrobeId(wardrobeId);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to load wardrobes')),
          );
        }
        return;
      }
    }
    setState(() => _addingToWardrobe = true);
    try {
      await WardrobeService.addItemToWardrobe(wardrobeId, widget.itemId);
      WardrobeRefreshNotifier.requestRefresh();
      if (mounted) {
        setState(() {
          _addingToWardrobe = false;
          _addedToWardrobe = true;
        });
        final s = AppStringsProvider.of(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.addedToWardrobe)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _addingToWardrobe = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textS = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final name = _item?['name'] as String? ?? 'Clothing Item';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // AppBar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: textP,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.check_circle, color: Colors.green, size: 24),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            const Divider(height: 1),

            // Main image viewer
            Expanded(
              flex: 5,
              child: _angleViews.isNotEmpty
                  ? _buildAngleViewer()
                  : _buildOriginalImages(),
            ),

            // Angle selector thumbnails
            if (_angleViews.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    Icon(Icons.rotate_90_degrees_ccw, size: 18, color: textS),
                    const SizedBox(width: 6),
                    Text(
                      '${_selectedAngle * 45}°',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: textP,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_angleViews.length} angles',
                      style: TextStyle(fontSize: 12, color: textS),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 74,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _angleViews.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final view = _angleViews[i] as Map;
                    final url = view['url'] as String? ?? '';
                    final selected = i == _selectedAngle;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedAngle = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 64,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected
                                ? AppColors.accentBlue
                                : Theme.of(context).dividerColor,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: _buildAdaptiveImage(
                            url,
                            fit: BoxFit.cover,
                            placeholder: Container(
                              color: isDark
                                  ? Colors.white10
                                  : Colors.black.withValues(alpha: 0.05),
                            ),
                            errorWidget: const Icon(
                              Icons.broken_image,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Action buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_addingToWardrobe || _addedToWardrobe)
                          ? null
                          : _addToCurrentWardrobe,
                      icon: _addingToWardrobe
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: textP,
                              ),
                            )
                          : Icon(
                              _addedToWardrobe
                                  ? Icons.check_circle
                                  : Icons.add_to_photos_outlined,
                              size: 20,
                              color: _addedToWardrobe ? Colors.green : textP,
                            ),
                      label: Text(
                        _addedToWardrobe
                            ? 'Already in current wardrobe'
                            : AppStringsProvider.of(
                                context,
                              ).addToCurrentWardrobe,
                        style: TextStyle(color: textP),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        WardrobeRefreshNotifier.requestRefresh();
                        Navigator.of(context).popUntil((r) => r.isFirst);
                      },
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildAdaptiveImage(
    String url, {
    BoxFit fit = BoxFit.cover,
    Widget? placeholder,
    Widget? errorWidget,
  }) {
    return AppRemoteImage(
      url: url,
      fit: fit,
      placeholder: placeholder,
      errorWidget: errorWidget,
    );
  }

  List<Map<String, dynamic>> _normalizeAngleViews(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    }
    if (raw is Map) {
      final entries = raw.entries.toList()
        ..sort((left, right) {
          final leftAngle = int.tryParse(left.key.toString()) ?? 0;
          final rightAngle = int.tryParse(right.key.toString()) ?? 0;
          return leftAngle.compareTo(rightAngle);
        });
      return entries
          .map(
            (entry) => <String, dynamic>{
              'angle': int.tryParse(entry.key.toString()),
              'url': entry.value?.toString(),
            },
          )
          .where((entry) => (entry['url'] as String? ?? '').isNotEmpty)
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }

  Widget _buildAngleViewer() {
    final view = _angleViews[_selectedAngle] as Map;
    final url = view['url'] as String? ?? '';
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        setState(() {
          if (details.primaryVelocity! < 0) {
            _selectedAngle = (_selectedAngle + 1) % _angleViews.length;
          } else {
            _selectedAngle =
                (_selectedAngle - 1 + _angleViews.length) % _angleViews.length;
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _buildAdaptiveImage(
          url,
          fit: BoxFit.contain,
          placeholder: const Center(child: CircularProgressIndicator()),
          errorWidget: const Center(child: Icon(Icons.broken_image, size: 48)),
        ),
      ),
    );
  }

  Widget _buildOriginalImages() {
    final images = _item?['images'] as Map? ?? {};
    final front =
        images['processedFrontUrl'] as String? ??
        images['originalFrontUrl'] as String? ??
        '';
    final back =
        images['processedBackUrl'] as String? ??
        images['originalBackUrl'] as String? ??
        '';

    return PageView(
      children: [
        if (front.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildAdaptiveImage(front, fit: BoxFit.contain),
          ),
        if (back.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildAdaptiveImage(back, fit: BoxFit.contain),
          ),
      ],
    );
  }
}
