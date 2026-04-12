class ImportHistory {
  final String id;
  final String userId;
  final String cardPackId;
  final String cardPackName;
  final String creatorId;
  final String creatorName;
  final int itemCount;
  final DateTime importedAt;

  ImportHistory({
    required this.id,
    required this.userId,
    required this.cardPackId,
    required this.cardPackName,
    required this.creatorId,
    required this.creatorName,
    required this.itemCount,
    required this.importedAt,
  });

  factory ImportHistory.fromJson(Map<String, dynamic> json) {
    return ImportHistory(
      id: json['id'] as String,
      userId: json['userId'] as String,
      cardPackId: json['cardPackId'] as String,
      cardPackName: json['cardPackName'] as String,
      creatorId: json['creatorId'] as String,
      creatorName: json['creatorName'] as String,
      itemCount: json['itemCount'] as int,
      importedAt: DateTime.parse(json['importedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'cardPackId': cardPackId,
      'cardPackName': cardPackName,
      'creatorId': creatorId,
      'creatorName': creatorName,
      'itemCount': itemCount,
      'importedAt': importedAt.toIso8601String(),
    };
  }
}
