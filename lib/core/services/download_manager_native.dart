// Native-only download helpers. Contains all dart:io, audiotags and
// permission_handler code. This file is ONLY compiled when dart.library.html
// is NOT present (native). dart2js will NEVER compile this file.

import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/models.dart';
import '../utils/flac_utils.dart';
import '../utils/web_metadata_writer.dart';

/// Request storage permissions on Android/iOS.
Future<void> requestNativePermissions({
  required bool isAndroid,
  required bool isIOS,
}) async {
  if (isAndroid) {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
    if (!status.isGranted) {
      await Permission.audio.request();
      await Permission.manageExternalStorage.request();
    }
  } else if (isIOS) {
    await Permission.storage.request();
  }
}

/// Write ID3/FLAC metadata tags to a downloaded file.
Future<void> writeNativeMetadata(String filePath, Track track, Dio dio) async {
  final file = File(filePath);
  if (!await file.exists()) return;

  final dir = file.parent;
  final extension = file.path.split('.').last;
  final safeTempName = 'temp_${DateTime.now().millisecondsSinceEpoch}.$extension';
  final safeTempPath = '${dir.path}${Platform.pathSeparator}$safeTempName';
  final safeFile = File(safeTempPath);

  try {
    if (await safeFile.exists()) await safeFile.delete();
    await file.rename(safeTempPath);

    try {
      if (extension == 'm4a' || extension == 'mp4') {
        print('[Metadata] Using WebMetadataWriter (Pure Dart MP4) for native M4A/MP4 tags...');
        final bytes = await safeFile.readAsBytes();
        final newBytes = await WebMetadataWriter.injectMetadata(bytes, track, dio);
        await safeFile.writeAsBytes(newBytes);
        print('[Metadata] Tags written successfully via WebMetadataWriter');
      } else if (extension == 'flac') {
        // NEVER use AudioTags/TagLib on FLAC — it rewrites the file and
        // truncates the audio payload. Use pure-Dart Vorbis Comment injection.
        print('[Metadata] Using FlacUtils (Pure Dart) for FLAC tags...');
        Uint8List? coverBytes;
        String coverMime = 'image/jpeg';
        if (track.albumCover != null && track.albumCover!.isNotEmpty) {
          try {
            final response = await dio.get(
              track.albumCover!,
              options: Options(responseType: ResponseType.bytes),
            );
            if (response.statusCode == 200) {
              coverBytes = Uint8List.fromList(response.data as List<int>);
              coverMime = response.headers.value('content-type') ?? 'image/jpeg';
            }
          } catch (e) {
            print('[Metadata] Error fetching cover art for FLAC: $e');
          }
        }
        final durationSecs = track.duration != null ? (track.duration! > 10000 ? track.duration! ~/ 1000 : track.duration!) : 0;
        await FlacUtils.injectMetadataAndFix(
          safeFile,
          title: track.title,
          artist: track.artist,
          album: track.albumTitle,
          coverBytes: coverBytes,
          coverMimeType: coverMime,
          durationSeconds: durationSecs,
        );
        print('[Metadata] FLAC tags written successfully via FlacUtils');
      } else {
        // Metadata writing for other formats (MP3 etc.) requires audiotags,
        // which is not available on all platforms. Skip gracefully.
        print('[Metadata] Skipping tag write (audiotags not available)');
      }
    } catch (e) {
      print('[Metadata] AudioTags write failed: $e');
    }
  } catch (e) {
    print('[Metadata] Rename error: $e');
  } finally {
    if (await safeFile.exists()) {
      try {
        if (await file.exists()) await file.delete();
        await safeFile.rename(filePath);
      } catch (e) {
        print('[Metadata] CRITICAL: Failed to restore filename: $e');
      }
    }
  }
}

/// Walk the raw FLAC metadata block bytes and clear the isLast bit on the
/// final block, so additional blocks can be appended by FlacUtils.
void _clearLastBlockFlag(Uint8List meta) {
  int offset = 0;
  int lastBlockOffset = -1;
  while (offset + 4 <= meta.length) {
    final headerByte = meta[offset];
    final isLast = (headerByte & 0x80) != 0;
    final length =
        (meta[offset + 1] << 16) | (meta[offset + 2] << 8) | meta[offset + 3];
    lastBlockOffset = offset;
    if (isLast) break;
    offset += 4 + length;
  }
  if (lastBlockOffset != -1) {
    meta[lastBlockOffset] = meta[lastBlockOffset] & 0x7F;
  }
}

/// Trigger web download — no-op on native.
Future<bool> triggerWebDownload(String url, String filename, {Track? track}) async => false;
