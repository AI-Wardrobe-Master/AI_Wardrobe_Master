import 'package:flutter/material.dart';

class ClothingMetadataArt extends StatelessWidget {
  const ClothingMetadataArt({
    super.key,
    required this.title,
    required this.categoryLabel,
    required this.material,
    this.sourceLabel,
    this.compact = false,
  });

  final String title;
  final String categoryLabel;
  final String material;
  final String? sourceLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = _paletteFor('$categoryLabel$title$material');
    final icon = _iconFor(categoryLabel);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -18,
            right: -12,
            child: Container(
              width: compact ? 54 : 84,
              height: compact ? 54 : 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.12),
              ),
            ),
          ),
          Positioned(
            bottom: -22,
            left: -10,
            child: Container(
              width: compact ? 62 : 108,
              height: compact ? 62 : 108,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withOpacity(0.12),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(compact ? 12 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _chip(categoryLabel),
                    if (sourceLabel != null && sourceLabel!.trim().isNotEmpty)
                      _chip(sourceLabel!),
                  ],
                ),
                const Spacer(),
                Icon(
                  icon,
                  size: compact ? 30 : 40,
                  color: Colors.white.withOpacity(0.94),
                ),
                SizedBox(height: compact ? 8 : 10),
                Text(
                  title,
                  maxLines: compact ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 12 : 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: compact ? 4 : 6),
                Text(
                  material,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 10 : 11,
                    color: Colors.white.withOpacity(0.84),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  List<Color> _paletteFor(String seed) {
    const palettes = <List<Color>>[
      [Color(0xFF345C72), Color(0xFF4F86A6)],
      [Color(0xFF5B3F8C), Color(0xFF8C6FCF)],
      [Color(0xFF4E5D2D), Color(0xFF7A8D4E)],
      [Color(0xFF7D4E57), Color(0xFFB97481)],
      [Color(0xFF7A4F2A), Color(0xFFC07A3B)],
      [Color(0xFF334B63), Color(0xFF6C91BF)],
    ];
    final index = seed.hashCode.abs() % palettes.length;
    return palettes[index];
  }

  IconData _iconFor(String text) {
    final normalized = text.toLowerCase();
    if (normalized.contains('shoe') ||
        normalized.contains('boot') ||
        normalized.contains('heel') ||
        normalized.contains('sneaker')) {
      return Icons.hiking_rounded;
    }
    if (normalized.contains('hat') ||
        normalized.contains('head') ||
        normalized.contains('beret') ||
        normalized.contains('scarf')) {
      return Icons.face_rounded;
    }
    if (normalized.contains('pant') ||
        normalized.contains('skirt') ||
        normalized.contains('jean') ||
        normalized.contains('bottom')) {
      return Icons.style_rounded;
    }
    return Icons.checkroom_rounded;
  }
}
