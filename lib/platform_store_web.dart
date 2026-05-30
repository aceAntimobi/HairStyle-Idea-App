// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'platform_store.dart';

PlatformStore createPlatformStoreImpl() => WebPlatformStore();

class WebPlatformStore implements PlatformStore {
  static const _prefix = 'hair_flutter_v2_';

  @override
  bool get isWeb => true;

  @override
  Future<String?> readText(String name) async {
    return html.window.localStorage['$_prefix$name'];
  }

  @override
  Future<void> writeText(String name, String value) async {
    try {
      html.window.localStorage['$_prefix$name'] = value;
    } catch (_) {
      // Browser storage is quota-bound. Keep the in-memory app flow usable even
      // if history persistence is too large for localStorage.
    }
  }

  @override
  Future<void> deleteText(String name) async {
    html.window.localStorage.remove('$_prefix$name');
  }

  @override
  Future<String> saveBytes(
    Uint8List bytes, {
    required String folder,
    required String name,
    required String extension,
  }) async {
    final mime =
        extension.toLowerCase() == 'jpg' || extension.toLowerCase() == 'jpeg'
        ? 'image/jpeg'
        : 'image/png';
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  @override
  Future<Uint8List?> readBytes(String reference) async {
    final comma = reference.indexOf(',');
    if (!reference.startsWith('data:') || comma < 0) {
      return null;
    }
    return base64Decode(reference.substring(comma + 1));
  }

  @override
  Future<bool> exists(String reference) async {
    return reference.startsWith('data:') && reference.contains(',');
  }

  @override
  Future<bool> saveImageToUserDevice(
    Uint8List bytes, {
    required String name,
  }) async {
    _downloadDataUri(
      'data:image/png;base64,${base64Encode(bytes)}',
      '$name.png',
    );
    return true;
  }

  @override
  Future<void> shareImage(
    Uint8List bytes, {
    required String text,
    String? reference,
  }) async {
    await saveImageToUserDevice(
      bytes,
      name: 'hairstyle_share_${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  void _downloadDataUri(String dataUri, String filename) {
    final anchor = html.AnchorElement(href: dataUri)
      ..download = filename
      ..style.display = 'none';
    html.document.body?.children.add(anchor);
    anchor.click();
    anchor.remove();
  }
}
