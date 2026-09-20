import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart';

import '../app_state.dart';
import '../data/attr_groups.dart';
import '../data/equipment_appearance.dart';
import '../data/player_data_cache.dart';
import '../data/player_mappings.dart';
import '../data/text_parser.dart';
import '../widgets/dialogs.dart';

// ─── Position filter descriptors ──────────────────────────────────────────────

const _kPosFilters = [
  ('All', ''),
  ('QB',  'QB'),
  ('RB',  'RB'),
  ('WR',  'WR'),
  ('TE',  'TE'),
  ('OL',  'OL'),
  ('DL',  'DL'),
  ('LB',  'LB'),
  ('DB',  'DB'),
  ('K/P', 'KP'),
];

bool _matchesPosFilter(String pos, String filter) {
  if (filter.isEmpty) return true;
  switch (filter) {
    case 'QB': return pos == 'QB';
    case 'RB': return pos == 'RB' || pos == 'FB';
    case 'WR': return pos == 'WR';
    case 'TE': return pos == 'TE';
    case 'OL': return pos == 'C' || pos == 'G' || pos == 'T';
    case 'DL': return pos == 'DT' || pos == 'DE';
    case 'LB': return pos == 'OLB' || pos == 'ILB';
    case 'DB': return pos == 'CB' || pos == 'FS' || pos == 'SS';
    case 'KP': return pos == 'K' || pos == 'P';
    default:   return false;
  }
}

// ─── XSS escape helper ────────────────────────────────────────────────────────

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

// ─── PlayerEditorScreen ───────────────────────────────────────────────────────

class PlayerEditorScreen {
  final AppState _appState;
  final HTMLElement _container;

  // Cached parse results (rebuilt when textContent changes)
  List<TeamBlock> _teamBlocks = [];
  List<String> _columns = [];
  List<String> _colleges = [];
  int _lastTextHash = 0;

  // Screen-local UI state
  String _selectedTeam = '';   // '' = All Teams
  String _searchQuery  = '';
  String _posFilter    = '';   // '' = All
  bool   _panelCollapsed = false;
  int    _activeTab    = 0;

  // Selected player
  int  _selectedLineIndex = -1;
  Map<String, String> _selectedFields = {};

  // Object URL for currently displayed photo
  String? _photoObjectUrl;

  PlayerEditorScreen(AppState appState)
      : _appState = appState,
        _container =
            document.getElementById('screen-players') as HTMLElement;

  // ─── Public render entry point ───────────────────────────────────────────

  void render() {
    if (!_appState.hasFile) {
      _container.innerHTML = '''
<div class="placeholder-screen">
  <span class="material-symbols-outlined">person</span>
  <h2>Player Editor</h2>
  <p>Open a gamesave file to edit players.</p>
</div>'''.toJS;
      _resetState();
      return;
    }

    // Rebuild parse cache when textContent changes
    final hash = _appState.textContent.hashCode;
    if (hash != _lastTextHash) {
      _lastTextHash = hash;
      _columns    = parseActiveColumns(_appState.textContent);
      _teamBlocks = parseTeamBlocksForDisplay(_appState.textContent);
      _colleges   = parseCollegeNames(_appState.textContent);
      // Clear stale selection — line indices are no longer meaningful
      _selectedLineIndex = -1;
      _selectedFields    = {};
    }

    _renderFull();
  }

  // ─── Full rebuild ────────────────────────────────────────────────────────

  void _renderFull() {
    _revokePhotoUrl();

    final subtitle = _appState.hasFile
        ? '${_appState.teamCount} teams · ${_appState.playerCount} players'
        : 'No file loaded';

    _container.innerHTML = '''
<div class="player-editor">
  <div class="section-header">
    <span class="material-symbols-outlined section-icon">person</span>
    <span class="section-title">Player Editor</span>
    <span class="section-subtitle">${_esc(subtitle)}</span>
  </div>
  <div class="player-editor-body">
    <div class="player-list-panel${_panelCollapsed ? ' collapsed' : ''}" id="pes-list-panel">
      ${_buildListPanelInner()}
    </div>
    <div class="player-attr-panel" id="pes-attr-panel">
      ${_buildAttrPanelHtml()}
    </div>
  </div>
</div>'''.toJS;

    _attachListPanelListeners();
    _attachAttrPanelListeners();
  }

  // ─── List panel HTML ─────────────────────────────────────────────────────

  String _buildListPanelInner() {
    final teamNames = _teamBlocks.map((b) => b.name).toList();
    final teamOptions = teamNames
        .map((n) =>
            '<option value="${_esc(n)}"${n == _selectedTeam ? ' selected' : ''}>${_esc(n)}</option>')
        .join();

    final chipHtml = _kPosFilters.map((pf) {
      final label = pf.$1;
      final key   = pf.$2;
      final active = key == _posFilter ? ' active' : '';
      return '<span class="pos-chip$active" data-pos="${_esc(key)}">${_esc(label)}</span>';
    }).join();

    // Visible player rows
    final rows = _buildPlayerRowsHtml();

    final collapseIcon = _panelCollapsed ? 'chevron_right' : 'chevron_left';

    return '''
<div class="player-list-controls">
  <select id="pes-team-select">
    <option value="">All Teams</option>
    $teamOptions
  </select>
</div>
<div class="player-search">
  <span class="material-symbols-outlined">search</span>
  <input id="pes-search" type="text" placeholder="Search name or position…"
    value="${_esc(_searchQuery)}">
</div>
<div class="position-chips" id="pes-pos-chips">$chipHtml</div>
<div class="player-list" id="pes-player-list">$rows</div>
<div class="panel-collapse-toggle" id="pes-collapse-toggle">
  ${_panelCollapsed ? '' : '<span style="font-size:11px">Collapse</span>'}
  <span class="material-symbols-outlined" style="font-size:16px">$collapseIcon</span>
</div>''';
  }

  String _buildPlayerRowsHtml() {
    final query = _searchQuery.toLowerCase();
    final buf = StringBuffer();

    Iterable<TeamBlock> visibleBlocks = _teamBlocks;
    if (_selectedTeam.isNotEmpty) {
      visibleBlocks = visibleBlocks.where((b) => b.name == _selectedTeam);
    }

    for (final block in visibleBlocks) {
      final visiblePlayers = block.players.where((p) {
        if (!_matchesPosFilter(p.position, _posFilter)) return false;
        if (query.isNotEmpty &&
            !p.fullName.toLowerCase().contains(query) &&
            !p.position.toLowerCase().contains(query)) { return false; }
        return true;
      });

      if (visiblePlayers.isEmpty) continue;

      // Team header row
      buf.write('''
<div style="padding:4px 10px 2px;font-size:10px;font-weight:700;color:var(--color-gold);
  letter-spacing:0.6px;text-transform:uppercase;background:var(--color-surface);
  border-bottom:1px solid var(--color-border);">${_esc(block.name)}</div>''');

      for (final p in visiblePlayers) {
        final sel = p.lineIndex == _selectedLineIndex ? ' selected' : '';
        buf.write('''
<div class="player-row$sel" data-line="${p.lineIndex}">
  <span class="pos-badge">${_esc(p.position)}</span>
  <div class="player-row-info">
    <div class="player-row-name">${_esc(p.fullName)}</div>
    <div class="player-row-meta">#${_esc(p.jerseyNumber)} · ${_esc(p.yearsPro)}yr</div>
  </div>
  <div class="player-row-actions">
    <button class="material-symbols-outlined pes-move-up" data-line="${p.lineIndex}"
      title="Move up" style="background:none;border:none;cursor:pointer">arrow_upward</button>
    <button class="material-symbols-outlined pes-move-down" data-line="${p.lineIndex}"
      title="Move down" style="background:none;border:none;cursor:pointer">arrow_downward</button>
  </div>
</div>''');
      }
    }

    if (buf.isEmpty) {
      buf.write(
          '<div style="padding:16px;text-align:center;font-size:12px;color:var(--color-muted)">No players match</div>');
    }

    return buf.toString();
  }

  // ─── Attr panel HTML ─────────────────────────────────────────────────────

  String _buildAttrPanelHtml() {
    if (_selectedLineIndex < 0) {
      return '''
<div class="player-attr-placeholder">
  <span class="material-symbols-outlined">person_search</span>
  <h3>Select a player</h3>
  <p>Choose a player from the list to edit their attributes.</p>
</div>''';
    }

    return '''
${_buildAttrHeaderHtml()}
${_buildAttrTabBarHtml()}
<div class="attr-grid" id="pes-attr-grid">
  ${_buildAttrGridHtml()}
</div>''';
  }

  String _buildAttrHeaderHtml() {
    final f = _selectedFields;
    final name = _esc('${f['fname'] ?? ''} ${f['lname'] ?? ''}'.trim());
    final pos        = _esc(f['Position']    ?? '');
    final jersey     = _esc(f['JerseyNumber'] ?? '');
    final team       = _esc(_teamNameForLine(_selectedLineIndex));
    final yearsPro   = _esc(f['YearsPro']    ?? '');
    final hand       = _esc(f['Hand']        ?? '');
    final height     = _esc(f['Height']      ?? '');
    final weight     = _esc(f['Weight']      ?? '');
    final skinRaw    = f['Skin'] ?? '';
    final skin       = _esc(skinRaw);

    final photoHtml = _buildPhotoHtml();

    return '''
<div class="player-attr-header">
  <div class="player-photo-box" id="pes-photo-box" title="Click to change photo">
    $photoHtml
  </div>
  <div class="player-attr-header-info">
    <div class="player-attr-name">$name</div>
    <div class="player-meta-chips">
      ${pos.isNotEmpty    ? '<span class="meta-chip">$pos</span>'          : ''}
      ${jersey.isNotEmpty ? '<span class="meta-chip">#$jersey</span>'      : ''}
      ${team.isNotEmpty   ? '<span class="meta-chip">$team</span>'         : ''}
      ${yearsPro.isNotEmpty ? '<span class="meta-chip">${yearsPro}yr</span>' : ''}
      ${hand.isNotEmpty   ? '<span class="meta-chip">$hand</span>'         : ''}
      ${height.isNotEmpty ? '<span class="meta-chip">$height</span>'       : ''}
      ${weight.isNotEmpty ? '<span class="meta-chip">${weight}lb</span>'   : ''}
      ${skin.isNotEmpty ? '<span class="meta-chip skin-chip" '
          'style="background:${skinColorHex(skinRaw)};'
          'color:${skinTextColor(skinRaw)};'
          'border-color:${skinColorHex(skinRaw)};">$skin</span>' : ''}
    </div>
  </div>
</div>''';
  }

  String _buildPhotoHtml() {
    _revokePhotoUrl();
    final photoStr = _selectedFields['Photo'] ?? '';
    final photoId  = int.tryParse(photoStr);
    if (photoId != null) {
      final bytes = PlayerDataCache.getPhoto(photoId);
      if (bytes != null) {
        _photoObjectUrl = _blobUrl(bytes);
        return '<img src="${_esc(_photoObjectUrl!)}" alt="photo">';
      }
    }
    return '<div class="photo-placeholder"><span class="material-symbols-outlined">person</span></div>';
  }

  String _buildAttrTabBarHtml() {
    final tabs = kAttrGroups.asMap().entries.map((e) {
      final active = e.key == _activeTab ? ' active' : '';
      return '<span class="attr-tab$active" data-tab="${e.key}">${_esc(e.value.tabLabel)}</span>';
    }).join();
    return '<div class="attr-tab-bar">$tabs</div>';
  }

  String _buildAttrGridHtml() {
    final group = kAttrGroups[_activeTab];
    final buf = StringBuffer();

    for (final attr in group.attrs) {
      // Skip if column not in active schema
      if (!_columns.contains(attr.key)) continue;

      final value = _selectedFields[attr.key] ?? '';

      switch (attr.type) {
        case AttrType.numeric:
          buf.write(_buildNumericCard(attr, value));
        case AttrType.slider:
          buf.write(_buildSliderCard(attr, value));
        case AttrType.dropdown:
          final List<String> opts;
          if (attr.key == 'Height') {
            opts = kHeightOptions;
          } else if (attr.key == 'College') {
            opts = _appState.tool?.GetColleges() ?? _colleges;
          } else {
            opts = attr.options;
          }
          buf.write(_buildDropdownCard(attr, value, opts));
        case AttrType.text:
          buf.write(_buildTextCard(attr, value));
        case AttrType.datePicker:
          buf.write(_buildDateCard(attr, value));
        case AttrType.autocomplete:
          buf.write(_buildAutocompleteCard(attr, value));
        case AttrType.mappedId:
          buf.write(_buildMappedIdCard(attr, value));
        case AttrType.imagePopover:
          buf.write(_buildImagePopoverCard(attr, value));
      }
    }

    if (buf.isEmpty) {
      buf.write(
          '<div style="color:var(--color-muted);font-size:13px">No fields available for this tab.</div>');
    }

    return buf.toString();
  }

  // ─── Individual attr card builders ───────────────────────────────────────

  String _buildNumericCard(AttrDef attr, String value) {
    final v = (int.tryParse(value) ?? 0).clamp(attr.min, attr.max);
    final pct = attr.max > attr.min
        ? ((v - attr.min) / (attr.max - attr.min) * 100).round()
        : 0;
    return '''
<div class="attr-card numeric" data-key="${_esc(attr.key)}">
  <div class="attr-card-label">${_esc(attr.label)}</div>
  <div class="numeric-display">
    <span class="numeric-side numeric-left">&#x2039;</span>
    <span class="numeric-value">${_esc(v.toString())}</span>
    <span class="numeric-side numeric-right">&#x203a;</span>
  </div>
  <div class="numeric-bar-track" data-key="${_esc(attr.key)}">
    <div class="numeric-bar-fill" style="width:$pct%"></div>
  </div>
</div>''';
  }

  String _buildSliderCard(AttrDef attr, String value) {
    final v = (int.tryParse(value) ?? attr.min).clamp(attr.min, attr.max);
    return '''
<div class="attr-card slider-field" data-key="${_esc(attr.key)}">
  <div class="attr-card-label">${_esc(attr.label)}</div>
  <div class="slider-row">
    <button class="slider-btn pes-slider-dec" data-key="${_esc(attr.key)}"
      data-min="${attr.min}" data-max="${attr.max}">−</button>
    <input type="range" min="${attr.min}" max="${attr.max}" value="$v"
      data-key="${_esc(attr.key)}" class="pes-slider-input">
    <button class="slider-btn pes-slider-inc" data-key="${_esc(attr.key)}"
      data-min="${attr.min}" data-max="${attr.max}">+</button>
    <span class="slider-value">${_esc(v.toString())}</span>
  </div>
</div>''';
  }

  String _buildDropdownCard(AttrDef attr, String value, List<String> options) {
    final optHtml = options.map((o) {
      final sel = o == value ? ' selected' : '';
      return '<option value="${_esc(o)}"$sel>${_esc(o)}</option>';
    }).join();
    return '''
<div class="attr-card dropdown-field" data-key="${_esc(attr.key)}">
  <div class="attr-card-label">${_esc(attr.label)}</div>
  <select class="pes-dropdown" data-key="${_esc(attr.key)}">$optHtml</select>
</div>''';
  }

  String _buildTextCard(AttrDef attr, String value) {
    return '''
<div class="attr-card text-field" data-key="${_esc(attr.key)}">
  <div class="attr-card-label">${_esc(attr.label)}</div>
  <input type="text" class="pes-text-input" data-key="${_esc(attr.key)}"
    value="${_esc(value)}">
</div>''';
  }

  String _buildDateCard(AttrDef attr, String value) {
    // Value format: M/D/YYYY or M/D/YY  → display as-is, convert to ISO for input
    final display = value.isEmpty ? '—' : value;
    final iso = _dobToIso(value);
    return '''
<div class="attr-card date-field" data-key="${_esc(attr.key)}">
  <div class="attr-card-label">${_esc(attr.label)}</div>
  <div class="date-display pes-date-display" data-key="${_esc(attr.key)}">
    <span>${_esc(display)}</span>
    <span class="material-symbols-outlined">calendar_today</span>
  </div>
  <input type="date" class="pes-date-input" data-key="${_esc(attr.key)}"
    value="${_esc(iso)}">
</div>''';
  }

  String _buildAutocompleteCard(AttrDef attr, String value) {
    return '''
<div class="attr-card autocomplete-field" data-key="${_esc(attr.key)}">
  <div class="attr-card-label">${_esc(attr.label)}</div>
  <input type="text" class="pes-autocomplete-input" data-key="${_esc(attr.key)}"
    autocomplete="off" value="${_esc(value)}">
</div>''';
  }

  String _buildMappedIdCard(AttrDef attr, String value) {
    final displayName = attr.key == 'Photo'
        ? photoIdToDisplayName(value)
        : pbpIdToDisplayName(value);
    final numDisplay = value.isEmpty ? '' : 'id: $value';
    return '''
<div class="attr-card mapped-id-field" data-key="${_esc(attr.key)}">
  <div class="attr-card-label">${_esc(attr.label)}</div>
  <div class="mapped-id-row">
    <span class="mapped-id-name">${_esc(displayName.isEmpty ? '(none)' : displayName)}</span>
    <span class="mapped-id-num">${_esc(numDisplay)}</span>
    <span class="material-symbols-outlined mapped-id-search pes-mapped-id-search"
      data-key="${_esc(attr.key)}" title="Pick…">search</span>
  </div>
</div>''';
  }

  /// Thumbnail-or-swatch + label trigger that opens an anchored popover
  /// listing every option with its own image/swatch (see the design
  /// discussion this implements: fewer full-screen dialogs, but still able
  /// to browse equipment visually instead of guessing from text labels).
  /// The popover's rows are built lazily each time it's opened (see the
  /// 'click' handler in _attachAttrGridListeners) — not here — since eagerly
  /// base64-encoding every option's image for every field on every render
  /// (up to 27 for FaceMask, across 11 fields) would be real, avoidable cost
  /// paid on every player selection whether or not the popover is ever
  /// opened. Rebuilding per-open (rather than caching after the first) is
  /// still cheap — PlayerDataCache caches decompressed image bytes, so a
  /// reopen only re-runs base64 encoding — and keeps the 'selected'
  /// highlight from ever going stale.
  String _buildImagePopoverCard(AttrDef attr, String value) {
    final thumb = _equipmentThumbHtml(attr.key, value);
    final label = value.isEmpty ? '(none)' : value;
    return '''
<div class="attr-card image-popover-field" data-key="${_esc(attr.key)}">
  <div class="attr-card-label">${_esc(attr.label)}</div>
  <button type="button" class="img-popover-trigger" data-key="${_esc(attr.key)}">
    $thumb
    <span class="img-popover-label">${_esc(label)}</span>
    <span class="material-symbols-outlined img-popover-caret">expand_more</span>
  </button>
  <div class="img-popover-panel" data-key="${_esc(attr.key)}" style="display:none"></div>
</div>''';
  }

  /// A single thumbnail: a color swatch for Skin (never image-backed — see
  /// equipment_appearance.dart), an equipment-image <img> when one resolves,
  /// or an empty placeholder swatch when the field has no image for this
  /// value (e.g. the known-incomplete Elbow variants).
  String _equipmentThumbHtml(String key, String value) {
    if (key == 'Skin') {
      return '<div class="img-popover-thumb swatch" '
          'style="background:${skinColorHex(value)}"></div>';
    }
    final filename = equipmentImageFilename(key, value);
    final bytes = filename == null ? null : PlayerDataCache.getEquipmentImage(filename);
    if (bytes == null) {
      return '<div class="img-popover-thumb placeholder"></div>';
    }
    final b64 = base64Encode(bytes);
    return '<img class="img-popover-thumb" src="data:image/jpeg;base64,$b64" alt="">';
  }

  /// Every option for [attr] as a clickable row (thumbnail/swatch + label),
  /// rebuilt fresh each time the popover opens — see _buildImagePopoverCard's
  /// doc comment for why.
  String _buildImagePopoverRows(AttrDef attr, String currentValue) {
    final buf = StringBuffer();
    for (final opt in attr.options) {
      final sel = opt == currentValue ? ' selected' : '';
      buf.write('''
<div class="img-popover-row$sel" data-key="${_esc(attr.key)}" data-value="${_esc(opt)}">
  ${_equipmentThumbHtml(attr.key, opt)}
  <span>${_esc(opt)}</span>
</div>''');
    }
    return buf.toString();
  }

  // ─── Event wiring ────────────────────────────────────────────────────────

  void _attachListPanelListeners() {
    final panel = _container.querySelector('#pes-list-panel') as HTMLElement?;
    if (panel == null) return;

    // Team dropdown
    panel.querySelector('#pes-team-select')?.addEventListener(
        'change',
        (Event e) {
          _selectedTeam      = (e.target as HTMLSelectElement).value;
          _selectedLineIndex = -1;
          _selectedFields    = {};
          _rebuildPlayerListOnly();
          _rebuildAttrPanel();
        }.toJS);

    // Search input
    panel.querySelector('#pes-search')?.addEventListener(
        'input',
        (Event e) {
          _searchQuery =
              (e.target as HTMLInputElement).value;
          _rebuildPlayerListOnly();
        }.toJS);

    // Position chips (event delegation)
    panel.querySelector('#pes-pos-chips')?.addEventListener(
        'click',
        (Event e) {
          final chip =
              (e.target as HTMLElement?)?.closest('.pos-chip') as HTMLElement?;
          if (chip == null) return;
          _posFilter = chip.dataset['pos'];
          final chips = panel.querySelectorAll('.pos-chip');
          for (var i = 0; i < chips.length; i++) {
            final c = chips.item(i) as HTMLElement;
            c.classList.toggle('active', c.dataset['pos'] == _posFilter);
          }
          _rebuildPlayerListOnly();
        }.toJS);

    // Player row selection + reorder (event delegation on player list)
    panel.querySelector('#pes-player-list')?.addEventListener(
        'click',
        (Event e) {
          final target = e.target as HTMLElement?;

          // Move up/down buttons
          if (target != null && target.classList.contains('pes-move-up')) {
            _movePlayer(int.tryParse(target.dataset['line']) ?? -1, -1);
            return;
          }
          if (target != null && target.classList.contains('pes-move-down')) {
            _movePlayer(int.tryParse(target.dataset['line']) ?? -1, 1);
            return;
          }

          // Row click — select player
          final row =
              target?.closest('.player-row') as HTMLElement?;
          if (row == null) return;
          final lineIdx =
              int.tryParse(row.dataset['line']) ?? -1;
          if (lineIdx >= 0) _selectPlayer(lineIdx);
        }.toJS);

    // Collapse toggle
    panel.querySelector('#pes-collapse-toggle')?.addEventListener(
        'click',
        (Event _) {
          _panelCollapsed = !_panelCollapsed;
          final listPanel =
              _container.querySelector('#pes-list-panel') as HTMLElement?;
          if (_panelCollapsed) {
            listPanel?.classList.add('collapsed');
          } else {
            listPanel?.classList.remove('collapsed');
          }
          // Rebuild inner content to swap icon/label
          final inner = _buildListPanelInner();
          if (listPanel != null) {
            listPanel.innerHTML = inner.toJS;
            _attachListPanelListeners();
          }
        }.toJS);
  }

  void _attachAttrPanelListeners() {
    final panel = _container.querySelector('#pes-attr-panel') as HTMLElement?;
    if (panel == null || _selectedLineIndex < 0) return;

    // Photo box click — delegate to _openMappedIdPicker so the UI updates too
    panel.querySelector('#pes-photo-box')?.addEventListener(
        'click',
        (Event _) { _openMappedIdPicker('Photo'); }.toJS);

    // Tab bar clicks
    panel.querySelector('.attr-tab-bar')?.addEventListener(
        'click',
        (Event e) {
          final tab =
              (e.target as HTMLElement?)?.closest('.attr-tab') as HTMLElement?;
          if (tab == null) return;
          final idx = int.tryParse(tab.dataset['tab']) ?? 0;
          if (idx == _activeTab) return;
          _activeTab = idx;
          _rebuildTabBar();
          _rebuildAttrGrid();
        }.toJS);

    // Numeric cards (event delegation on attr-grid)
    _attachAttrGridListeners(panel);
  }

  void _attachAttrGridListeners(HTMLElement panel) {
    final grid = panel.querySelector('#pes-attr-grid') as HTMLElement?;
    if (grid == null) return;

    // Numeric card: left/right half click
    grid.addEventListener(
        'click',
        (Event e) {
          final target = e.target as HTMLElement?;

          // Image-popover row click — select this option
          final imgRow = target?.closest('.img-popover-row') as HTMLElement?;
          if (imgRow != null) {
            final key = imgRow.dataset['key'];
            final val = imgRow.dataset['value'];
            _writeField(key, val);
            _updateImagePopoverTrigger(grid, key, val);
            (imgRow.closest('.img-popover-panel') as HTMLElement?)
                ?.style.display = 'none';
            return;
          }

          // Image-popover trigger click — toggle its panel, (re)building the
          // rows fresh each open so the 'selected' highlight never goes
          // stale (cheap: PlayerDataCache caches decompressed image bytes,
          // so a reopen only re-runs base64 encoding, not decompression).
          final imgTrigger = target?.closest('.img-popover-trigger') as HTMLElement?;
          if (imgTrigger != null) {
            final key = imgTrigger.dataset['key'];
            final panel = (imgTrigger.closest('.attr-card') as HTMLElement?)
                ?.querySelector('.img-popover-panel') as HTMLElement?;
            if (panel == null) return;
            final opening = panel.style.display == 'none';
            _closeAllImagePopovers(grid);
            if (opening) {
              final attr = _findAttrDef(key);
              if (attr != null) {
                panel.innerHTML =
                    _buildImagePopoverRows(attr, _selectedFields[key] ?? '').toJS;
              }
              panel.style.display = 'block';
            }
            return;
          }

          // Mapped-id search
          if (target != null && target.classList.contains('pes-mapped-id-search')) {
            final key = target.dataset['key'];
            _openMappedIdPicker(key);
            return;
          }

          // Date display click
          if (target?.closest('.pes-date-display') != null) {
            final display =
                target?.closest('.pes-date-display') as HTMLElement?;
            final key = display?.dataset['key'] ?? '';
            final dateInput = grid.querySelector(
                    '[data-key="${_esc(key)}"].pes-date-input')
                as HTMLInputElement?;
            dateInput?.showPicker();
            return;
          }

          // Numeric card click — only respond to clicks inside .numeric-display
          if (target?.closest('.numeric-display') == null) return;
          final card =
              target?.closest('.attr-card.numeric') as HTMLElement?;
          if (card == null) return;
          final key = card.dataset['key'];
          final attr = _findAttrDef(key);
          if (attr == null) return;
          final cur =
              (int.tryParse(_selectedFields[key] ?? '') ?? 0)
                  .clamp(attr.min, attr.max);

          // Left half of card = decrement, right half = increment
          final rect = card.getBoundingClientRect();
          final clickX = (e as MouseEvent).clientX;
          final newVal =
              (clickX < rect.left + rect.width / 2 ? cur - 1 : cur + 1)
                  .clamp(attr.min, attr.max);
          _writeField(key, newVal.toString());
          _updateNumericCardDisplay(grid, key, newVal, attr);
        }.toJS);

    // Numeric bar drag
    grid.addEventListener(
        'mousedown',
        (Event e) {
          final target = e.target as HTMLElement?;
          final track =
              target?.closest('.numeric-bar-track') as HTMLElement?;
          if (track == null) return;
          final key = track.dataset['key'];
          final attr = _findAttrDef(key);
          if (attr == null) return;

          void updateFromEvent(MouseEvent ev) {
            final rect = track.getBoundingClientRect();
            final pct = ((ev.clientX - rect.left) / rect.width)
                .clamp(0.0, 1.0);
            final newVal =
                (attr.min + (pct * (attr.max - attr.min)).round())
                    .clamp(attr.min, attr.max);
            _writeField(key, newVal.toString());
            final card =
                track.closest('.attr-card.numeric') as HTMLElement?;
            if (card != null) {
              _updateNumericCardDisplay(grid, key, newVal, attr);
            }
          }

          updateFromEvent(e as MouseEvent);

          // Store .toJS results so removeEventListener gets the same reference.
          late final JSFunction onMoveJs;
          late final JSFunction onUpJs;
          onMoveJs = (Event ev) { updateFromEvent(ev as MouseEvent); }.toJS;
          onUpJs = (Event _) {
            document.removeEventListener('mousemove', onMoveJs);
            document.removeEventListener('mouseup', onUpJs);
          }.toJS;
          document.addEventListener('mousemove', onMoveJs);
          document.addEventListener('mouseup', onUpJs);
        }.toJS);

    // Keyboard on numeric cards
    grid.addEventListener(
        'keydown',
        (Event e) {
          final ke = e as KeyboardEvent;
          final card =
              (e.target as HTMLElement?)?.closest('.attr-card.numeric')
                  as HTMLElement?;
          if (card == null) return;
          final key = card.dataset['key'];
          final attr = _findAttrDef(key);
          if (attr == null) return;
          final cur =
              (int.tryParse(_selectedFields[key] ?? '') ?? 0)
                  .clamp(attr.min, attr.max);
          int? newVal;
          if (ke.key == 'ArrowUp')   newVal = (cur + 1).clamp(attr.min, attr.max);
          if (ke.key == 'ArrowDown') newVal = (cur - 1).clamp(attr.min, attr.max);
          if (newVal == null) return;
          e.preventDefault();
          _writeField(key, newVal.toString());
          _updateNumericCardDisplay(grid, key, newVal, attr);
        }.toJS);

    // Slider input
    grid.addEventListener(
        'input',
        (Event e) {
          final target = e.target as HTMLElement?;
          if (target == null || !target.classList.contains('pes-slider-input')) return;
          final key = (target as HTMLInputElement).dataset['key'];
          final val = target.value;
          _writeField(key, val);
          // Update slider value display
          final card =
              target.closest('.attr-card.slider-field') as HTMLElement?;
          card?.querySelector('.slider-value')?.let((el) {
            (el as HTMLElement).textContent = val;
          });
        }.toJS);

    // Slider +/- buttons
    grid.addEventListener(
        'click',
        (Event e) {
          final target = e.target as HTMLElement?;
          if (target == null) return;
          final isDec = target.classList.contains('pes-slider-dec');
          final isInc = target.classList.contains('pes-slider-inc');
          if (!isDec && !isInc) return;
          final key  = target.dataset['key'];
          final min  = int.tryParse(target.dataset['min']) ?? 0;
          final max  = int.tryParse(target.dataset['max']) ?? 99;
          final cur  = int.tryParse(_selectedFields[key] ?? '') ?? min;
          final next = (cur + (isInc ? 1 : -1)).clamp(min, max);
          _writeField(key, next.toString());
          final card =
              target.closest('.attr-card.slider-field') as HTMLElement?;
          (card?.querySelector('.pes-slider-input') as HTMLInputElement?)
              ?.value = next.toString();
          card?.querySelector('.slider-value')?.let((el) {
            (el as HTMLElement).textContent = next.toString();
          });
        }.toJS);

    // Dropdown change
    grid.addEventListener(
        'change',
        (Event e) {
          final target = e.target as HTMLElement?;
          if (target != null && target.classList.contains('pes-dropdown')) {
            final sel = target as HTMLSelectElement;
            _writeField(sel.dataset['key'], sel.value);
          }
          if (target != null && target.classList.contains('pes-date-input')) {
            final inp = target as HTMLInputElement;
            final key = inp.dataset['key'];
            final iso = inp.value; // YYYY-MM-DD
            final display = _isoToDob(iso);
            _writeField(key, display);
            // Update display span
            final disp = grid
                .querySelector('.pes-date-display[data-key="${_esc(key)}"]')
                as HTMLElement?;
            disp?.querySelector('span')?.let((el) {
              (el as HTMLElement).textContent = display.isEmpty ? '—' : display;
            });
          }
        }.toJS);

    // Text input blur
    grid.addEventListener(
        'change',
        (Event e) {
          final target = e.target as HTMLElement?;
          if (target != null && target.classList.contains('pes-text-input')) {
            final inp = target as HTMLInputElement;
            _writeField(inp.dataset['key'], inp.value);
          }
        }.toJS);

    // Autocomplete input
    _attachAutocompleteListeners(grid);
  }

  void _attachAutocompleteListeners(HTMLElement grid) {
    grid.addEventListener(
        'input',
        (Event e) {
          final target = e.target as HTMLElement?;
          if (target == null || !target.classList.contains('pes-autocomplete-input')) {
            return;
          }
          final inp = target as HTMLInputElement;
          final query = inp.value.toLowerCase();
          final card =
              inp.closest('.autocomplete-field') as HTMLElement?;
          if (card == null) return;

          // Remove old dropdown
          card.querySelector('.autocomplete-dropdown')?.remove();
          if (query.isEmpty) return;

          final matches = _colleges
              .where((c) => c.toLowerCase().contains(query))
              .take(8)
              .toList();
          if (matches.isEmpty) return;

          final dd = document.createElement('div') as HTMLElement;
          dd.className = 'autocomplete-dropdown';
          dd.innerHTML = matches
              .map((c) =>
                  '<div class="autocomplete-item">${_esc(c)}</div>')
              .join()
              .toJS;
          card.append(dd);

          dd.addEventListener(
              'mousedown',
              (Event e2) {
                final item = (e2.target as HTMLElement?)
                    ?.closest('.autocomplete-item') as HTMLElement?;
                if (item == null) return;
                final val = item.textContent ?? '';
                inp.value = val;
                _writeField(
                    inp.dataset['key'], val);
                dd.remove();
                e2.preventDefault();
              }.toJS);
        }.toJS);

    grid.addEventListener(
        'blur',
        (Event e) {
          final target = e.target as HTMLElement?;
          if (target != null && target.classList.contains('pes-autocomplete-input')) {
            _writeField(
                (target as HTMLInputElement).dataset['key'],
                target.value);
            Future.delayed(
                const Duration(milliseconds: 150),
                () => target
                    .closest('.autocomplete-field')
                    ?.querySelector('.autocomplete-dropdown')
                    ?.remove());
          }
        }.toJS);

    // Click-away close for image popovers. 'focusout' (unlike 'blur') bubbles,
    // so this delegates correctly from the grid. The delay lets a row's
    // 'click' (fired just after the mousedown that triggers this) land and
    // write the value before the panel actually hides.
    grid.addEventListener(
        'focusout',
        (Event e) {
          final target = e.target as HTMLElement?;
          if (target == null || !target.classList.contains('img-popover-trigger')) return;
          final panel = (target.closest('.attr-card') as HTMLElement?)
              ?.querySelector('.img-popover-panel') as HTMLElement?;
          if (panel == null) return;
          Future.delayed(const Duration(milliseconds: 150), () {
            panel.style.display = 'none';
          });
        }.toJS);
  }

  void _closeAllImagePopovers(HTMLElement grid) {
    final panels = grid.querySelectorAll('.img-popover-panel');
    for (var i = 0; i < panels.length; i++) {
      (panels.item(i) as HTMLElement).style.display = 'none';
    }
  }

  void _updateImagePopoverTrigger(HTMLElement grid, String key, String value) {
    final trigger = grid.querySelector('.img-popover-trigger[data-key="${_esc(key)}"]')
        as HTMLElement?;
    if (trigger == null) return;
    final label = value.isEmpty ? '(none)' : value;
    trigger.innerHTML = '''
${_equipmentThumbHtml(key, value)}
<span class="img-popover-label">${_esc(label)}</span>
<span class="material-symbols-outlined img-popover-caret">expand_more</span>
'''
        .toJS;
  }

  // ─── Partial rebuilds ────────────────────────────────────────────────────

  /// Re-renders only the row list — never the search input, team select, or
  /// position chips around it. Those live in the same panel, so a full
  /// panel rebuild (replacing the whole `innerHTML`) would create a brand
  /// new `<input>` node on every keystroke and silently drop focus, forcing
  /// a re-click per character typed into search. The rows list is rebuilt
  /// by innerHTML swap too, but that's safe: row click handling is
  /// delegated on the (unreplaced) `#pes-player-list` container itself, not
  /// bound to individual row elements.
  void _rebuildPlayerListOnly() {
    final list =
        _container.querySelector('#pes-player-list') as HTMLElement?;
    if (list == null) return;
    list.innerHTML = _buildPlayerRowsHtml().toJS;
  }

  void _rebuildTabBar() {
    // Update active class on existing tab elements — no DOM replacement needed
    final tabs = _container.querySelectorAll('.attr-tab');
    for (var i = 0; i < tabs.length; i++) {
      final tab = tabs.item(i) as HTMLElement?;
      if (tab == null) continue;
      final idx = int.tryParse(tab.dataset['tab']) ?? -1;
      if (idx == _activeTab) {
        tab.classList.add('active');
      } else {
        tab.classList.remove('active');
      }
    }
  }

  void _rebuildAttrPanel() {
    final attrPanel =
        _container.querySelector('#pes-attr-panel') as HTMLElement?;
    if (attrPanel == null) return;
    attrPanel.innerHTML = _buildAttrPanelHtml().toJS;
    _attachAttrPanelListeners();
  }

  void _rebuildAttrGrid() {
    final panel =
        _container.querySelector('#pes-attr-panel') as HTMLElement?;
    final grid = panel?.querySelector('#pes-attr-grid') as HTMLElement?;
    if (grid == null) return;
    // Only replace innerHTML — the grid element itself stays, so existing
    // event-delegation listeners (attached once in _attachAttrGridListeners)
    // remain valid.  Do NOT call _attachAttrGridListeners here.
    grid.innerHTML = _buildAttrGridHtml().toJS;
  }

  // ─── Player selection ────────────────────────────────────────────────────

  void _selectPlayer(int lineIndex) {
    // Update highlight in list
    final rows = _container.querySelectorAll('.player-row');
    for (var i = 0; i < rows.length; i++) {
      (rows.item(i) as HTMLElement?)?.classList.remove('selected');
    }
    _container
        .querySelector('.player-row[data-line="$lineIndex"]')
        ?.classList.add('selected');

    _selectedLineIndex = lineIndex;
    _selectedFields    = _fieldsForLine(lineIndex);

    // Rebuild attr panel
    final attrPanel =
        _container.querySelector('#pes-attr-panel') as HTMLElement?;
    if (attrPanel != null) {
      attrPanel.innerHTML = _buildAttrPanelHtml().toJS;
      _attachAttrPanelListeners();
    }
  }

  Map<String, String> _fieldsForLine(int lineIndex) {
    final lines = _appState.textContent.split('\n');
    if (lineIndex < 0 || lineIndex >= lines.length) return {};
    final delim = detectDelimiter(_appState.textContent);
    final vals  = splitCsv(lines[lineIndex], delim);
    final result = <String, String>{};
    for (int i = 0; i < _columns.length && i < vals.length; i++) {
      result[_columns[i]] = vals[i];
    }
    return result;
  }

  // ─── Player reorder ──────────────────────────────────────────────────────

  void _movePlayer(int lineIndex, int direction) {
    if (lineIndex < 0) return;

    // Find the player in the visible list, then find the sibling
    final allPlayers = _teamBlocks
        .expand((b) => b.players)
        .toList();
    final idx = allPlayers.indexWhere((p) => p.lineIndex == lineIndex);
    if (idx < 0) return;

    final siblingIdx = idx + direction;
    if (siblingIdx < 0 || siblingIdx >= allPlayers.length) return;

    final siblingLine = allPlayers[siblingIdx].lineIndex;
    _appState.textContent = swapLines(
        _appState.textContent, lineIndex, siblingLine);

    // Invalidate cache and re-render
    _lastTextHash = 0;
    _appState.refreshCounts();
    _appState.notify();
  }

  // ─── Field write ─────────────────────────────────────────────────────────

  void _writeField(String key, String value) {
    if (_selectedLineIndex < 0) return;
    _selectedFields[key] = value;
    _appState.textContent = setFieldInLine(
        _appState.textContent,
        _selectedLineIndex,
        key,
        value,
        _columns,
        detectDelimiter(_appState.textContent));
    // Update the hash so next render() call doesn't re-parse unnecessarily
    _lastTextHash = _appState.textContent.hashCode;
    _syncPlayerRowDisplay();
  }

  /// Patches the player-list-row displays [_writeField] alone leaves stale
  /// (only rebuilt on a full re-render, which the hash-skip above
  /// deliberately avoids): the position badge, name, and jersey#/years-pro
  /// meta line. Also updates the cached [PlayerRow] so a later read of
  /// [_teamBlocks] — e.g. reordering — doesn't see stale data either.
  /// Cheap enough to run unconditionally on every write, including the many
  /// fired during a numeric-bar drag.
  void _syncPlayerRowDisplay() {
    final name = '${_selectedFields['fname'] ?? ''} ${_selectedFields['lname'] ?? ''}'.trim();
    final position = _selectedFields['Position'] ?? '';
    final jersey = _selectedFields['JerseyNumber'] ?? '';
    final yearsPro = _selectedFields['YearsPro'] ?? '';

    for (final block in _teamBlocks) {
      for (final row in block.players) {
        if (row.lineIndex == _selectedLineIndex) {
          row.fields['fname'] = _selectedFields['fname'] ?? '';
          row.fields['lname'] = _selectedFields['lname'] ?? '';
          row.fields['Position'] = position;
          row.fields['JerseyNumber'] = jersey;
          row.fields['YearsPro'] = yearsPro;
        }
      }
    }

    (_container.querySelector('.player-attr-name') as HTMLElement?)
        ?.textContent = name;

    final rowEl = _container
        .querySelector('.player-row[data-line="$_selectedLineIndex"]') as HTMLElement?;
    (rowEl?.querySelector('.player-row-name') as HTMLElement?)?.textContent = name;
    (rowEl?.querySelector('.pos-badge') as HTMLElement?)?.textContent = position;
    (rowEl?.querySelector('.player-row-meta') as HTMLElement?)?.textContent =
        '#$jersey · ${yearsPro}yr';
  }

  // ─── Mapped ID picker ────────────────────────────────────────────────────

  void _openMappedIdPicker(String key) {
    if (key == 'Photo') {
      final curId = int.tryParse(_selectedFields['Photo'] ?? '');
      FacePickerDialog().open(
        currentId: curId,
        onPicked: (id) {
          _writeField('Photo', id);
          // Update mapped-id card if it is currently visible in the attr grid
          final grid =
              _container.querySelector('#pes-attr-grid') as HTMLElement?;
          final card = grid?.querySelector(
              '.attr-card.mapped-id-field[data-key="Photo"]') as HTMLElement?;
          if (card != null) {
            final name = photoIdToDisplayName(id);
            card.querySelector('.mapped-id-name')?.let((el) {
              (el as HTMLElement).textContent =
                  name.isEmpty ? '(none)' : name;
            });
            card.querySelector('.mapped-id-num')?.let((el) {
              (el as HTMLElement).textContent = 'id: $id';
            });
          }
          // Always update the photo box in the header
          final photoBox =
              _container.querySelector('#pes-photo-box') as HTMLElement?;
          if (photoBox != null) {
            _revokePhotoUrl();
            final bytes = PlayerDataCache.getPhoto(int.tryParse(id) ?? -1);
            if (bytes != null) {
              _photoObjectUrl = _blobUrl(bytes);
              photoBox.innerHTML =
                  '<img src="${_esc(_photoObjectUrl!)}" alt="photo">'.toJS;
            } else {
              photoBox.innerHTML = ''.toJS;
            }
          }
        },
      );
    }
    if (key == 'PBP') {
      final curId = _selectedFields['PBP'];
      PbpPickerDialog().open(
        currentId: curId,
        onPicked: (id) {
          _writeField('PBP', id);
          final grid =
              _container.querySelector('#pes-attr-grid') as HTMLElement?;
          final card = grid?.querySelector(
              '.attr-card.mapped-id-field[data-key="PBP"]') as HTMLElement?;
          if (card != null) {
            final name = pbpIdToDisplayName(id);
            card.querySelector('.mapped-id-name')?.let((el) {
              (el as HTMLElement).textContent =
                  name.isEmpty ? '(none)' : name;
            });
            card.querySelector('.mapped-id-num')?.let((el) {
              (el as HTMLElement).textContent = 'id: $id';
            });
          }
        },
      );
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  void _resetState() {
    _teamBlocks         = [];
    _columns            = [];
    _colleges           = [];
    _lastTextHash       = 0;
    _selectedTeam       = '';
    _searchQuery        = '';
    _posFilter          = '';
    _panelCollapsed     = false;
    _activeTab          = 0;
    _selectedLineIndex  = -1;
    _selectedFields     = {};
    _revokePhotoUrl();
  }

  void _revokePhotoUrl() {
    if (_photoObjectUrl != null) {
      URL.revokeObjectURL(_photoObjectUrl!);
      _photoObjectUrl = null;
    }
  }

  String _teamNameForLine(int lineIndex) {
    for (final block in _teamBlocks) {
      if (block.players.any((p) => p.lineIndex == lineIndex)) {
        return block.name;
      }
    }
    return '';
  }

  AttrDef? _findAttrDef(String key) {
    for (final group in kAttrGroups) {
      for (final attr in group.attrs) {
        if (attr.key == key) return attr;
      }
    }
    return null;
  }

  void _updateNumericCardDisplay(
      HTMLElement grid, String key, int newVal, AttrDef attr) {
    final card =
        grid.querySelector('.attr-card.numeric[data-key="${_esc(key)}"]')
            as HTMLElement?;
    if (card == null) return;
    card.querySelector('.numeric-value')?.let((el) {
      (el as HTMLElement).textContent = newVal.toString();
    });
    final pct = attr.max > attr.min
        ? ((newVal - attr.min) / (attr.max - attr.min) * 100).round()
        : 0;
    card.querySelector('.numeric-bar-fill')?.let((el) {
      (el as HTMLElement).style.width = '$pct%';
    });
  }

  static String _blobUrl(Uint8List bytes) {
    final blob = Blob([bytes.toJS].toJS);
    return URL.createObjectURL(blob);
  }

  /// Converts M/D/YYYY or M/D/YY to ISO YYYY-MM-DD for date inputs.
  static String _dobToIso(String dob) {
    final parts = dob.split('/');
    if (parts.length != 3) return '';
    final m = int.tryParse(parts[0]);
    final d = int.tryParse(parts[1]);
    var y   = int.tryParse(parts[2]);
    if (m == null || d == null || y == null) return '';
    if (y < 100) y += y >= 50 ? 1900 : 2000;
    return '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
  }

  /// Converts ISO YYYY-MM-DD back to M/D/YYYY.
  static String _isoToDob(String iso) {
    final parts = iso.split('-');
    if (parts.length != 3) return '';
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return '';
    return '$m/$d/$y';
  }
}

// ─── Extension helpers ────────────────────────────────────────────────────────

extension _LetExt on Object? {
  T? let<T>(T? Function(Object) fn) {
    final self = this;
    return self == null ? null : fn(self);
  }
}
