// Module 3: Wardrobe & wardrobe item models (API response shapes).

class Wardrobe {
  final String id;
  final String wid;
  final String userId;
  final String? ownerUid;
  final String? ownerUsername;
  final String name;
  final String kind;
  final String type; // REGULAR | VIRTUAL
  final String source;
  final String? description;
  final String? coverImageUrl;
  final List<String> autoTags;
  final List<String> manualTags;
  final List<String> tags;
  final bool isPublic;
  final String? parentWardrobeId;
  final String? outfitId;
  final int itemCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Wardrobe({
    required this.id,
    required this.wid,
    required this.userId,
    this.ownerUid,
    this.ownerUsername,
    required this.name,
    required this.kind,
    required this.type,
    required this.source,
    this.description,
    this.coverImageUrl,
    this.autoTags = const [],
    this.manualTags = const [],
    this.tags = const [],
    this.isPublic = false,
    this.parentWardrobeId,
    this.outfitId,
    required this.itemCount,
    this.createdAt,
    this.updatedAt,
  });

  bool get isVirtual => type == 'VIRTUAL';
  bool get isMain => kind == 'MAIN';

  factory Wardrobe.fromJson(Map<String, dynamic> json) {
    List<String> stringList(dynamic raw) => (raw as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .toList();

    return Wardrobe(
      id: json['id'] as String,
      wid: json['wid'] as String? ?? '',
      userId: json['userId'] as String,
      ownerUid: json['ownerUid'] as String?,
      ownerUsername: json['ownerUsername'] as String?,
      name: json['name'] as String,
      kind: json['kind'] as String? ?? 'SUB',
      type: json['type'] as String? ?? 'REGULAR',
      source: json['source'] as String? ?? 'MANUAL',
      description: json['description'] as String?,
      coverImageUrl: json['coverImageUrl'] as String?,
      autoTags: stringList(json['autoTags']),
      manualTags: stringList(json['manualTags']),
      tags: stringList(json['tags']),
      isPublic: json['isPublic'] as bool? ?? false,
      parentWardrobeId: json['parentWardrobeId'] as String?,
      outfitId: json['outfitId'] as String?,
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
  final String? description;
  final String source; // OWNED | IMPORTED
  final List<dynamic> finalTags;
  final List<String> customTags;
  final String? imageUrl;
  final Map<String, dynamic> images;
  final String? category;
  final String? material;
  final String? style;
  final DateTime? addedAt;

  const ClothingItemBrief({
    required this.id,
    this.name,
    this.description,
    required this.source,
    this.finalTags = const [],
    this.customTags = const [],
    this.imageUrl,
    this.images = const <String, dynamic>{},
    this.category,
    this.material,
    this.style,
    this.addedAt,
  });

  factory ClothingItemBrief.fromJson(Map<String, dynamic> json) {
    return ClothingItemBrief(
      id: json['id'] as String,
      name: json['name'] as String?,
      description: json['description'] as String?,
      source: json['source'] as String? ?? 'OWNED',
      finalTags: (json['finalTags'] as List<dynamic>?) ?? [],
      customTags: (json['customTags'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      imageUrl: json['imageUrl'] as String?,
      images: Map<String, dynamic>.from(
        json['images'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
      category: json['category'] as String?,
      material: json['material'] as String?,
      style: json['style'] as String?,
      addedAt: json['addedAt'] != null
          ? DateTime.tryParse(json['addedAt'] as String)
          : null,
    );
  }

  List<String> get tagValues {
    final values = <String>[];
    for (final raw in finalTags) {
      if (raw is Map<String, dynamic>) {
        final value = raw['value'];
        final key = raw['key'];
        if (value != null && value.toString().trim().isNotEmpty) {
          values.add(value.toString());
        } else if (key != null && key.toString().trim().isNotEmpty) {
          values.add(key.toString());
        }
      }
    }
    values.addAll(customTags);
    return values;
  }

  /// Category for grouping: from finalTags key "category" or "type", else null.
  String? get categoryTag {
    if (category != null && category!.trim().isNotEmpty) {
      return category;
    }
    for (final t in finalTags) {
      if (t is Map && (t['key'] == 'category' || t['key'] == 'type')) {
        return t['value']?.toString();
      }
    }
    return null;
  }

  String? get previewImageUrl {
    return images['processedFrontUrl'] as String? ??
        images['originalFrontUrl'] as String? ??
        imageUrl;
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
              json['clothingItem'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}
