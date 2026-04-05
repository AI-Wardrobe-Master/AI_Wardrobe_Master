class OutfitCollection {
  const OutfitCollection({
    required this.id,
    required this.title,
    required this.tags,
    required this.description,
    required this.stylingNotes,
    required this.previewImagePath,
    required this.shareCode,
    required this.shareUrl,
    required this.isShareable,
    required this.createdAt,
    required this.items,
  });

  final String id;
  final String title;
  final List<String> tags;
  final String description;
  final String stylingNotes;
  final String previewImagePath;
  final String shareCode;
  final String shareUrl;
  final bool isShareable;
  final DateTime createdAt;
  final List<OutfitCollectionItem> items;

  factory OutfitCollection.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const <dynamic>[];
    return OutfitCollection(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled collection',
      tags: (json['tags'] as List<dynamic>? ?? const <dynamic>[])
          .map((tag) => tag.toString())
          .where((tag) => tag.trim().isNotEmpty)
          .toList(),
      description: json['description'] as String? ?? '',
      stylingNotes: json['stylingNotes'] as String? ?? '',
      previewImagePath: json['previewImagePath'] as String? ?? '',
      shareCode: json['shareCode'] as String? ?? '',
      shareUrl: json['shareUrl'] as String? ?? '',
      isShareable: json['isShareable'] as bool? ?? true,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map(OutfitCollectionItem.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'tags': tags,
      'description': description,
      'stylingNotes': stylingNotes,
      'previewImagePath': previewImagePath,
      'shareCode': shareCode,
      'shareUrl': shareUrl,
      'isShareable': isShareable,
      'createdAt': createdAt.toIso8601String(),
      'items': items.map((item) => item.toJson()).toList(),
    };
  }
}

class OutfitCollectionItem {
  const OutfitCollectionItem({
    required this.clothingItemId,
    required this.title,
    required this.zone,
    required this.layer,
    required this.categoryLabel,
    required this.material,
    required this.sourceLabel,
  });

  final String clothingItemId;
  final String title;
  final String zone;
  final int layer;
  final String categoryLabel;
  final String material;
  final String sourceLabel;

  factory OutfitCollectionItem.fromJson(Map<String, dynamic> json) {
    return OutfitCollectionItem(
      clothingItemId: json['clothingItemId'] as String? ?? '',
      title: json['title'] as String? ?? 'Wardrobe item',
      zone: json['zone'] as String? ?? 'Unknown',
      layer: (json['layer'] as num?)?.toInt() ?? 1,
      categoryLabel: json['categoryLabel'] as String? ?? 'Wardrobe item',
      material: json['material'] as String? ?? 'Unknown material',
      sourceLabel: json['sourceLabel'] as String? ?? 'Owned item',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'clothingItemId': clothingItemId,
      'title': title,
      'zone': zone,
      'layer': layer,
      'categoryLabel': categoryLabel,
      'material': material,
      'sourceLabel': sourceLabel,
    };
  }
}
