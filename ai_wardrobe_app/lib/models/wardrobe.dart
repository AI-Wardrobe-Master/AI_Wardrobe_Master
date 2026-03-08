// Module 3: Wardrobe & wardrobe item models (API response shapes).

class Wardrobe {
  final String id;
  final String userId;
  final String name;
  final String type; // REGULAR | VIRTUAL
  final String? description;
  final int itemCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Wardrobe({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    this.description,
    required this.itemCount,
    this.createdAt,
    this.updatedAt,
  });

  bool get isVirtual => type == 'VIRTUAL';

  factory Wardrobe.fromJson(Map<String, dynamic> json) {
    return Wardrobe(
      id: json['id'] as String,
      userId: json['userId'] as String,
      name: json['name'] as String,
      type: json['type'] as String? ?? 'REGULAR',
      description: json['description'] as String?,
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    );
  }
}

class ClothingItemBrief {
  final String id;
  final String? name;
  final String source; // OWNED | IMPORTED
  final List<dynamic> finalTags;
  final DateTime? addedAt;

  const ClothingItemBrief({
    required this.id,
    this.name,
    required this.source,
    this.finalTags = const [],
    this.addedAt,
  });

  factory ClothingItemBrief.fromJson(Map<String, dynamic> json) {
    return ClothingItemBrief(
      id: json['id'] as String,
      name: json['name'] as String?,
      source: json['source'] as String? ?? 'OWNED',
      finalTags: (json['finalTags'] as List<dynamic>?) ?? [],
      addedAt: json['addedAt'] != null
          ? DateTime.tryParse(json['addedAt'] as String)
          : null,
    );
  }

  /// Category for grouping: from finalTags key "category" or "type", else null.
  String? get categoryTag {
    for (final t in finalTags) {
      if (t is Map && (t['key'] == 'category' || t['key'] == 'type')) {
        return t['value']?.toString();
      }
    }
    return null;
  }
}

class WardrobeItemWithClothing {
  final String id;
  final String wardrobeId;
  final String clothingItemId;
  final DateTime? addedAt;
  final int? displayOrder;
  final ClothingItemBrief? clothingItem;

  const WardrobeItemWithClothing({
    required this.id,
    required this.wardrobeId,
    required this.clothingItemId,
    this.addedAt,
    this.displayOrder,
    this.clothingItem,
  });

  factory WardrobeItemWithClothing.fromJson(Map<String, dynamic> json) {
    return WardrobeItemWithClothing(
      id: json['id'] as String,
      wardrobeId: json['wardrobeId'] as String,
      clothingItemId: json['clothingItemId'] as String,
      addedAt: json['addedAt'] != null
          ? DateTime.tryParse(json['addedAt'] as String)
          : null,
      displayOrder: (json['displayOrder'] as num?)?.toInt(),
      clothingItem: json['clothingItem'] != null
          ? ClothingItemBrief.fromJson(
              json['clothingItem'] as Map<String, dynamic>)
          : null,
    );
  }
}
