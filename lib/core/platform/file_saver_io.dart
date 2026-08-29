import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String?> saveFile({
  required String fileName,
  required String contents,
  required String mimeType,
}) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsString(contents, flush: true);
  return file.path;
}
