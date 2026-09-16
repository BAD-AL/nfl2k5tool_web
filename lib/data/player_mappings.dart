import 'package:nfl2k5tool_dart/nfl2k5tool_dart.dart' show DataMap;
import 'package:nfl2k5tool_dart/enf_photo_index.dart' show kEnfPhotoIndexContent;

/// A display entry for a mapped ID field (Photo or PBP).
class MappedEntry {
  final String id;   // numeric ID as string
  final String name; // display name
  const MappedEntry(this.id, this.name);
}

/// Photo ID → player name, parsed from `kEnfPhotoIndexContent`.
/// Format per line: `"Last, First=NNNN"`
final List<MappedEntry> photoOptions = _parsePhotoIndex();

final Map<String, String> _photoNameById = {
  for (final e in photoOptions) e.id: e.name,
};

String photoIdToDisplayName(String id) =>
    _photoNameById[id] ?? _photoNameById[id.padLeft(4, '0')] ?? '';

/// Returns the display name for a PBP ID using DataMap.ReversePBPMap.
String pbpIdToDisplayName(String id) =>
    DataMap.ReversePBPMap[id] ?? DataMap.ReversePBPMap[id.padLeft(4, '0')] ?? '';

// ─── Parsers ──────────────────────────────────────────────────────────────────

List<MappedEntry> _parsePhotoIndex() {
  final entries = <MappedEntry>[];
  for (final line in kEnfPhotoIndexContent.split('\n')) {
    final t = line.trim();
    if (t.isEmpty) continue;
    final eq = t.indexOf('=');
    if (eq < 0) continue;
    final name = t.substring(0, eq).trim();
    final id   = t.substring(eq + 1).trim();
    if (id.isNotEmpty) entries.add(MappedEntry(id, name));
  }
  return entries;
}

