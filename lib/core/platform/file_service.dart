import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// A file chosen by the user.
class PickedFile {
  const PickedFile({
    required this.path,
    required this.name,
    required this.size,
  });
  final String path;
  final String name;
  final int size;
}

/// Native open/save dialogs and safe file reads. One place for the
/// file_picker package so the rest of the app does not depend on it.
abstract interface class FileService {
  /// Opens the system file dialog. Null when the user cancels.
  Future<PickedFile?> pickFile({List<String>? extensions, String? title});

  /// Reads a text file, refusing files larger than [maxBytes].
  Future<String> readText(String path, {int maxBytes = 10 * 1024 * 1024});

  /// Opens the system save dialog and writes [bytes]. Returns the saved path,
  /// or null when cancelled.
  Future<String?> saveBytes(
    String suggestedName,
    Uint8List bytes, {
    String? title,
  });

  Future<String?> saveText(String suggestedName, String text, {String? title});
}

class FileTooLargeException implements Exception {
  const FileTooLargeException(this.path, this.maxBytes);
  final String path;
  final int maxBytes;

  @override
  String toString() => 'FileTooLargeException($path > $maxBytes bytes)';
}

class NativeFileService implements FileService {
  const NativeFileService();

  @override
  Future<PickedFile?> pickFile({
    List<String>? extensions,
    String? title,
  }) async {
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: title,
      type: extensions == null ? FileType.any : FileType.custom,
      allowedExtensions: extensions,
      withData: false,
    );
    final f = res?.files.single;
    final path = f?.path;
    if (f == null || path == null) return null;
    return PickedFile(path: path, name: f.name, size: f.size);
  }

  @override
  Future<String> readText(
    String path, {
    int maxBytes = 10 * 1024 * 1024,
  }) async {
    final file = File(path);
    final length = await file.length();
    if (length > maxBytes) throw FileTooLargeException(path, maxBytes);
    return utf8.decode(await file.readAsBytes(), allowMalformed: true);
  }

  @override
  Future<String?> saveBytes(
    String suggestedName,
    Uint8List bytes, {
    String? title,
  }) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: title,
      fileName: suggestedName,
      bytes: bytes,
    );
    if (path == null) return null;
    // On Windows and Linux the dialog only returns a path; write the file.
    // On Android the plugin already wrote it from [bytes].
    if (!Platform.isAndroid) {
      await File(path).writeAsBytes(bytes, flush: true);
    }
    return path;
  }

  @override
  Future<String?> saveText(
    String suggestedName,
    String text, {
    String? title,
  }) => saveBytes(
    suggestedName,
    Uint8List.fromList(utf8.encode(text)),
    title: title,
  );
}

/// File service for tests: no dialogs, scripted answers.
class FakeFileService implements FileService {
  FakeFileService({this.picked, Map<String, String>? files})
    : files = files ?? <String, String>{};

  PickedFile? picked;
  final Map<String, String> files;
  final Map<String, Uint8List> saved = <String, Uint8List>{};

  @override
  Future<PickedFile?> pickFile({
    List<String>? extensions,
    String? title,
  }) async => picked;

  @override
  Future<String> readText(
    String path, {
    int maxBytes = 10 * 1024 * 1024,
  }) async {
    final t = files[path];
    if (t == null) throw FileSystemException('not found', path);
    if (t.length > maxBytes) throw FileTooLargeException(path, maxBytes);
    return t;
  }

  @override
  Future<String?> saveBytes(
    String suggestedName,
    Uint8List bytes, {
    String? title,
  }) async {
    saved[suggestedName] = bytes;
    return '/fake/$suggestedName';
  }

  @override
  Future<String?> saveText(
    String suggestedName,
    String text, {
    String? title,
  }) => saveBytes(suggestedName, Uint8List.fromList(utf8.encode(text)));
}
