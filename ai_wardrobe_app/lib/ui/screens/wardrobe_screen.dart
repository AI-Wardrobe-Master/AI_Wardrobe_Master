import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({super.key});

  @override
  State<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> {
  final List<String> _categories = [
    'All',
    'Tops',
    'Bottoms',
    'Outerwear',
    'Accessories',
  ];

  int _selectedCategoryIndex = 0;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _textPrimary =>
      _isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
  Color get _textSecondary =>
      _isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
  Color get _accent =>
      _isDark ? AppColors.darkAccentBlue : AppColors.accentBlue;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your wardrobe',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'A calm, structured overview of your clothes.',
                      style: TextStyle(
                        fontSize: 12,
                        color: _textSecondary,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Icon(
                    Icons.qr_code_scanner_rounded,
                    size: 20,
                    color: _textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildCategoryChips(),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                hintText: 'Search in your wardrobe',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: _textSecondary,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  size: 20,
                  color: _textSecondary,
                ),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true,
                fillColor: _isDark ? AppColors.darkSurface : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide:
                      BorderSide(color: Theme.of(context).dividerColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide:
                      BorderSide(color: Theme.of(context).dividerColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide(color: _accent),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.checkroom_rounded,
                      size: 40,
                      color: _textSecondary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No clothes yet.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Use Add to start building your wardrobe.',
                      style: TextStyle(
                        fontSize: 12,
                        color: _textSecondary,
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

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final selected = index == _selectedCategoryIndex;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedCategoryIndex = index;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: selected
                    ? (_isDark ? AppColors.darkSurface : Colors.white)
                    : (_isDark
                        ? AppColors.darkBackground
                        : AppColors.background),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected
                      ? _accent
                      : Theme.of(context).dividerColor,
                  width: selected ? 1.4 : 1,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                _categories[index],
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? _textPrimary : _textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
