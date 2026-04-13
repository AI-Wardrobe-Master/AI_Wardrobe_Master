import 'package:dio/dio.dart';

import '../models/creator.dart';
import 'api_config.dart';

class CreatorApiService {
  static final _dio = Dio(BaseOptions(baseUrl: apiBaseUrl));

  static Future<Creator> getCreator(String id) async {
    try {
      final resp = await _dio.get('/creators/$id');
      final responseData = resp.data as Map<String, dynamic>;
      return Creator.fromJson(responseData['data'] as Map<String, dynamic>);
    } catch (_) {
      for (final creator in _localCreators) {
        if (creator.userId == id) return creator;
      }

      return Creator(
        userId: id,
        username: id,
        displayName: 'Unknown Creator',
        bio: 'Creator profile is unavailable while the platform API is offline.',
        followerCount: 0,
        packCount: 0,
        isVerified: false,
      );
    }
  }

  static Future<List<Creator>> listCreators({
    bool? verified,
    String? search,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'page': page,
        'limit': limit,
      };
      if (verified != null) queryParams['verified'] = verified;
      if (search != null && search.isNotEmpty) queryParams['search'] = search;

      final resp = await _dio.get('/creators', queryParameters: queryParams);
      final responseData = resp.data as Map<String, dynamic>;
      final data = responseData['data'] as Map<String, dynamic>;
      final creators = data['creators'] as List<dynamic>;
      return creators
          .map((e) => Creator.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      final query = search?.trim().toLowerCase();
      return _localCreators.where((creator) {
        if (verified == true && !creator.isVerified) return false;
        if (query == null || query.isEmpty) return true;
        return creator.displayName.toLowerCase().contains(query) ||
            creator.username.toLowerCase().contains(query) ||
            (creator.brandName?.toLowerCase().contains(query) ?? false) ||
            (creator.bio?.toLowerCase().contains(query) ?? false);
      }).toList();
    }
  }

  static final List<Creator> _localCreators = [
    Creator(
      userId: 'local_user',
      username: 'you',
      displayName: 'Your Studio',
      brandName: 'Local Creator',
      bio: 'Local creator profile used when the platform API is unavailable.',
      followerCount: 0,
      packCount: 0,
      isVerified: false,
    ),
    Creator(
      userId: 'demo_creator_1',
      username: 'davidxile',
      displayName: 'David Xile',
      brandName: 'Wardrobe Lab',
      bio: 'Experimental card packs and creator content for module restoration.',
      followerCount: 128,
      packCount: 3,
      isVerified: true,
    ),
  ];
}
