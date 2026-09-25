import 'dart:io';
import 'package:path_provider/path_provider.dart';

class TidalMpdStorage {
  static Future<String?> save(String trackId, String mpdXml) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/tidal_${trackId}_${DateTime.now().millisecondsSinceEpoch}.mpd');
      await file.writeAsString(mpdXml);
      print('[Tidal] Saved MPD to ${file.path}');
      return file.uri.toString();
    } catch (e) {
      print('[Tidal] Failed to save MPD: $e');
      return null;
    }
  }
}