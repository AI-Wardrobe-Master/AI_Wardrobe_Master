import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String?> readCollections(String fileName) async {
  try {
    final file = await _storageFile(fileName);
    if (!await file.exists()) {
      return null;
    }
    return await file.readAsString();
  } catch (_) {
    return null;
  }
}

Future<void> writeCollections(String fileName, String payload) async {
  try {
    final file = await _storageFile(fileName);
    await file.parent.create(recursive: true);
    await file.writeAsString(payload);
  } catch (_) {
    return;
  }
}

Future<File> _storageFile(String fileName) async {
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}${Platform.pathSeparator}$fileName');
}
