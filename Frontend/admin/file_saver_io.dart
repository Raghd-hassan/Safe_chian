// Mobile/Desktop implementation for file saving
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';

Future<void> saveFile(Uint8List bytes, String fileName, String mimeType) async {
  Directory? directory;
  if (Platform.isWindows) {
    directory = await getDownloadsDirectory();
  } else if (Platform.isAndroid) {
    directory = Directory('/storage/emulated/0/Download');
  } else {
    directory = await getApplicationDocumentsDirectory();
  }

  final filePath =
      '${directory?.path ?? '.'}${Platform.pathSeparator}$fileName';
  await File(filePath).writeAsBytes(bytes);
  await OpenFile.open(filePath);
}
