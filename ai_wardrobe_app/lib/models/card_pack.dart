enum PackType { clothingCollection, outfit }

enum PackStatus { draft, published, archived }

class CardPack {
  final String id;
  final String creatorId;
  final String? creatorUid;
  final String? creatorUsername;
  final String name;
  final String? description;
  final String? coverImageUrl;
  final String? wardrobeId;
  final String? wardrobeWid;
  final PackType type;
  final List<String> itemIds;
  final int itemCount;
  final String? shareLink;
  final PackStatus status;
  final int importCount;
  final DateTime createdAt;
  final DateTime? publishedAt;
  final DateTime updatedAt;
  final List<Map<String, dynamic>>? items;

  CardPack({
    required this.id,
    required this.creatorId,
    this.creatorUid,
    this.creatorUsername,
    required this.name,
    this.description,
    this.coverImageUrl,
    this.wardrobeId,
    this.wardrobeWid,
    required this.type,
    required this.itemIds,
    required this.itemCount,
    this.shareLink,
    required this.status,
    required this.importCount,
    required this.createdAt,
    this.publishedAt,
    required this.updatedAt,
    this.items,
  });

  factory CardPack.fromJson(Map<String, dynamic> json) {
    return CardPack(
      id: json['id'] as String,
      creatorId: json['creatorId'] as String,
      creatorUid: json['creatorUid'] as String?,
      creatorUsername: json['creatorUsername'] as String?,
      name: json['name'] as String,
      description: json['description'] as String?,
      coverImageUrl:
          json['coverImageUrl'] as String? ?? json['coverImage'] as String?,
      wardrobeId: json['wardrobeId'] as String?,
      wardrobeWid: json['wardrobeWid'] as String?,
      type: _parsePackType(json['type'] as String? ?? 'CLOTHING_COLLECTION'),
      itemIds: (json['itemIds'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      itemCount:
          json['itemCount'] as int? ??
          (json['itemIds'] as List<dynamic>? ?? const []).length,
      shareLink: json['shareLink'] as String?,
      status: _parsePackStatus(json['status'] as String? ?? 'DRAFT'),
      importCount: json['importCount'] as int? ?? 0,
      createdAt: DateTime.parse(
        json['createdAt'] as String? ?? DateTime.now().toIso8601String(),
      ),
      publishedAt: json['publishedAt'] != null
          ? DateTime.parse(json['publishedAt'] as String)
          : null,
      updatedAt: DateTime.parse(
        json['updatedAt'] as String? ?? DateTime.now().toIso8601String(),
      ),
      items: json['items'] != null
          ? (json['items'] as List<dynamic>)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'creatorId': creatorId,
      'creatorUid': creatorUid,
      'creatorUsername': creatorUsername,
      'name': name,
      'description': description,
      'coverImageUrl': coverImageUrl,
      'wardrobeId': wardrobeId,
      'wardrobeWid': wardrobeWid,
      'type': switch (type) {
        PackType.clothingCollection => 'CLOTHING_COLLECTION',
        PackType.outfit => 'OUTFIT',
      },
      'itemIds': itemIds,
      'itemCount': itemCount,
      'shareLink': shareLink,
      'status': switch (status) {
        PackStatus.draft => 'DRAFT',
        PackStatus.published => 'PUBLISHED',
        PackStatus.archived => 'ARCHIVED',
      },
      'importCount': importCount,
      'createdAt': createdAt.toIso8601String(),
      'publishedAt': publishedAt?.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'items': items,
    };
  }

  static PackType _parsePackType(String type) {
    switch (type.toUpperCase()) {
      case 'OUTFIT':
        return PackType.outfit;
      case 'CLOTHING_COLLECTION':
      default:
        return PackType.clothingCollection;
    }
  }

  static PackStatus _parsePackStatus(String status) {
    switch (status.toUpperCase()) {
      case 'PUBLISHED':
        return PackStatus.published;
      case 'ARCHIVED':
        return PackStatus.archived;
      case 'DRAFT':
      default:
        return PackStatus.draft;
    }
  }
}
