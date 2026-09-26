// Web implementation for file saving
import 'dart:html' as html;
import 'dart:typed_data';

Future<void> saveFile(Uint8List bytes, String fileName, String mimeType) async {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement()
    ..href = url
    ..download = fileName
    ..click();
  html.Url.revokeObjectUrl(url);
}
