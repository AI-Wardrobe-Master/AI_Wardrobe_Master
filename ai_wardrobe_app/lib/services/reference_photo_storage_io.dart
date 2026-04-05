import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String?> readReferencePhotoLibrary(String fileName) async {
  try {
    final file = await _libraryFile(fileName);
    if (!await file.exists()) {
      return null;
    }
    return await file.readAsString();
  } catch (_) {
    return null;
  }
}

Future<void> writeReferencePhotoLibrary(String fileName, String payload) async {
  try {
    final file = await _libraryFile(fileName);
    await file.parent.create(recursive: true);
    await file.writeAsString(payload);
  } catch (_) {
    return;
  }
}

Future<String> copyReferencePhoto(String sourcePath, String fileName) async {
  final source = File(sourcePath);
  final directory = await _photoDirectory();
  await directory.create(recursive: true);
  final target = File('${directory.path}${Platform.pathSeparator}$fileName');
  await source.copy(target.path);
  return target.path;
}

Future<void> deleteReferencePhoto(String imagePath) async {
  try {
    final file = File(imagePath);
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {
    return;
  }
}

Future<File> _libraryFile(String fileName) async {
  final directory = await getApplicationSupportDirectory();
  return File('${directory.path}${Platform.pathSeparator}$fileName');
}

Future<Directory> _photoDirectory() async {
  final directory = await getApplicationSupportDirectory();
  return Directory(
    '${directory.path}${Platform.pathSeparator}reference_photos',
  );
}
