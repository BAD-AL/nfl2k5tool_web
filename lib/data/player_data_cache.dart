import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'player_data_file.dart';

/// Lazy-loaded cache of player face photos from the embedded `PlayerData.zip`.
///
/// [ensureLoaded] parses the ZIP directory and stores [ArchiveFile] references
/// without decompressing any photo data — fast enough to call synchronously at
/// startup.  Individual photos are decompressed on first access via [getPhoto]
/// and cached in [_byteCache] so each image is only inflated once.
class PlayerDataCache {
  /// ArchiveFile references keyed by photo ID (no decompression at load time).
  static Map<int, ArchiveFile>? _index;

  /// Decompressed JPEG bytes, populated on first [getPhoto] call per ID.
  static final Map<int, Uint8List> _byteCache = {};

  static Map<String, List<int>>? _categories;

  /// ArchiveFile references keyed by coach body name e.g. `[Dennis Erickson]`.
  static Map<String, ArchiveFile>? _bodyIndex;

  /// Decompressed JPEG bytes for coach bodies, populated on first access.
  static final Map<String, Uint8List> _bodyCache = {};

  /// ArchiveFile references keyed by lowercased equipment-image filename
  /// (no extension), e.g. 'facemask14' -> the ArchiveFile for
  /// 'Facemask14.jpg'. Lowercased because the engine's enum names (e.g.
  /// 'FaceMask14') don't always match the asset's exact casing.
  static Map<String, ArchiveFile>? _equipmentIndex;

  /// Decompressed JPEG bytes for equipment images, populated on first access.
  static final Map<String, Uint8List> _equipmentCache = {};

  /// Parses the ZIP directory on first call; no-op thereafter.
  /// Does NOT decompress any photo data — completes in well under 100 ms.
  static void ensureLoaded() {
    if (_index != null) return;

    final arc = ZipDecoder().decodeBytes(kPlayerDataZip);

    final index = <int, ArchiveFile>{};
    Map<String, List<int>>? categories;

    for (final file in arc.files) {
      if (!file.isFile) continue;
      final name = file.name;

      if ((name.endsWith('.jpg') || name.endsWith('.jpeg')) &&
          name.contains('PlayerPhotos/')) {
        final basename = name.split('/').last;
        final id = int.tryParse(basename.replaceAll(RegExp(r'[^0-9]'), ''));
        if (id != null) {
          index[id] = file; // store ref only — no .content call
        }
      } else if (name.endsWith('.jpg') && name.contains('CoachBodies/')) {
        final basename = name.split('/').last.replaceAll('.jpg', '');
        (_bodyIndex ??= {})[basename] = file;
      } else if (name.endsWith('.jpg') && name.contains('EquipmentImages/')) {
        final basename = name.split('/').last.replaceAll('.jpg', '');
        (_equipmentIndex ??= {})[basename.toLowerCase()] = file;
      } else if (name.endsWith('FaceFormCategories.json')) {
        // Categories JSON is tiny; decode it eagerly.
        final json = utf8.decode(file.content as List<int>);
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        final catList = decoded['categories'] as List<dynamic>;
        categories = {
          for (final item in catList)
            (item as Map<String, dynamic>)['key'] as String:
                ((item['values'] as List<dynamic>).cast<int>()),
        };
      }
    }

    _index = index;
    _categories = categories ?? {};
  }

  /// Returns the JPEG bytes for [id], decompressing from the ZIP on first
  /// access and caching the result.  Returns `null` if the ID is unknown.
  static Uint8List? getPhoto(int id) {
    final cached = _byteCache[id];
    if (cached != null) return cached;
    final archiveFile = _index?[id];
    if (archiveFile == null) return null;
    final bytes = archiveFile.content as Uint8List;
    _byteCache[id] = bytes;
    return bytes;
  }

  /// Returns the JPEG bytes for coach body [name] (e.g. `[Dennis Erickson]`).
  /// Decompresses on first access and caches. Returns `null` if not found.
  static Uint8List? getCoachBody(String name) {
    final cached = _bodyCache[name];
    if (cached != null) return cached;
    final archiveFile = _bodyIndex?[name];
    if (archiveFile == null) return null;
    final bytes = archiveFile.content as Uint8List;
    _bodyCache[name] = bytes;
    return bytes;
  }

  /// Returns the JPEG bytes for the equipment image matching [filenameNoExt]
  /// (e.g. 'Facemask14' or 'GloveType1' — case-insensitive, no extension).
  /// Decompresses on first access and caches. Returns `null` if not found.
  static Uint8List? getEquipmentImage(String filenameNoExt) {
    final key = filenameNoExt.toLowerCase();
    final cached = _equipmentCache[key];
    if (cached != null) return cached;
    final archiveFile = _equipmentIndex?[key];
    if (archiveFile == null) return null;
    final bytes = archiveFile.content as Uint8List;
    _equipmentCache[key] = bytes;
    return bytes;
  }

  /// All available coach body names, sorted.
  static List<String> get allCoachBodyNames {
    final names = (_bodyIndex?.keys ?? <String>[]).toList()..sort();
    return names;
  }

  /// All available photo IDs, sorted ascending.
  static List<int> get allPhotoIds {
    final ids = (_index?.keys ?? <int>[]).toList()..sort();
    return ids;
  }

  /// Category name → list of photo IDs, from `FaceFormCategories.json`.
  static Map<String, List<int>> get faceCategories => _categories ?? {};

  /// Photo IDs belonging to [category], or empty list if not found.
  static List<int> photoIdsForCategory(String category) =>
      _categories?[category] ?? [];
}
