import 'dart:io';
import 'dart:typed_data';

import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'platform_store.dart';

PlatformStore createPlatformStoreImpl() => IoPlatformStore();

class IoPlatformStore implements PlatformStore {
  @override
  bool get isWeb => false;

  @override
  Future<String?> readText(String name) async {
    final file = await _textFile(name);
    if (!await file.exists()) {
      return null;
    }
    return file.readAsString();
  }

  @override
  Future<void> writeText(String name, String value) async {
    final file = await _textFile(name);
    await file.writeAsString(value, flush: true);
  }

  @override
  Future<void> deleteText(String name) async {
    final file = await _textFile(name);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<String> saveBytes(
    Uint8List bytes, {
    required String folder,
    required String name,
    required String extension,
  }) async {
    final dir = await _ensureDir(folder);
    final file = File('${dir.path}/$name.$extension');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  @override
  Future<Uint8List?> readBytes(String reference) async {
    final file = File(reference);
    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  @override
  Future<bool> exists(String reference) => File(reference).exists();

  @override
  Future<bool> saveImageToUserDevice(
    Uint8List bytes, {
    required String name,
  }) async {
    final result = await ImageGallerySaverPlus.saveImage(
      bytes,
      quality: 100,
      name: name,
    );
    return result['isSuccess'] == true || result['filePath'] != null;
  }

  @override
  Future<void> shareImage(
    Uint8List bytes, {
    required String text,
    String? reference,
  }) async {
    final path =
        reference ??
        await saveBytes(
          bytes,
          folder: 'shares',
          name: DateTime.now().microsecondsSinceEpoch.toString(),
          extension: 'png',
        );
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], text: text),
    );
  }

  Future<File> _textFile(String name) async =>
      File('${(await _appDir()).path}/$name');

  Future<Directory> _ensureDir(String name) async {
    final dir = Directory('${(await _appDir()).path}/$name');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _appDir() => getApplicationDocumentsDirectory();
}
