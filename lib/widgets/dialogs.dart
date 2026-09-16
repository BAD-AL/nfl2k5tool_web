import 'dart:js_interop';
import 'dart:typed_data';
import 'package:nfl2k5tool_dart/nfl2k5tool_dart.dart' show DataMap;
import 'package:web/web.dart';

import '../data/player_data_cache.dart';
import '../data/player_mappings.dart';

// ─── Shared dialog helpers ────────────────────────────────────────────────────

/// Wires close-on-ESC for a dialog, storing the listener so it can be removed.
/// Returns the JSFunction reference that must be passed to [_removeEscListener].
JSFunction _addEscListener(void Function() close) {
  late final JSFunction fn;
  fn = (Event e) {
    if ((e as KeyboardEvent).key == 'Escape') close();
  }.toJS;
  document.addEventListener('keydown', fn);
  return fn;
}

void _removeEscListener(JSFunction fn) {
  document.removeEventListener('keydown', fn);
}

/// Wires click-outside-to-close on the overlay backdrop.
/// Clicks that bubble up to the overlay itself (i.e. on the dark area, not
/// inside the dialog box) call [close].  The inner dialog box gets a
/// stopPropagation listener so its clicks never reach the overlay.
void _wireOverlayClose(HTMLElement overlay, void Function() close) {
  // Clicking the dark backdrop closes the dialog
  overlay.addEventListener('click', (Event e) {
    if ((e.target as HTMLElement?) == overlay) close();
  }.toJS);
  // Stop clicks inside the dialog from bubbling to the backdrop
  (overlay.firstElementChild as HTMLElement?)
      ?.addEventListener('click', (Event e) { e.stopPropagation(); }.toJS);
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

// ─── Face Picker Dialog ───────────────────────────────────────────────────────

/// Shows a face-photo picker dialog with virtual-scrolled thumbnails.
class FacePickerDialog {
  HTMLElement? _overlay;
  _VirtualFaceGrid? _grid;
  String? _selectedId;
  JSFunction? _escFn;

  void open({
    required int? currentId,
    required void Function(String id) onPicked,
  }) {
    if (_overlay != null) return; // already open
    PlayerDataCache.ensureLoaded();
    _selectedId = currentId?.toString();

    final overlay = document.createElement('div') as HTMLElement;
    overlay.className = 'dialog-overlay';
    overlay.innerHTML = _buildShellHtml().toJS;
    document.body!.append(overlay);
    _overlay = overlay;

    _escFn = _addEscListener(close);
    _wireOverlayClose(overlay, close);

    final cancelBtn = overlay.querySelector('#fp-cancel') as HTMLElement?;
    cancelBtn?.addEventListener('click', (Event e) { e.stopPropagation(); close(); }.toJS);
    // X button delegates to cancel so both behave identically
    overlay.querySelector('.dialog-close')
        ?.addEventListener('click', (Event _) { cancelBtn?.click(); }.toJS);

    overlay.querySelector('#fp-confirm')?.addEventListener('click', (Event e) {
      e.stopPropagation();
      final id = _selectedId;
      if (id != null) onPicked(id);
      close();
    }.toJS);

    _buildGrid(overlay, category: '');

    final catSel = overlay.querySelector('#fp-category') as HTMLSelectElement?;
    catSel?.addEventListener('change', (Event _) {
      _buildGrid(overlay, category: catSel.value);
    }.toJS);

    final searchInput = overlay.querySelector('#fp-search') as HTMLInputElement?;
    searchInput?.addEventListener('input', (Event _) {
      _buildGrid(overlay, category: catSel?.value ?? '');
    }.toJS);

    final showIdsCb = overlay.querySelector('#fp-show-ids') as HTMLInputElement?;
    showIdsCb?.addEventListener('change', (Event _) {
      _grid?.showIds = showIdsCb.checked;
    }.toJS);
  }

  void close() {
    if (_overlay == null) return;
    _removeEscListener(_escFn!);
    _escFn = null;
    _grid?.dispose();
    _grid = null;
    _overlay!.remove();
    _overlay = null;
  }

  String _buildShellHtml() {
    final cats = PlayerDataCache.faceCategories.keys.toList()..sort();
    final catOpts =
        cats.map((c) => '<option value="${_esc(c)}">${_esc(c)}</option>').join();
    return '''
<div class="dialog face-picker-dialog">
  <div class="dialog-header">
    <span>Face Picker</span>
    <span class="material-symbols-outlined dialog-close">close</span>
  </div>
  <div class="face-picker-controls">
    <label style="font-size:12px;color:var(--color-muted)">Category:</label>
    <select id="fp-category"
      style="background:var(--color-chip);border:1px solid var(--color-border);
             border-radius:4px;color:var(--color-text);padding:3px 8px;font-size:12px;">
      <option value="">All</option>
      $catOpts
    </select>
    <input type="text" id="fp-search" placeholder="Search name or ID..."
      style="background:var(--color-chip);border:1px solid var(--color-border);
             border-radius:4px;color:var(--color-text);padding:3px 8px;font-size:12px;
             width:160px;">
    <label style="display:flex;align-items:center;gap:5px;font-size:12px;
                  color:var(--color-muted);cursor:pointer;margin-left:auto">
      <input type="checkbox" id="fp-show-ids"> Show IDs
    </label>
  </div>
  <div class="dialog-body" style="padding:0;overflow:hidden;flex:1;display:flex;flex-direction:column;">
    <div class="face-grid-scroller"></div>
    <div class="face-grid-empty" style="display:none;padding:24px;text-align:center;
      font-size:12px;color:var(--color-muted);">No photos match your search.</div>
  </div>
  <div class="dialog-footer">
    <button class="btn btn-outlined" id="fp-cancel">Cancel</button>
    <button class="btn btn-filled" id="fp-confirm">Select</button>
  </div>
</div>''';
  }

  void _buildGrid(HTMLElement overlay, {required String category}) {
    _grid?.dispose();
    _grid = null;

    final scroller =
        overlay.querySelector('.face-grid-scroller') as HTMLElement?;
    if (scroller == null) return;

    List<int> ids;
    if (category.isEmpty) {
      ids = PlayerDataCache.allPhotoIds;
    } else {
      ids = List.of(PlayerDataCache.photoIdsForCategory(category))..sort();
    }

    final query = (overlay.querySelector('#fp-search') as HTMLInputElement?)
            ?.value.trim().toLowerCase() ?? '';
    if (query.isNotEmpty) {
      ids = ids.where((id) => _matchesSearch(id, query)).toList();
    }

    final emptyMsg = overlay.querySelector('.face-grid-empty') as HTMLElement?;
    if (ids.isEmpty) {
      scroller.style.display = 'none';
      emptyMsg?.style.display = 'block';
      return;
    }
    scroller.style.display = '';
    emptyMsg?.style.display = 'none';

    _grid = _VirtualFaceGrid(
      scroller: scroller,
      ids: ids,
      selectedId: _selectedId,
      onSelect: (id) { _selectedId = id; },
    );
    _grid!.mount();

    if (_selectedId != null) {
      Future.delayed(Duration.zero, () => _grid?.scrollToSelected());
    }
  }
}

/// True if [id]'s numeric string or its mapped photo name contains [query]
/// (already lowercased). Used for the Face Picker's search-by-name-or-ID box.
bool _matchesSearch(int id, String query) {
  final idStr = id.toString();
  final paddedId = idStr.padLeft(4, '0'); // matches the displayed "ID 0155" form
  if (idStr.contains(query) || paddedId.contains(query)) return true;
  final name = photoIdToDisplayName(idStr);
  return name.toLowerCase().contains(query);
}

// ─── Virtual Face Grid ────────────────────────────────────────────────────────

class _VirtualFaceGrid {
  static const int _cols = 10;
  static const int _cellH = 68;
  static const int _gap = 4;
  static const int _rowH = _cellH + _gap; // 72px
  static const int _bufferRows = 3;

  final HTMLElement scroller;
  final List<int> ids;
  String? selectedId;
  final void Function(String id) onSelect;

  final _urlCache = <int, String>{};

  late final HTMLElement _container;
  late final HTMLElement _window;
  late final JSFunction _scrollHandler;

  int _firstRendered = 0;
  int _lastRendered = -1;
  bool _showIds = false;

  _VirtualFaceGrid({
    required this.scroller,
    required this.ids,
    required this.selectedId,
    required this.onSelect,
  });

  int get _totalRows => (ids.length / _cols).ceil();
  int get _totalHeight => _totalRows * _rowH - _gap + 16;

  set showIds(bool v) {
    _showIds = v;
    final labels = _window.querySelectorAll('.face-id-label');
    for (var i = 0; i < labels.length; i++) {
      (labels.item(i) as HTMLElement?)?.style.display = v ? 'block' : 'none';
    }
  }

  void mount() {
    _container = document.createElement('div') as HTMLElement;
    _container.style.position = 'relative';
    _container.style.height = '${_totalHeight}px';

    _window = document.createElement('div') as HTMLElement;
    _window.className = 'face-grid-window';
    _window.style.position = 'absolute';
    _window.style.left = '8px';
    _window.style.right = '8px';
    _window.style.top = '8px';

    _container.append(_window);
    scroller.append(_container);

    _window.addEventListener('click', (Event e) {
      final thumb =
          (e.target as HTMLElement?)?.closest('.face-thumb') as HTMLElement?;
      if (thumb == null) return;
      final id = thumb.dataset['id'];
      if (id.isEmpty) return;
      final old = _window.querySelectorAll('.face-thumb.selected');
      for (var i = 0; i < old.length; i++) {
        (old.item(i) as HTMLElement?)?.classList.remove('selected');
      }
      thumb.classList.add('selected');
      selectedId = id;
      onSelect(id);
    }.toJS);

    _scrollHandler = (Event _) { _onScroll(); }.toJS;
    scroller.addEventListener('scroll', _scrollHandler);

    _render();
  }

  void dispose() {
    scroller.removeEventListener('scroll', _scrollHandler);
    for (final url in _urlCache.values) {
      URL.revokeObjectURL(url);
    }
    _urlCache.clear();
    _container.remove();
  }

  void scrollToSelected() {
    final id = selectedId;
    if (id == null) return;
    final idx = ids.indexOf(int.tryParse(id) ?? -1);
    if (idx < 0) return;
    final row = idx ~/ _cols;
    final rowTop = 8 + row * _rowH;
    final desired = rowTop - scroller.clientHeight / 2 + _cellH / 2;
    scroller.scrollTop = desired.clamp(0, _totalHeight.toDouble());
  }

  void _onScroll() => _render();

  void _render() {
    final scrollTop = scroller.scrollTop;
    final viewH = scroller.clientHeight;
    final totalRows = _totalRows;

    if (totalRows == 0) {
      _window.innerHTML = ''.toJS;
      return;
    }

    final gridTop = (scrollTop - 8).clamp(0, double.infinity);
    final firstRow =
        ((gridTop / _rowH).floor() - _bufferRows).clamp(0, totalRows - 1).toInt();
    final lastRow =
        (((gridTop + viewH) / _rowH).ceil() + _bufferRows - 1)
            .clamp(0, totalRows - 1).toInt();

    if (firstRow == _firstRendered && lastRow == _lastRendered) return;
    _firstRendered = firstRow;
    _lastRendered = lastRow;

    _window.style.top = '${8 + firstRow * _rowH}px';

    final firstIdx = firstRow * _cols;
    final lastIdx = ((lastRow + 1) * _cols).clamp(0, ids.length);

    final buf = StringBuffer();
    for (var i = firstIdx; i < lastIdx; i++) {
      final id = ids[i];
      final isSel = id.toString() == selectedId;
      final label = id.toString().padLeft(4, '0');
      final url = _blobUrlFor(id);
      final name = photoIdToDisplayName(id.toString());
      final tooltip = name.isEmpty ? 'ID $label' : '$name (ID $label)';
      buf.write(
        '<div class="face-thumb${isSel ? ' selected' : ''}" '
        'data-id="$id" title="${_esc(tooltip)}">'
        '<img src="$url" alt="$label" loading="eager">'
        '<div class="face-id-label" style="display:${_showIds ? 'block' : 'none'}">$label</div>'
        '</div>',
      );
    }
    _window.innerHTML = buf.toString().toJS;
  }

  String _blobUrlFor(int id) {
    final cached = _urlCache[id];
    if (cached != null) return cached;
    final bytes = PlayerDataCache.getPhoto(id);
    if (bytes == null) return '';
    final url = _makeBlobUrl(bytes);
    _urlCache[id] = url;
    return url;
  }

  static String _makeBlobUrl(Uint8List bytes) {
    final blob = Blob([bytes.toJS].toJS);
    return URL.createObjectURL(blob);
  }
}

// ─── Coach Body Picker Dialog ─────────────────────────────────────────────────

/// Shows a simple grid of the 34 coach body images.
/// [currentName] is the currently selected body name, e.g. `[Dennis Erickson]`.
/// [onPicked] receives the selected name (with brackets).
class CoachBodyPickerDialog {
  HTMLElement? _overlay;
  String? _selectedName;
  JSFunction? _escFn;

  void open({
    required String? currentName,
    required void Function(String name) onPicked,
  }) {
    if (_overlay != null) return;
    PlayerDataCache.ensureLoaded();
    _selectedName = currentName;

    final overlay = document.createElement('div') as HTMLElement;
    overlay.className = 'dialog-overlay';
    overlay.innerHTML = _buildShellHtml().toJS;
    document.body!.append(overlay);
    _overlay = overlay;

    _escFn = _addEscListener(close);
    _wireOverlayClose(overlay, close);

    final cancelBtn = overlay.querySelector('#cb-cancel') as HTMLElement?;
    cancelBtn?.addEventListener('click', (Event e) { e.stopPropagation(); close(); }.toJS);
    overlay.querySelector('.dialog-close')
        ?.addEventListener('click', (Event _) { cancelBtn?.click(); }.toJS);

    overlay.querySelector('#cb-confirm')?.addEventListener('click', (Event e) {
      e.stopPropagation();
      final name = _selectedName;
      if (name != null) onPicked(name);
      close();
    }.toJS);

    _buildGrid(overlay);
  }

  void close() {
    if (_overlay == null) return;
    _removeEscListener(_escFn!);
    _escFn = null;
    _overlay!.remove();
    _overlay = null;
  }

  String _buildShellHtml() => '''
<div class="dialog face-picker-dialog">
  <div class="dialog-header">
    <span>Coach Body Picker</span>
    <span class="material-symbols-outlined dialog-close">close</span>
  </div>
  <div class="dialog-body" style="padding:8px;overflow-y:auto;flex:1;">
    <div id="cb-grid" style="display:grid;grid-template-columns:repeat(3,1fr);gap:8px;"></div>
  </div>
  <div class="dialog-footer">
    <button class="btn btn-outlined" id="cb-cancel">Cancel</button>
    <button class="btn btn-filled" id="cb-confirm">Select</button>
  </div>
</div>''';

  void _buildGrid(HTMLElement overlay) {
    final grid = overlay.querySelector('#cb-grid') as HTMLElement?;
    if (grid == null) return;

    final names = PlayerDataCache.allCoachBodyNames;
    final buf = StringBuffer();
    for (final name in names) {
      final isSel = name == _selectedName;
      final bytes = PlayerDataCache.getCoachBody(name);
      final url = bytes != null
          ? URL.createObjectURL(Blob([bytes.toJS].toJS))
          : '';
      final label = name; // keep brackets: [Dennis Erickson]
      buf.write(
        '<div class="face-thumb${isSel ? ' selected' : ''}" data-name="${_esc(name)}" '
        'title="${_esc(label)}" style="height:160px;display:flex;flex-direction:column;'
        'align-items:center;gap:4px;padding:4px;">'
        '${url.isNotEmpty ? '<img src="$url" alt="${_esc(label)}" style="flex:1;object-fit:contain;width:100%;min-height:0;">' : '<div style="flex:1;"></div>'}'
        '<div style="font-size:10px;text-align:center;line-height:1.2;'
        'color:var(--color-text-secondary);overflow:hidden;max-width:100%;">${_esc(label)}</div>'
        '</div>',
      );
    }
    grid.innerHTML = buf.toString().toJS;

    grid.addEventListener('click', (Event e) {
      final thumb = (e.target as HTMLElement?)?.closest('.face-thumb') as HTMLElement?;
      if (thumb == null) return;
      final name = thumb.dataset['name'];
      if (name.isEmpty) return;
      final old = grid.querySelectorAll('.face-thumb.selected');
      for (var i = 0; i < old.length; i++) {
        (old.item(i) as HTMLElement?)?.classList.remove('selected');
      }
      thumb.classList.add('selected');
      _selectedName = name;
    }.toJS);
  }
}

// ─── PBP Name Picker Dialog ───────────────────────────────────────────────────

/// Searchable list picker for PBP announcer name IDs.
///
/// Uses [DataMap.PBPMap] (key = display name, value = numeric ID string).
/// The user sees display names; the selected value written to the save is
/// the numeric ID.
class PbpPickerDialog {
  HTMLElement? _overlay;
  String? _selectedId;
  JSFunction? _escFn;

  // Sorted snapshot of DataMap.PBPMap entries built once per open().
  late final List<MapEntry<String, String>> _entries;

  void open({
    required String? currentId,
    required void Function(String id) onPicked,
  }) {
    if (_overlay != null) return; // already open
    _selectedId = currentId;

    // Build sorted entry list: key = display name, value = numeric ID
    _entries = DataMap.PBPMap.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final overlay = document.createElement('div') as HTMLElement;
    overlay.className = 'dialog-overlay';
    overlay.innerHTML = _buildHtml().toJS;
    document.body!.append(overlay);
    _overlay = overlay;

    _escFn = _addEscListener(close);
    _wireOverlayClose(overlay, close);

    final cancelBtn = overlay.querySelector('#pbp-cancel') as HTMLElement?;
    cancelBtn?.addEventListener('click', (Event e) { e.stopPropagation(); close(); }.toJS);
    // X button delegates to cancel so both behave identically
    overlay.querySelector('.dialog-close')
        ?.addEventListener('click', (Event _) { cancelBtn?.click(); }.toJS);

    overlay.querySelector('#pbp-confirm')?.addEventListener('click', (Event e) {
      e.stopPropagation();
      final id = _selectedId;
      if (id != null) onPicked(id);
      close();
    }.toJS);

    final search = overlay.querySelector('#pbp-search') as HTMLInputElement?;
    search?.addEventListener('input', (Event _) {
      _populate(overlay, filter: search.value.toLowerCase());
    }.toJS);

    overlay.querySelector('#pbp-list')?.addEventListener('click', (Event e) {
      final row = (e.target as HTMLElement?)?.closest('.pbp-row') as HTMLElement?;
      if (row == null) return;
      final id = row.dataset['id'];
      if (id.isEmpty) return;
      final old = overlay.querySelectorAll('.pbp-row.selected');
      for (var i = 0; i < old.length; i++) {
        (old.item(i) as HTMLElement?)?.classList.remove('selected');
      }
      row.classList.add('selected');
      _selectedId = id;
    }.toJS);

    _populate(overlay, filter: '');

    if (currentId != null) {
      Future.delayed(Duration.zero, () {
        overlay.querySelector('.pbp-row.selected')?.scrollIntoView(true.toJS);
      });
    }
  }

  void close() {
    if (_overlay == null) return;
    _removeEscListener(_escFn!);
    _escFn = null;
    _overlay!.remove();
    _overlay = null;
  }

  String _buildHtml() => '''
<div class="dialog pbp-picker-dialog">
  <div class="dialog-header">
    <span>PBP Name Picker</span>
    <span class="material-symbols-outlined dialog-close">close</span>
  </div>
  <div class="face-picker-controls">
    <input id="pbp-search" type="text" placeholder="Search name or ID\u2026"
      style="flex:1;background:var(--color-chip);border:1px solid var(--color-border);
             border-radius:4px;color:var(--color-text);padding:4px 8px;font-size:12px;">
  </div>
  <div class="dialog-body" style="padding:0;overflow-y:auto;flex:1;">
    <div id="pbp-list"></div>
  </div>
  <div class="dialog-footer">
    <button class="btn btn-outlined" id="pbp-cancel">Cancel</button>
    <button class="btn btn-filled" id="pbp-confirm">Select</button>
  </div>
</div>''';

  void _populate(HTMLElement overlay, {required String filter}) {
    final list = overlay.querySelector('#pbp-list') as HTMLElement?;
    if (list == null) return;

    final shown = filter.isEmpty
        ? _entries
        : _entries
            .where((e) =>
                e.key.toLowerCase().contains(filter) ||
                e.value.contains(filter))
            .toList();

    final buf = StringBuffer();
    for (final entry in shown) {
      final sel = entry.value == _selectedId ? ' selected' : '';
      buf.write('<div class="pbp-row$sel" data-id="${_esc(entry.value)}">'
          '<span class="pbp-name">${_esc(entry.key)}</span>'
          '<span class="pbp-id">id:\u00a0${_esc(entry.value)}</span>'
          '</div>');
    }
    list.innerHTML = buf.toString().toJS;
  }
}
