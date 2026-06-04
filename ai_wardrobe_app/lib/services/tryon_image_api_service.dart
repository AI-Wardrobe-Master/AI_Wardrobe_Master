import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'api_config.dart';

class TryOnImage {
  const TryOnImage({
    required this.id,
    required this.personViewType,
    required this.imageUrl,
    required this.isDefault,
  });

  final String id;
  final String personViewType;
  final String imageUrl;
  final bool isDefault;

  factory TryOnImage.fromJson(Map<String, dynamic> json) {
    return TryOnImage(
      id: json['id']?.toString() ?? '',
      personViewType: json['personViewType']?.toString() ?? 'FULL_BODY',
      imageUrl: json['imageUrl']?.toString() ?? '',
      isDefault: json['isDefault'] == true,
    );
  }
}

class TryOnImageApiService {
  static final Dio _dio = buildApiDio();

  static Future<TryOnImage?> getDefaultImage() async {
    final resp = await _dio.get('/me/tryon-image');
    final responseData = resp.data as Map<String, dynamic>;
    final data = responseData['data'];
    if (data is! Map) {
      return null;
    }
    return TryOnImage.fromJson(Map<String, dynamic>.from(data));
  }

  static Future<TryOnImage> uploadDefaultImage({
    required List<int> bytes,
    String filename = 'tryon-person.jpg',
  }) async {
    final formData = FormData.fromMap({
      'person_image': MultipartFile.fromBytes(
        bytes,
        filename: filename,
      ),
    });
    final resp = await _dio.post('/me/tryon-image', data: formData);
    final responseData = resp.data as Map<String, dynamic>;
    return TryOnImage.fromJson(
      Map<String, dynamic>.from(responseData['data'] as Map),
    );
  }

  static Future<void> deleteDefaultImage() async {
    await _dio.delete('/me/tryon-image');
  }

  static Future<Uint8List> downloadImageBytes(String imageUrl) async {
    final resp = await _dio.get<List<int>>(
      resolveFileUrl(imageUrl),
      options: Options(responseType: ResponseType.bytes),
    );
    final data = resp.data;
    if (data == null || data.isEmpty) {
      throw StateError('Try-on image response was empty.');
    }
    return Uint8List.fromList(data);
  }
}
