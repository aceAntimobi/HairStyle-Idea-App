import 'dart:typed_data';

import 'platform_store_io.dart'
    if (dart.library.html) 'platform_store_web.dart';

abstract class PlatformStore {
  bool get isWeb;

  Future<String?> readText(String name);
  Future<void> writeText(String name, String value);
  Future<void> deleteText(String name);

  Future<String> saveBytes(
    Uint8List bytes, {
    required String folder,
    required String name,
    required String extension,
  });

  Future<Uint8List?> readBytes(String reference);
  Future<bool> exists(String reference);
  Future<bool> saveImageToUserDevice(Uint8List bytes, {required String name});
  Future<void> shareImage(
    Uint8List bytes, {
    required String text,
    String? reference,
  });
}

PlatformStore createPlatformStore() => createPlatformStoreImpl();
