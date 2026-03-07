import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../services/api_config.dart';
import '../../../services/clothing_api_service.dart';
import '../../../theme/app_theme.dart';

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
      setState(() {
        _item = results[0];
        _angleViews = (results[1] as Map)['angleViews'] as List? ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  String _fullUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    return '$fileBaseUrl$url';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textS = isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
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
                    Icon(Icons.rotate_90_degrees_ccw,
                        size: 18, color: textS),
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
                    final url = _fullUrl(view['url'] as String?);
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
                          child: CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: isDark
                                  ? Colors.white10
                                  : Colors.black.withValues(alpha: 0.05),
                            ),
                            errorWidget: (_, __, ___) => const Icon(
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
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                  child: const Text('Done'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAngleViewer() {
    final view = _angleViews[_selectedAngle] as Map;
    final url = _fullUrl(view['url'] as String?);
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
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.contain,
          placeholder: (_, __) =>
              const Center(child: CircularProgressIndicator()),
          errorWidget: (_, __, ___) =>
              const Center(child: Icon(Icons.broken_image, size: 48)),
        ),
      ),
    );
  }

  Widget _buildOriginalImages() {
    final images = _item?['images'] as Map? ?? {};
    final front = _fullUrl(images['processedFrontUrl'] as String?);
    final back = _fullUrl(images['processedBackUrl'] as String?);

    return PageView(
      children: [
        if (front.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: CachedNetworkImage(
              imageUrl: front,
              fit: BoxFit.contain,
            ),
          ),
        if (back.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: CachedNetworkImage(
              imageUrl: back,
              fit: BoxFit.contain,
            ),
          ),
      ],
    );
  }
}
