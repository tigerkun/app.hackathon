import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

abstract class IStorageService {
  Future<void> setString(String key, String value);
  Future<String?> getString(String key);
  Future<void> remove(String key);
  Future<void> clear();
}

/// Persistent Storage Service
/// Automatically persists session credentials, tokens, and PIN settings to local disk
/// so they survive app restarts, with fallback to memory for transient environments.
class StorageService implements IStorageService {
  static final Map<String, String> _memoryStore = {};
  static bool _isLoaded = false;
  static File? _storageFile;

  static Future<void> _initPersistence() async {
    if (_isLoaded) return;
    try {
      // Platform-safe persistent directory via path_provider.
      // Covers Android, iOS, Windows, macOS, and Linux — the previous
      // Platform.is* branches silently skipped Android/iOS entirely.
      final docsDir = await getApplicationDocumentsDirectory();
      final baseDir = Directory('${docsDir.path}/safesphere');
      if (!await baseDir.exists()) {
        await baseDir.create(recursive: true);
      }
      _storageFile = File('${baseDir.path}/user_session_store.json');
      if (await _storageFile!.exists()) {
        final content = await _storageFile!.readAsString();
        if (content.isNotEmpty) {
          final decoded = jsonDecode(content);
          if (decoded is Map<String, dynamic>) {
            decoded.forEach((k, v) {
              _memoryStore[k] = v.toString();
            });
          }
        }
      }
    } catch (_) {
      // Graceful fallback to memory store
    } finally {
      _isLoaded = true;
    }
  }

  static Future<void> _saveToDisk() async {
    if (_storageFile == null) return;
    try {
      await _storageFile!.writeAsString(jsonEncode(_memoryStore));
    } catch (_) {}
  }

  @override
  Future<void> setString(String key, String value) async {
    await _initPersistence();
    _memoryStore[key] = value;
    await _saveToDisk();
  }

  @override
  Future<String?> getString(String key) async {
    await _initPersistence();
    return _memoryStore[key];
  }

  @override
  Future<void> remove(String key) async {
    await _initPersistence();
    _memoryStore.remove(key);
    await _saveToDisk();
  }

  @override
  Future<void> clear() async {
    await _initPersistence();
    _memoryStore.clear();
    await _saveToDisk();
  }
}
