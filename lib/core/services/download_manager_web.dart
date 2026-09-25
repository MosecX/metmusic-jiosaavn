// Web-only download helpers.
// On web, we must use a proxy and Blob URLs since browsers ignore 'download' on cross-origin URLs.
import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:dio/dio.dart';

import '../models/models.dart';
import '../utils/web_metadata_writer.dart';

const String _proxyBase =
    'https://webdownloadproxy.thevolecitor.workers.dev/?url=';

/// Triggers a browser file download by fetching through a CORS proxy.
Future<bool> triggerWebDownload(String url, String filename,
    {Track? track}) async {
  try {
    final proxyUrl = '$_proxyBase${Uri.encodeComponent(url)}';

    final dio = Dio();
    final response = await dio.get<List<int>>(
      proxyUrl,
      options: Options(responseType: ResponseType.bytes),
    );

    if (response.data == null) return false;
    Uint8List bytes = Uint8List.fromList(response.data!);

    // Inject metadata if track info is provided
    if (track != null) {
      bytes = await WebMetadataWriter.injectMetadata(bytes, track, dio);
    }

    return await triggerWebDownloadBlob(bytes, filename);
  } catch (e) {
    print('[WebDownload] Error: $e');
    return false;
  }
}

/// Helper for Blobs on Web
Future<bool> triggerWebDownloadBlob(Uint8List bytes, String filename) async {
  try {
    final blob = web.Blob([bytes.toJS].toJS);
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = filename;
    anchor.click();
    web.URL.revokeObjectURL(url);
    return true;
  } catch (e) {
    print('[WebBlob] Error: $e');
    return false;
  }
}

Future<void> requestNativePermissions(
    {required bool isAndroid, required bool isIOS}) async {}
Future<void> writeNativeMetadata(String filePath, Track track, Dio dio) async {}
Future<void> renameFile(String from, String to) async {}
