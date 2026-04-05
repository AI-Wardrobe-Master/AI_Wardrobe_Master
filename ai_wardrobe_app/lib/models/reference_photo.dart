class ReferencePhotoLibrary {
  const ReferencePhotoLibrary({
    required this.photos,
    required this.selectedPhotoId,
  });

  const ReferencePhotoLibrary.empty()
      : photos = const <ReferencePhoto>[],
        selectedPhotoId = null;

  final List<ReferencePhoto> photos;
  final String? selectedPhotoId;

  ReferencePhoto? get selectedPhoto {
    for (final photo in photos) {
      if (photo.id == selectedPhotoId) {
        return photo;
      }
    }
    return null;
  }

  ReferencePhotoLibrary copyWith({
    List<ReferencePhoto>? photos,
    String? selectedPhotoId,
    bool clearSelectedPhoto = false,
  }) {
    return ReferencePhotoLibrary(
      photos: photos ?? this.photos,
      selectedPhotoId: clearSelectedPhoto
          ? null
          : selectedPhotoId ?? this.selectedPhotoId,
    );
  }

  factory ReferencePhotoLibrary.fromJson(Map<String, dynamic> json) {
    final rawPhotos = json['photos'] as List<dynamic>? ?? const <dynamic>[];
    return ReferencePhotoLibrary(
      photos: rawPhotos
          .whereType<Map<String, dynamic>>()
          .map(ReferencePhoto.fromJson)
          .toList(),
      selectedPhotoId: json['selectedPhotoId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'selectedPhotoId': selectedPhotoId,
      'photos': photos.map((photo) => photo.toJson()).toList(),
    };
  }
}

class ReferencePhoto {
  const ReferencePhoto({
    required this.id,
    required this.label,
    required this.imagePath,
    required this.createdAt,
  });

  final String id;
  final String label;
  final String imagePath;
  final DateTime createdAt;

  factory ReferencePhoto.fromJson(Map<String, dynamic> json) {
    return ReferencePhoto(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? 'Reference Photo',
      imagePath: json['imagePath'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'imagePath': imagePath,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
