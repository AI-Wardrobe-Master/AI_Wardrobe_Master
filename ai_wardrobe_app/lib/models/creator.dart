class Creator {
  final String userId;
  final String username;
  final String displayName;
  final String? brandName;
  final String? bio;
  final String? avatarUrl;
  final String? websiteUrl;
  final Map<String, String>? socialLinks;
  final int followerCount;
  final int packCount;
  final bool isVerified;
  final DateTime? verifiedAt;

  Creator({
    required this.userId,
    required this.username,
    required this.displayName,
    this.brandName,
    this.bio,
    this.avatarUrl,
    this.websiteUrl,
    this.socialLinks,
    required this.followerCount,
    required this.packCount,
    required this.isVerified,
    this.verifiedAt,
  });

  factory Creator.fromJson(Map<String, dynamic> json) {
    final socialLinksRaw = json['socialLinks'];
    return Creator(
      userId: (json['userId'] ?? json['id']) as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String,
      brandName: json['brandName'] as String?,
      bio: json['bio'] as String? ?? json['bioSummary'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      websiteUrl: json['websiteUrl'] as String?,
      socialLinks: socialLinksRaw is Map
          ? socialLinksRaw.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : null,
      followerCount: json['followerCount'] as int? ?? 0,
      packCount: json['packCount'] as int? ?? 0,
      isVerified: json['isVerified'] as bool? ?? false,
      verifiedAt: json['verifiedAt'] != null
          ? DateTime.parse(json['verifiedAt'] as String)
          : null,
    );
  }
}
