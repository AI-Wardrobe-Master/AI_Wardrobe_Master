import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../services/api_config.dart';

class AppRemoteImage extends StatelessWidget {
  AppRemoteImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  final String url;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  static final Dio _dio = buildApiDio();

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return errorWidget ?? const SizedBox.shrink();
    }

    if (url.startsWith('data:')) {
      try {
        final data = Uri.parse(url).data;
        if (data != null) {
          return Image.memory(
            data.contentAsBytes(),
            fit: fit,
            errorBuilder: (_, __, ___) =>
                errorWidget ?? const SizedBox.shrink(),
          );
        }
      } catch (_) {
        return errorWidget ?? const SizedBox.shrink();
      }
      return errorWidget ?? const SizedBox.shrink();
    }

    final resolvedUrl = resolveFileUrl(url);
    if (kIsWeb) {
      return FutureBuilder<Uint8List>(
        future: _loadImageBytes(resolvedUrl),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Image.memory(
              snapshot.data!,
              fit: fit,
              errorBuilder: (_, __, ___) =>
                  errorWidget ?? const SizedBox.shrink(),
            );
          }
          if (snapshot.hasError) {
            return errorWidget ?? const SizedBox.shrink();
          }
          return placeholder ?? const SizedBox.shrink();
        },
      );
    }

    return CachedNetworkImage(
      imageUrl: resolvedUrl,
      httpHeaders: ApiSession.authHeaders,
      fit: fit,
      placeholder: (_, __) => placeholder ?? const SizedBox.shrink(),
      errorWidget: (_, __, ___) => errorWidget ?? const SizedBox.shrink(),
    );
  }

  static Future<Uint8List> _loadImageBytes(String resolvedUrl) async {
    final response = await _dio.get<List<int>>(
      resolvedUrl,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data ?? const <int>[]);
  }
}
