import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/outfit_collection.dart';
import '../../services/outfit_collection_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/adaptive_image.dart';

const _collectionZones = <String>[
  'Head',
  'Upper Body',
  'Lower Body',
  'Feet',
];

class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textS = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

    return SafeArea(
      child: FutureBuilder<List<OutfitCollection>>(
        future: OutfitCollectionService.ensureLoaded(),
        builder: (context, snapshot) {
          return ValueListenableBuilder<List<OutfitCollection>>(
            valueListenable: OutfitCollectionService.listenable,
            builder: (context, collections, _) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Discover',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: textP,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Browse shared styling ideas and the outfit collections you export from Visualize.',
                      style: TextStyle(fontSize: 12, color: textS),
                    ),
                    const SizedBox(height: 16),
                    _CollectionSummary(collections: collections, textP: textP),
                    const SizedBox(height: 16),
                    Expanded(
                      child: collections.isEmpty
                          ? _EmptyDiscoverState(textP: textP, textS: textS)
                          : ListView.separated(
                              padding: EdgeInsets.zero,
                              itemCount: collections.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 14),
                              itemBuilder: (context, index) {
                                final collection = collections[index];
                                return _CollectionCard(collection: collection);
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _CollectionSummary extends StatelessWidget {
  const _CollectionSummary({required this.collections, required this.textP});

  final List<OutfitCollection> collections;
  final Color textP;

  @override
  Widget build(BuildContext context) {
    final sharedCount = collections.where((item) => item.isShareable).length;
    return Row(
      children: [
        Expanded(
          child: _SummaryChip(
            label: 'Collections',
            value: collections.length.toString(),
            accent: AppColors.accentBlue,
            textP: textP,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryChip(
            label: 'Share ready',
            value: sharedCount.toString(),
            accent: AppColors.accentYellow,
            textP: textP,
          ),
        ),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
    required this.accent,
    required this.textP,
  });

  final String label;
  final String value;
  final Color accent;
  final Color textP;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: textP,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textP,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDiscoverState extends StatelessWidget {
  const _EmptyDiscoverState({required this.textP, required this.textS});

  final Color textP;
  final Color textS;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department_outlined, size: 40, color: textS),
          const SizedBox(height: 8),
          Text(
            'No outfit collections yet.',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: textP,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Export a look from Visualize and it will appear here with your preview cover, body-part notes, and share actions.',
            style: TextStyle(fontSize: 12, color: textS),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({required this.collection});

  final OutfitCollection collection;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textS = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => _showCollectionDetails(context, collection),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Theme.of(context).dividerColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.18 : 0.05),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 240,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF121820)
                    : const Color(0xFFF7F2EA),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: AdaptiveImage(
                imagePath: collection.previewImagePath,
                fit: BoxFit.contain,
                alignment: Alignment.topCenter,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          collection.title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: textP,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accentBlue.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${collection.items.length} pieces',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accentBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (collection.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      collection.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: textS,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in collection.tags.take(5))
                        _tagChip(tag, textP),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _BodyCoverageGrid(
                    collection: collection,
                    textP: textP,
                    textS: textS,
                    compact: true,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'How to wear',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: textP,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    collection.stylingNotes,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, height: 1.5, color: textS),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tagChip(String text, Color textP) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accentYellow.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textP,
        ),
      ),
    );
  }

  Future<void> _showCollectionDetails(
    BuildContext context,
    OutfitCollection collection,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textS = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          minChildSize: 0.68,
          builder: (context, controller) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                children: [
                  Center(
                    child: Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Theme.of(context).dividerColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    height: 320,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF121820)
                          : const Color(0xFFF7F2EA),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: AdaptiveImage(
                        imagePath: collection.previewImagePath,
                        fit: BoxFit.contain,
                        alignment: Alignment.topCenter,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    collection.title,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: textP,
                    ),
                  ),
                  if (collection.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      collection.description,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.6,
                        color: textS,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in collection.tags) _tagChip(tag, textP),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Body coverage',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: textP,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _BodyCoverageGrid(
                    collection: collection,
                    textP: textP,
                    textS: textS,
                    compact: false,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'How to wear',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: textP,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    collection.stylingNotes,
                    style: TextStyle(fontSize: 12, height: 1.6, color: textS),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Included pieces',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: textP,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final item in collection.items)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkBackground
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: textP,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${item.zone} • Layer ${item.layer} • ${item.categoryLabel}',
                            style: TextStyle(fontSize: 12, color: textS),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${item.material} • ${item.sourceLabel}',
                            style: TextStyle(fontSize: 11, color: textS),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: collection.shareCode),
                            );
                            if (sheetContext.mounted) {
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                const SnackBar(
                                  content: Text('Share code copied'),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.qr_code_2_rounded),
                          label: const Text('Copy Share Code'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: collection.shareUrl),
                            );
                            if (sheetContext.mounted) {
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                const SnackBar(
                                  content: Text('Share link copied'),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.share_rounded),
                          label: const Text('Copy Share Link'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: const Text('Done'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _BodyCoverageGrid extends StatelessWidget {
  const _BodyCoverageGrid({
    required this.collection,
    required this.textP,
    required this.textS,
    required this.compact,
  });

  final OutfitCollection collection;
  final Color textP;
  final Color textS;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = compact
            ? constraints.maxWidth
            : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final zone in _collectionZones)
              SizedBox(
                width: compact ? width : width,
                child: _ZoneSummaryCard(
                  zone: zone,
                  items: collection.items
                      .where((item) => item.zone == zone)
                      .toList(),
                  textP: textP,
                  textS: textS,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ZoneSummaryCard extends StatelessWidget {
  const _ZoneSummaryCard({
    required this.zone,
    required this.items,
    required this.textP,
    required this.textS,
  });

  final String zone;
  final List<OutfitCollectionItem> items;
  final Color textP;
  final Color textS;

  @override
  Widget build(BuildContext context) {
    final summary = items.isEmpty
        ? 'Not styled yet'
        : items.map((item) => 'L${item.layer} ${item.title}').join(' • ');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkBackground.withOpacity(0.75)
            : const Color(0xFFF8F5EF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            zone,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: textP,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            summary,
            style: TextStyle(fontSize: 11, height: 1.45, color: textS),
          ),
        ],
      ),
    );
  }
}
