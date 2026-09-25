import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:reicon_flutter/reicon_flutter.dart';

/// Reicon helper for consistent icon usage throughout the app
/// Uses reicon_flutter for SVG icons rendered via flutter_svg
class ReIcon {
  ReIcon._();

  /// Wraps a Reicon outline icon path in an SvgPicture widget
  static Widget outline(String iconName, {
    double? size,
    Color? color,
  }) {
    final path = Reicon.outline[iconName];
    if (path == null) {
      return SizedBox(width: size ?? 24, height: size ?? 24);
    }
    final svgString = reiconSvg(path, size: (size ?? 24).toInt());
    return SvgPicture.string(
      svgString,
      width: size ?? 24,
      height: size ?? 24,
      colorFilter: color != null
          ? ColorFilter.mode(color, BlendMode.srcIn)
          : null,
    );
  }

  /// Wraps a Reicon filled icon path in an SvgPicture widget
  static Widget filled(String iconName, {
    double? size,
    Color? color,
  }) {
    final path = Reicon.filled[iconName];
    if (path == null) {
      return SizedBox(width: size ?? 24, height: size ?? 24);
    }
    final svgString = reiconSvg(path, size: (size ?? 24).toInt());
    return SvgPicture.string(
      svgString,
      width: size ?? 24,
      height: size ?? 24,
      colorFilter: color != null
          ? ColorFilter.mode(color, BlendMode.srcIn)
          : null,
    );
  }

  // Common music app icons - outline variants
  static Widget home({double? size, Color? color}) =>
      outline('home', size: size, color: color);

  static Widget search({double? size, Color? color}) =>
      outline('search', size: size, color: color);

  static Widget library({double? size, Color? color}) =>
      outline('library', size: size, color: color);

  static Widget settings({double? size, Color? color}) =>
      outline('settings', size: size, color: color);

  static Widget play({double? size, Color? color}) =>
      outline('play', size: size, color: color);

  static Widget playCircle({double? size, Color? color}) =>
      outline('play_circle', size: size, color: color);

  static Widget pause({double? size, Color? color}) =>
      outline('pause', size: size, color: color);

  static Widget pauseCircle({double? size, Color? color}) =>
      outline('pause_circle', size: size, color: color);

  static Widget skipBack({double? size, Color? color}) =>
      outline('skip_back', size: size, color: color);

  static Widget skipForward({double? size, Color? color}) =>
      outline('skip_forward', size: size, color: color);

  static Widget shuffle({double? size, Color? color}) =>
      outline('shuffle', size: size, color: color);

  static Widget repeat({double? size, Color? color}) =>
      outline('repeat', size: size, color: color);

  static Widget heart({double? size, Color? color}) =>
      outline('heart', size: size, color: color);

  static Widget heartFilled({double? size, Color? color}) =>
      filled('heart', size: size, color: color);

  static Widget download({double? size, Color? color}) =>
      outline('download', size: size, color: color);

  static Widget downloadCloud({double? size, Color? color}) =>
      outline('download_cloud', size: size, color: color);

  static Widget uploadCloud({double? size, Color? color}) =>
      outline('upload_cloud', size: size, color: color);

  static Widget queue({double? size, Color? color}) =>
      outline('queue', size: size, color: color);

  static Widget musicNote({double? size, Color? color}) =>
      outline('music_note', size: size, color: color);

  static Widget musicNote2({double? size, Color? color}) =>
      outline('music_note', size: size, color: color);

  static Widget album({double? size, Color? color}) =>
      outline('album', size: size, color: color);

  static Widget artist({double? size, Color? color}) =>
      outline('user', size: size, color: color);

  static Widget playlist({double? size, Color? color}) =>
      outline('playlist', size: size, color: color);

  static Widget add({double? size, Color? color}) =>
      outline('plus', size: size, color: color);

  static Widget addCircle({double? size, Color? color}) =>
      outline('plus_circle', size: size, color: color);

  static Widget remove({double? size, Color? color}) =>
      outline('minus', size: size, color: color);

  static Widget removeCircle({double? size, Color? color}) =>
      outline('minus_circle', size: size, color: color);

  static Widget close({double? size, Color? color}) =>
      outline('x', size: size, color: color);

  static Widget check({double? size, Color? color}) =>
      outline('check', size: size, color: color);

  static Widget chevronRight({double? size, Color? color}) =>
      outline('chevron_right', size: size, color: color);

  static Widget chevronLeft({double? size, Color? color}) =>
      outline('chevron_left', size: size, color: color);

  static Widget chevronDown({double? size, Color? color}) =>
      outline('chevron_down', size: size, color: color);

  static Widget menu({double? size, Color? color}) =>
      outline('menu', size: size, color: color);

  static Widget moreVertical({double? size, Color? color}) =>
      outline('more_vertical', size: size, color: color);

  static Widget moreHorizontal({double? size, Color? color}) =>
      outline('more_horizontal', size: size, color: color);

  static Widget share({double? size, Color? color}) =>
      outline('share', size: size, color: color);

  static Widget shareIos({double? size, Color? color}) =>
      outline('share', size: size, color: color);

  static Widget link({double? size, Color? color}) =>
      outline('link', size: size, color: color);

  static Widget copy({double? size, Color? color}) =>
      outline('copy', size: size, color: color);

  static Widget paste({double? size, Color? color}) =>
      outline('paste', size: size, color: color);

  static Widget trash({double? size, Color? color}) =>
      outline('trash', size: size, color: color);

  static Widget edit({double? size, Color? color}) =>
      outline('edit', size: size, color: color);

  static Widget editPencil({double? size, Color? color}) =>
      outline('edit', size: size, color: color);

  static Widget searchMagnifying({double? size, Color? color}) =>
      outline('search', size: size, color: color);

  static Widget cloud({double? size, Color? color}) =>
      outline('cloud', size: size, color: color);

  static Widget cloudOff({double? size, Color? color}) =>
      outline('cloud_off', size: size, color: color);

  static Widget wifi({double? size, Color? color}) =>
      outline('wifi', size: size, color: color);

  static Widget wifiOff({double? size, Color? color}) =>
      outline('wifi_off', size: size, color: color);

  static Widget sync({double? size, Color? color}) =>
      outline('sync', size: size, color: color);

  static Widget refresh({double? size, Color? color}) =>
      outline('refresh', size: size, color: color);

  static Widget extension({double? size, Color? color}) =>
      outline('extension', size: size, color: color);

  static Widget extensionOff({double? size, Color? color}) =>
      outline('extension_off', size: size, color: color);

  static Widget folder({double? size, Color? color}) =>
      outline('folder', size: size, color: color);

  static Widget folderOpen({double? size, Color? color}) =>
      outline('folder_open', size: size, color: color);

  static Widget file({double? size, Color? color}) =>
      outline('file', size: size, color: color);

  static Widget fileAudio({double? size, Color? color}) =>
      outline('file_audio', size: size, color: color);

  static Widget filter({double? size, Color? color}) =>
      outline('filter', size: size, color: color);

  static Widget sort({double? size, Color? color}) =>
      outline('sort', size: size, color: color);

  static Widget volume({double? size, Color? color}) =>
      outline('volume', size: size, color: color);

  static Widget volumeMute({double? size, Color? color}) =>
      outline('volume_x', size: size, color: color);

  static Widget volumeLow({double? size, Color? color}) =>
      outline('volume_low', size: size, color: color);

  static Widget volumeHigh({double? size, Color? color}) =>
      outline('volume', size: size, color: color);

  static Widget speaker({double? size, Color? color}) =>
      outline('speaker', size: size, color: color);

  static Widget headphones({double? size, Color? color}) =>
      outline('headphones', size: size, color: color);

  static Widget mic({double? size, Color? color}) =>
      outline('mic', size: size, color: color);

  static Widget micOff({double? size, Color? color}) =>
      outline('mic_off', size: size, color: color);

  static Widget camera({double? size, Color? color}) =>
      outline('camera', size: size, color: color);

  static Widget image({double? size, Color? color}) =>
      outline('image', size: size, color: color);

  static Widget imageSquare({double? size, Color? color}) =>
      outline('image_square', size: size, color: color);

  static Widget video({double? size, Color? color}) =>
      outline('video', size: size, color: color);

  static Widget playList({double? size, Color? color}) =>
      outline('playlist', size: size, color: color);

  static Widget playListAdd({double? size, Color? color}) =>
      outline('playlist_add', size: size, color: color);

  static Widget loader({double? size, Color? color}) =>
      outline('loader', size: size, color: color);

  static Widget loaderCircle({double? size, Color? color}) =>
      outline('loader', size: size, color: color);

  static Widget clock({double? size, Color? color}) =>
      outline('clock', size: size, color: color);

  static Widget calendar({double? size, Color? color}) =>
      outline('calendar', size: size, color: color);

  static Widget star({double? size, Color? color}) =>
      outline('star', size: size, color: color);

  static Widget starFilled({double? size, Color? color}) =>
      filled('star', size: size, color: color);

  static Widget info({double? size, Color? color}) =>
      outline('info', size: size, color: color);

  static Widget help({double? size, Color? color}) =>
      outline('help', size: size, color: color);

  static Widget warning({double? size, Color? color}) =>
      outline('warning', size: size, color: color);

  static Widget error({double? size, Color? color}) =>
      outline('error', size: size, color: color);

  static Widget checkCircle({double? size, Color? color}) =>
      outline('check_circle', size: size, color: color);

  static Widget checkCircleFilled({double? size, Color? color}) =>
      filled('check_circle', size: size, color: color);

  static Widget arrowRight({double? size, Color? color}) =>
      outline('arrow_right', size: size, color: color);

  static Widget arrowLeft({double? size, Color? color}) =>
      outline('arrow_left', size: size, color: color);

  static Widget arrowUp({double? size, Color? color}) =>
      outline('arrow_up', size: size, color: color);

  static Widget arrowDown({double? size, Color? color}) =>
      outline('arrow_down', size: size, color: color);

  static Widget externalLink({double? size, Color? color}) =>
      outline('external_link', size: size, color: color);

  static Widget maximize({double? size, Color? color}) =>
      outline('maximize', size: size, color: color);

  static Widget minimize({double? size, Color? color}) =>
      outline('minimize', size: size, color: color);

  static Widget grid({double? size, Color? color}) =>
      outline('grid', size: size, color: color);

  static Widget list({double? size, Color? color}) =>
      outline('list', size: size, color: color);

  static Widget layout({double? size, Color? color}) =>
      outline('layout', size: size, color: color);

  static Widget lock({double? size, Color? color}) =>
      outline('lock', size: size, color: color);

  static Widget lockOpen({double? size, Color? color}) =>
      outline('lock_open', size: size, color: color);

  static Widget key({double? size, Color? color}) =>
      outline('key', size: size, color: color);

  static Widget mail({double? size, Color? color}) =>
      outline('mail', size: size, color: color);

  static Widget send({double? size, Color? color}) =>
      outline('send', size: size, color: color);

  static Widget user({double? size, Color? color}) =>
      outline('user', size: size, color: color);

  static Widget users({double? size, Color? color}) =>
      outline('users', size: size, color: color);

  static Widget globe({double? size, Color? color}) =>
      outline('globe', size: size, color: color);

  static Widget moon({double? size, Color? color}) =>
      outline('moon', size: size, color: color);

  static Widget sun({double? size, Color? color}) =>
      outline('sun', size: size, color: color);

  static Widget zap({double? size, Color? color}) =>
      outline('zap', size: size, color: color);

  static Widget sparkles({double? size, Color? color}) =>
      outline('sparkles', size: size, color: color);

  static Widget sparkle({double? size, Color? color}) =>
      outline('sparkle', size: size, color: color);

  static Widget autoAwesome({double? size, Color? color}) =>
      outline('auto_awesome', size: size, color: color);

  static Widget lyrics({double? size, Color? color}) =>
      outline('lyrics', size: size, color: color);
}
