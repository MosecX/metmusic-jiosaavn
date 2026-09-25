export 'tidal_mpd_storage_stub.dart'
    if (dart.library.io) 'tidal_mpd_storage_io.dart';

abstract class TidalMpdStorage {
  static Future<String?> save(String trackId, String mpdXml) =>
      throw UnimplementedError();
}