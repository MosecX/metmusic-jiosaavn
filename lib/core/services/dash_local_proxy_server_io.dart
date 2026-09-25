import 'dart:io';
import 'package:http/http.dart' as http;
import 'dash_native_parser.dart';

class DashLocalProxyServer {
  static HttpServer? _server;
  static DashManifest? _currentManifest;
  static String? _proxyUrl;
  static double Function()? _getPosition;
  // Uniform (approximate) segment size + init size, used to map byte ranges to
  // segments so the player can seek within the concatenated fMP4 stream.
  static List<int> _segmentSizes = <int>[];
  static int _initSize = 0;
  static int _totalBytes = 0;

  static Future<String> start(DashManifest manifest,
      {String? proxyUrl, double Function()? getPosition}) async {
    _currentManifest = manifest;
    _proxyUrl = proxyUrl;
    _getPosition = getPosition;
    await _computeSizes(manifest);

    if (_server == null) {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server!.listen(_handleRequest);
    }

    return 'http://127.0.0.1:${_server!.port}/stream';
  }

  /// Fetch the exact init + per-segment sizes so a byte range can be mapped to
  /// the precise fMP4 fragment. Seeking must land on the exact fragment the
  /// extractor expects (its seek map is built from real byte offsets), so an
  /// approximate/uniform size would send the wrong fragment and the decoder
  /// would restart. A handful of HEAD requests at stream start is cheap.
  static Future<void> _computeSizes(DashManifest manifest) async {
    _segmentSizes = <int>[];
    _totalBytes = 0;
    _initSize = 0;
    final urls = manifest.mediaSegmentUrls;
    if (urls.isEmpty) return;
    _initSize = await _sizeOf(manifest.initSegmentUrl);
    final sizes = await Future.wait<int>(urls.map((u) => _sizeOf(u)));
    _segmentSizes = sizes;
    _totalBytes =
        (_initSize > 0 ? _initSize : 0) + sizes.fold(0, (a, b) => a + b);
  }

  static Future<int> _sizeOf(String url) async {
    final u = _proxy(url);
    try {
      final r = await http.head(Uri.parse(u));
      final cl = r.headers['content-length'];
      if (cl != null) return int.tryParse(cl) ?? 0;
    } catch (_) {}
    try {
      final r = await http.get(Uri.parse(u), headers: {'Range': 'bytes=0-0'});
      final cr = r.headers['content-range'];
      if (cr != null) {
        final parts = cr.split('/');
        if (parts.length == 2) return int.tryParse(parts[1]) ?? 0;
      }
      if (r.contentLength != null && r.contentLength! > 0) return r.contentLength!;
    } catch (_) {}
    return 0;
  }

  static String _proxy(String url) {
    if (_proxyUrl != null && url.startsWith('http')) {
      return '$_proxyUrl${Uri.encodeComponent(url)}';
    }
    return url;
  }

  static Future<void> _handleRequest(HttpRequest request) async {
    if (_currentManifest == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final manifest = _currentManifest!;
    final response = request.response;
    response.headers.contentType = ContentType('audio', 'mp4');

    // Parse a Range request (the player issues these on seek).
    int startByte = 0;
    int? endByte;
    bool isRange = false;
    final rangeHeader = request.headers.value('range');
    if (rangeHeader != null && _totalBytes > 0 && _segmentSizes.isNotEmpty) {
      final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(rangeHeader);
      if (m != null) {
        startByte = int.tryParse(m.group(1)!) ?? 0;
        final endStr = m.group(2);
        endByte = (endStr != null && endStr.isNotEmpty) ? int.tryParse(endStr) : null;
        isRange = true;
      }
    }

    // On a normal (non-range) load we serve init + all segments. On a seek the
    // fMP4 extractor already parsed the init (moov) during the first load, so a
    // range response must contain the EXACT bytes the player asked for — we must
    // NOT re-prepend the init, or every following byte shifts and the decoder
    // seeks into garbage and restarts. The only exception is a seek that lands
    // inside the (tiny) init region, which we treat as "play from the start".
    final serveFromStart = !isRange || startByte < _initSize;

    // Map the media byte offset to the precise fragment (using real sizes).
    int segIndex = 0;
    int segOffset = 0;
    if (isRange && !serveFromStart) {
      final mediaStart = startByte - _initSize;
      int cum = 0;
      bool found = false;
      for (int i = 0; i < _segmentSizes.length; i++) {
        final sz = _segmentSizes[i];
        if (sz > 0 && cum + sz > mediaStart) {
          segIndex = i;
          segOffset = mediaStart - cum;
          found = true;
          break;
        }
        cum += sz;
        segIndex = i;
      }
      if (!found) {
        segIndex = _segmentSizes.length - 1;
        segOffset = 0;
      }
    }

    final initBytes = await _fetchBytes(manifest.initSegmentUrl);

    if (isRange) {
      final contentLength = (endByte != null ? endByte - startByte + 1 : _totalBytes - startByte)
          .clamp(0, _totalBytes - startByte);
      final lastByte = startByte + contentLength - 1;
      response.statusCode = HttpStatus.partialContent;
      response.headers.set('Accept-Ranges', 'bytes');
      response.headers
          .set('Content-Range', 'bytes $startByte-$lastByte/$_totalBytes');
      response.headers.set('Content-Length', '$contentLength');
    } else {
      // Advertise seek support; stream is chunked (variable segment sizes).
      response.headers.set('Accept-Ranges', 'bytes');
    }

    try {
      int sent = 0;
      if (serveFromStart && initBytes != null) {
        // Initial/near-start load: prepend init so the extractor can parse moov.
        response.add(initBytes);
        sent += initBytes.length;
        await response.flush();
      }

      final startIdx = serveFromStart ? 0 : segIndex;
      final startOff = serveFromStart ? 0 : segOffset;
      for (int i = startIdx; i < manifest.mediaSegmentUrls.length; i++) {
        if (request.response.connectionInfo == null) break;

        // Throttle only for the non-seek (live) forward stream.
        if (!isRange && _getPosition != null && manifest.segmentDuration > 0) {
          final currentPos = _getPosition!();
          final segmentStartPos = i * manifest.segmentDuration;
          final leadTime = segmentStartPos - currentPos;
          if (leadTime > 15.0) {
            bool connected = true;
            while (_getPosition != null) {
              if (request.response.connectionInfo == null) {
                connected = false;
                break;
              }
              final newPos = _getPosition!();
              if (segmentStartPos - newPos <= 10.0) break;
              await Future.delayed(const Duration(milliseconds: 500));
            }
            if (!connected) break;
          }
        }

        final bytes = await _fetchBytes(manifest.mediaSegmentUrls[i]);
        if (bytes == null) break;
        final chunk = (i == startIdx && startOff > 0) ? bytes.sublist(startOff) : bytes;

        if (isRange) {
          final remaining = (endByte != null ? endByte - startByte + 1 : _totalBytes - startByte) - sent;
          if (remaining <= 0) break;
          final toAdd = chunk.length > remaining ? chunk.sublist(0, remaining) : chunk;
          response.add(toAdd);
          sent += toAdd.length;
        } else {
          response.add(chunk);
          sent += chunk.length;
        }
        await response.flush();
        if (isRange && sent >= (endByte != null ? endByte - startByte + 1 : _totalBytes - startByte)) {
          break;
        }
      }
    } catch (e) {
      print('[DashLocalProxyServer] Stream error: $e');
    } finally {
      await response.close();
    }
  }

  static Future<List<int>?> _fetchBytes(String url) async {
    try {
      final r = await http.get(Uri.parse(_proxy(url)));
      if (r.statusCode == 200 || r.statusCode == 206) return r.bodyBytes;
    } catch (e) {
      print('[DashLocalProxyServer] Segment error: $e');
    }
    return null;
  }

  static void stop() {
    _server?.close(force: true);
    _server = null;
    _currentManifest = null;
    _getPosition = null;
    _segmentSizes = <int>[];
    _initSize = 0;
    _totalBytes = 0;
  }
}
