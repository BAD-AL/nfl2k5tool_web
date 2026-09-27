import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart';

import '../app_state.dart';
import '../data/player_data_cache.dart';
import '../data/text_parser.dart';
import '../widgets/dialogs.dart';

// ─── XSS escape ───────────────────────────────────────────────────────────────

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

// ─── Tab definitions ──────────────────────────────────────────────────────────

class _TabDef {
  final String label;
  final List<({String key, String label, int min, int max})> fields;
  const _TabDef({required this.label, required this.fields});
}

const _kStringFields = ['FirstName', 'LastName', 'Info1', 'Info2', 'Info3'];

const _kTabs = [
  _TabDef(label: 'Text Info',   fields: []),  // handled separately
  _TabDef(label: 'Stats',       fields: [
    (key: 'Wins',              label: 'Wins',              min: 0, max: 255),
    (key: 'Losses',            label: 'Losses',            min: 0, max: 255),
    (key: 'Ties',              label: 'Ties',              min: 0, max: 255),
    (key: 'SeasonsWithTeam',   label: 'Seasons w/ Team',   min: 0, max: 255),
    (key: 'totalSeasons',      label: 'Total Seasons',     min: 0, max: 255),
    (key: 'WinningSeasons',    label: 'Winning Seasons',   min: 0, max: 255),
    (key: 'SuperBowls',        label: 'Super Bowls',       min: 0, max: 255),
    (key: 'SuperBowlWins',     label: 'SB Wins',           min: 0, max: 255),
    (key: 'SuperBowlLosses',   label: 'SB Losses',         min: 0, max: 255),
    (key: 'PlayoffWins',       label: 'Playoff Wins',      min: 0, max: 255),
    (key: 'PlayoffLosses',     label: 'Playoff Losses',    min: 0, max: 255),
  ]),
  _TabDef(label: 'Abilities',   fields: [
    (key: 'Overall',           label: 'Overall',           min: 0, max: 127),
    (key: 'OvrallOffense',     label: 'Offense',           min: 0, max: 127),
    (key: 'RushFor',           label: 'Run Offense',       min: 0, max: 127),
    (key: 'PassFor',           label: 'Pass Offense',      min: 0, max: 127),
    (key: 'OverallDefense',    label: 'Defense',           min: 0, max: 127),
    (key: 'PassRush',          label: 'Pass Rush',         min: 0, max: 127),
    (key: 'PassCoverage',      label: 'Pass Coverage',     min: 0, max: 127),
    (key: 'QB',                label: 'QB',                min: 0, max: 127),
    (key: 'RB',                label: 'RB',                min: 0, max: 127),
    (key: 'TE',                label: 'TE',                min: 0, max: 127),
    (key: 'WR',                label: 'WR',                min: 0, max: 127),
    (key: 'OL',                label: 'OL',                min: 0, max: 127),
    (key: 'DL',                label: 'DL',                min: 0, max: 127),
    (key: 'LB',                label: 'LB',                min: 0, max: 127),
    (key: 'SpecialTeams',      label: 'Special Teams',     min: 0, max: 127),
    (key: 'Professionalism',   label: 'Professionalism',   min: 0, max: 127),
    (key: 'Preparation',       label: 'Preparation',       min: 0, max: 127),
    (key: 'Conditioning',      label: 'Conditioning',      min: 0, max: 127),
    (key: 'Motivation',        label: 'Motivation',        min: 0, max: 127),
    (key: 'Leadership',        label: 'Leadership',        min: 0, max: 127),
    (key: 'Discipline',        label: 'Discipline',        min: 0, max: 127),
    (key: 'Respect',           label: 'Respect',           min: 0, max: 127),
  ]),
  _TabDef(label: 'Play Calling', fields: [
    (key: 'PlaycallingRun',    label: 'Run %',             min: 0, max: 100),
    (key: 'ShotgunRun',        label: 'Shotgun Run %',     min: 0, max: 100),
    (key: 'IFormRun',          label: 'I-Form Run %',      min: 0, max: 100),
    (key: 'SplitbackRun',      label: 'Splitback Run %',   min: 0, max: 100),
    (key: 'EmptyRun',          label: 'Empty Run %',       min: 0, max: 100),
    (key: 'ShotgunPass',       label: 'Shotgun Pass %',    min: 0, max: 100),
    (key: 'SplitbackPass',     label: 'Splitback Pass %',  min: 0, max: 100),
    (key: 'IFormPass',         label: 'I-Form Pass %',     min: 0, max: 100),
    (key: 'LoneBackPass',      label: 'Lone Back Pass %',  min: 0, max: 100),
    (key: 'EmptyPass',         label: 'Empty Pass %',      min: 0, max: 100),
  ]),
];

// ─── CoachEditorScreen ────────────────────────────────────────────────────────

class CoachEditorScreen {
  final AppState _appState;
  final HTMLElement _container;

  List<String>   _headers  = [];
  List<CoachRow> _coaches  = [];
  int _lastTextHash = 0;

  int _selectedIdx = -1;   // index into _coaches
  int _activeTab   = 0;

  String? _photoObjectUrl;
  String? _bodyObjectUrl;

  CoachEditorScreen(AppState appState)
      : _appState = appState,
        _container = document.getElementById('screen-coaches') as HTMLElement;

  // ─── Public entry point ───────────────────────────────────────────────────

  void render() {
    if (!_appState.hasFile) {
      _container.innerHTML = '''
<div class="placeholder-screen">
  <span class="material-symbols-outlined">headset_mic</span>
  <h2>Coach Editor</h2>
  <p>Open a gamesave file to edit coaches.</p>
</div>'''.toJS;
      _resetState();
      return;
    }

    final hash = _appState.textContent.hashCode;
    if (hash != _lastTextHash) {
      _lastTextHash = hash;
      final parsed = parseCoachLines(_appState.textContent);
      _headers = parsed.headers;
      _coaches = parsed.coaches;
      _selectedIdx = -1;
    }

    if (_coaches.isEmpty) {
      _container.innerHTML = '''
<div class="placeholder-screen">
  <span class="material-symbols-outlined">headset_mic</span>
  <h2>Coach Editor</h2>
  <p>No coach data found in the current text.</p>
  <p style="font-size:13px;color:var(--color-text-secondary);">
    Enable <b>Show Coaches</b> in <b>Options</b> to include coach data.
  </p>
</div>'''.toJS;
      return;
    }

    _renderFull();
  }

  // ─── Full DOM build ───────────────────────────────────────────────────────

  void _renderFull() {
    _revokeUrls();
    _container.innerHTML = '''
<div class="player-editor">
  <div class="section-header">
    <span class="material-symbols-outlined section-icon">headset_mic</span>
    <span class="section-title">Coach Editor</span>
    <span class="section-subtitle">${_coaches.length} coaches</span>
  </div>
  <div class="player-editor-body">
    <div class="player-list-panel" id="ces-list-panel">
      ${_buildListHtml()}
    </div>
    <div class="player-attr-panel" id="ces-detail-panel">
      ${_buildDetailHtml()}
    </div>
  </div>
</div>'''.toJS;

    _attachListeners();
  }

  // ─── List panel ───────────────────────────────────────────────────────────

  String _buildListHtml() {
    final buf = StringBuffer();
    buf.write('<div class="player-list">');
    for (int i = 0; i < _coaches.length; i++) {
      final c = _coaches[i];
      final sel = i == _selectedIdx ? ' selected' : '';
      buf.write('''
<div class="player-row$sel" data-idx="$i">
  <div class="player-row-info">
    <div class="player-row-name">${_esc(c.fullName.isEmpty ? '(unnamed)' : c.fullName)}</div>
    <div class="player-row-meta">${_esc(c.team)}</div>
  </div>
</div>''');
    }
    buf.write('</div>');
    return buf.toString();
  }

  // ─── Detail panel ─────────────────────────────────────────────────────────

  String _buildDetailHtml() {
    if (_selectedIdx < 0) {
      return '''
<div class="player-attr-placeholder">
  <span class="material-symbols-outlined">person_search</span>
  <h3>Select a coach</h3>
  <p>Choose a coach from the list to edit their attributes.</p>
</div>''';
    }

    return '''
${_buildCoachHeaderHtml()}
${_buildStringBudgetHtml()}
${_buildTabBarHtml()}
<div class="attr-grid" id="ces-attr-grid">
  ${_buildTabContentHtml()}
</div>''';
  }

  String _buildCoachHeaderHtml() {
    _revokeUrls();
    final c = _coaches[_selectedIdx];
    final photoId = int.tryParse(c.photo);
    if (photoId != null) {
      final bytes = PlayerDataCache.getPhoto(photoId);
      if (bytes != null) {
        _photoObjectUrl = _makeBlobUrl(bytes);
      }
    }
    final bodyBytes = PlayerDataCache.getCoachBody(c.body);
    if (bodyBytes != null) {
      _bodyObjectUrl = _makeBlobUrl(bodyBytes);
    }

    final photoHtml = _photoObjectUrl != null
        ? '<img src="${_esc(_photoObjectUrl!)}" alt="photo">'
        : '<div class="photo-placeholder"><span class="material-symbols-outlined">person</span></div>';
    final bodyHtml = _bodyObjectUrl != null
        ? '<img src="${_esc(_bodyObjectUrl!)}" alt="body" style="width:100%;height:100%;object-fit:contain;">'
        : '<div class="photo-placeholder"><span class="material-symbols-outlined">accessibility</span></div>';
    final coach     = _coaches[_selectedIdx];
    final bodyLabel = _esc(coach.body.isEmpty ? '' : coach.body);
    final fullName  = _esc(coach.fullName.isEmpty ? '(unnamed)' : coach.fullName);
    final teamLabel = _esc(coach.team.isEmpty ? '' : '${coach.team} Coach');

    return '''
<div class="player-attr-header" style="gap:8px;">
  <div class="player-photo-box" id="ces-photo-box" title="Click to change photo" style="cursor:pointer;">
    $photoHtml
  </div>
  <div style="display:flex;flex-direction:column;align-items:center;gap:4px;flex-shrink:0;">
    <div id="ces-body-box" title="Click to change coach body"
      style="width:64px;height:80px;border-radius:6px;overflow:hidden;
             border:2px solid var(--color-border);cursor:pointer;">
      $bodyHtml
    </div>
    <div style="font-size:9px;text-align:center;color:var(--color-muted);
                max-width:68px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;"
         title="$bodyLabel">$bodyLabel</div>
  </div>
  <div class="player-attr-header-info">
    <div id="ces-team-label"
         style="font-size:13px;font-weight:700;color:var(--color-accent);margin-bottom:4px;">
      $teamLabel
    </div>
    <div class="player-attr-name" id="ces-coach-name">$fullName</div>
  </div>
</div>''';
  }

  String _buildStringBudgetHtml() {
    final used   = coachStringCharsUsed(_coaches, _headers);
    final budget = kCoachStringCharBudget;
    return '<div id="ces-budget" style="margin:6px 12px 0;font-size:11px;">'
        '${_buildBudgetInnerHtml(used, budget)}</div>';
  }

  String _buildBudgetInnerHtml(int used, int budget) {
    final pct   = (used / budget * 100).round().clamp(0, 100);
    final over  = used > budget;
    final warn  = pct >= 90;
    final color = over ? 'var(--color-error,#e05)' : warn ? 'var(--color-gold)' : 'var(--color-accent)';
    final textColor = over ? 'var(--color-error,#e05)' : 'var(--color-muted)';
    final prefix = over ? '&#x26A0; ' : '';
    const tipLine1 = 'The coaches name and info fields are all part of the coach string section.'
        ' It can take up no more than 2648 characters.';
    const tipLine2 = 'You may need to delete some longer strings to make it all fit.';
    return '''
<span style="color:$textColor">
  ${prefix}Coach Strings: Total possible characters = $budget; $used Characters currently used
  <span title="$tipLine1&#10;$tipLine2"
        style="cursor:help;color:var(--color-muted);margin-left:4px;">&#x24D8;</span>
</span>
<div style="margin-top:3px;height:4px;background:var(--color-border);border-radius:2px;">
  <div style="height:100%;width:$pct%;background:$color;border-radius:2px;transition:width .2s;"></div>
</div>''';
  }

  String _buildTabBarHtml() {
    final tabs = _kTabs.asMap().entries.map((e) {
      final active = e.key == _activeTab ? ' active' : '';
      return '<span class="attr-tab$active" data-tab="${e.key}">${_esc(e.value.label)}</span>';
    }).join();
    return '<div class="attr-tab-bar">$tabs</div>';
  }

  String _buildTabContentHtml() {
    if (_selectedIdx < 0) return '';
    final c = _coaches[_selectedIdx];

    if (_activeTab == 0) return _buildStringsTabHtml(c);

    final tab = _kTabs[_activeTab];
    final visible = tab.fields.where((f) => _headers.contains(f.key)).toList();
    if (visible.isEmpty) {
      return '<div style="padding:24px;color:var(--color-muted);font-size:13px;">'
          'These fields are not in the current CoachKEY. '
          'Enable <b>Show Coaches</b> in Options to regenerate with the full key.</div>';
    }

    final buf = StringBuffer();
    for (final f in visible) {
      final v = (int.tryParse(c.fields[f.key] ?? '0') ?? 0).clamp(f.min, f.max);
      final pct = f.max > f.min ? ((v - f.min) / (f.max - f.min) * 100).round() : 0;
      buf.write('''
<div class="attr-card numeric" data-key="${_esc(f.key)}" data-min="${f.min}" data-max="${f.max}">
  <div class="attr-card-label">${_esc(f.label)}</div>
  <div class="numeric-display">
    <span class="numeric-side numeric-left ces-dec" data-key="${_esc(f.key)}">&#x2039;</span>
    <span class="numeric-value">${_esc(v.toString())}</span>
    <span class="numeric-side numeric-right ces-inc" data-key="${_esc(f.key)}">&#x203a;</span>
  </div>
  <div class="numeric-bar-track">
    <div class="numeric-bar-fill" style="width:$pct%"></div>
  </div>
</div>''');
    }
    return buf.toString();
  }

  static const _kStringLabels = {
    'FirstName': 'First Name',
    'LastName':  'Last Name',
    'Info1':     'Info 1',
    'Info2':     'Info 2',
    'Info3':     'Info 3',
  };

  // Info fields are capped at 50 characters each by the game engine.
  static const _kInfoMaxLength = 50;
  static const _kInfoKeys = {'Info1', 'Info2', 'Info3'};

  String _buildStringsTabHtml(CoachRow c) {
    final buf = StringBuffer();

    for (final key in _kStringFields) {
      if (!_headers.contains(key)) continue;
      final val      = c.fields[key] ?? '';
      final label    = _kStringLabels[key] ?? key;
      final maxAttr  = _kInfoKeys.contains(key) ? ' maxlength="$_kInfoMaxLength"' : '';
      final limitHint = _kInfoKeys.contains(key)
          ? ' <span class="ces-char-hint" style="float:right;font-weight:400;">${val.length}/$_kInfoMaxLength</span>'
          : '';
      buf.write('''
<div class="attr-card text-field" data-key="${_esc(key)}" style="width:100%;">
  <div class="attr-card-label">${_esc(label)}$limitHint</div>
  <input type="text" class="pes-text-input ces-string-input" data-key="${_esc(key)}"
    value="${_esc(val)}"$maxAttr style="width:100%;box-sizing:border-box;">
</div>''');
    }

    if (buf.isEmpty) {
      buf.write('<div style="padding:24px;color:var(--color-muted);font-size:13px;">'
          'String fields not present in current CoachKEY.</div>');
    }
    return buf.toString();
  }

  // ─── Event wiring ─────────────────────────────────────────────────────────

  void _attachListeners() {
    // Coach list row selection
    final listPanel = _container.querySelector('#ces-list-panel') as HTMLElement?;
    listPanel?.addEventListener('click', (Event e) {
      final row = (e.target as HTMLElement?)?.closest('.player-row') as HTMLElement?;
      if (row == null) return;
      final idx = int.tryParse(row.dataset['idx']) ?? -1;
      if (idx >= 0 && idx < _coaches.length) _selectCoach(idx);
    }.toJS);

    _attachDetailListeners();
  }

  void _attachDetailListeners() {
    final detail = _container.querySelector('#ces-detail-panel') as HTMLElement?;
    if (detail == null) return;

    // Photo box click
    detail.querySelector('#ces-photo-box')?.addEventListener('click', (Event _) {
      if (_selectedIdx < 0) return;
      final curId = int.tryParse(_coaches[_selectedIdx].photo);
      FacePickerDialog().open(
        currentId: curId,
        onPicked: (id) { _writeField('Photo', id); _rebuildDetail(); },
      );
    }.toJS);

    // Body box click
    detail.querySelector('#ces-body-box')?.addEventListener('click', (Event _) {
      if (_selectedIdx < 0) return;
      CoachBodyPickerDialog().open(
        currentName: _coaches[_selectedIdx].body,
        onPicked: (name) { _writeField('Body', name); _rebuildDetail(); },
      );
    }.toJS);

    // Tab bar
    detail.querySelector('.attr-tab-bar')?.addEventListener('click', (Event e) {
      final tab = (e.target as HTMLElement?)?.closest('.attr-tab') as HTMLElement?;
      if (tab == null) return;
      final idx = int.tryParse(tab.dataset['tab']) ?? -1;
      if (idx >= 0 && idx < _kTabs.length && idx != _activeTab) {
        _activeTab = idx;
        _rebuildTabBar();
        _rebuildGrid();
      }
    }.toJS);

    _attachGridListeners();
  }

  void _attachGridListeners() {
    final grid = _container.querySelector('#ces-attr-grid') as HTMLElement?;
    if (grid == null) return;

    // Numeric +/- (event delegation)
    grid.addEventListener('click', (Event e) {
      final target = e.target as HTMLElement?;
      if (target == null) return;
      final isInc = target.classList.contains('ces-inc');
      final isDec = target.classList.contains('ces-dec');
      if (!isInc && !isDec) return;

      final key = target.dataset['key'];
      if (key.isEmpty) return;
      final card = target.closest('.attr-card.numeric') as HTMLElement?;
      if (card == null) return;
      final minV = int.tryParse(card.dataset['min']) ?? 0;
      final maxV = int.tryParse(card.dataset['max']) ?? 255;
      final cur  = int.tryParse(
          (card.querySelector('.numeric-value') as HTMLElement?)?.textContent ?? '0') ?? 0;
      final next = (isInc ? cur + 1 : cur - 1).clamp(minV, maxV);
      if (next == cur) return;

      _writeField(key, next.toString());
      _updateNumericCard(grid, key, next, minV, maxV);
      _rebuildBudgetBar();
    }.toJS);

    // String inputs: live name + budget update on input, commit on blur
    grid.addEventListener('input', (Event e) {
      final target = e.target as HTMLElement?;
      if (target == null || !target.classList.contains('ces-string-input')) return;
      final key   = (target as HTMLInputElement).dataset['key'];
      final value = target.value;

      // Update in-memory fields so budget calculation reflects current input values
      if (_selectedIdx >= 0 && _selectedIdx < _coaches.length) {
        _coaches[_selectedIdx].fields[key] = value;
      }

      // Live character counter for Info fields
      if (_kInfoKeys.contains(key)) {
        final card = (grid.querySelector('.attr-card[data-key="${_esc(key)}"]') as HTMLElement?);
        final hint = card?.querySelector('.ces-char-hint') as HTMLElement?;
        if (hint != null) hint.textContent = '${value.length}/$_kInfoMaxLength';
      }

      // Live name update for FirstName/LastName
      if (key == 'FirstName' || key == 'LastName') {
        final fn = (grid.querySelector('.ces-string-input[data-key="FirstName"]')
                as HTMLInputElement?)?.value ??
            _coaches[_selectedIdx].firstName;
        final ln = (grid.querySelector('.ces-string-input[data-key="LastName"]')
                as HTMLInputElement?)?.value ??
            _coaches[_selectedIdx].lastName;
        final newName = '$fn $ln'.trim();
        final nameEl = _container.querySelector('#ces-coach-name') as HTMLElement?;
        if (nameEl != null) nameEl.textContent = newName.isEmpty ? '(unnamed)' : newName;
        _updateListItemName(_selectedIdx, newName);
      }

      // Live budget bar update
      _rebuildBudgetBar();
    }.toJS);

    // 'focusout' (unlike 'blur') bubbles, so this delegates correctly from
    // the grid -- see the identical note in player_editor_screen.dart. A
    // plain 'blur' listener here would never fire for a descendant input's
    // blur at all, silently discarding every typed edit that isn't also
    // reflected by some other live-update path.
    grid.addEventListener('focusout', (Event e) {
      final target = e.target as HTMLElement?;
      if (target == null || !target.classList.contains('ces-string-input')) return;
      final key = (target as HTMLInputElement).dataset['key'];
      _writeField(key, target.value);
      _rebuildBudgetBar();
    }.toJS);
  }

  // ─── Selection ────────────────────────────────────────────────────────────

  void _selectCoach(int idx) {
    // Update list highlight
    final rows = _container.querySelectorAll('.player-row');
    for (var i = 0; i < rows.length; i++) {
      (rows.item(i) as HTMLElement?)?.classList.remove('selected');
    }
    _container.querySelector('.player-row[data-idx="$idx"]')?.classList.add('selected');

    _selectedIdx = idx;
    _rebuildDetail();
  }

  // ─── Partial rebuilds ─────────────────────────────────────────────────────

  void _rebuildDetail() {
    final detail = _container.querySelector('#ces-detail-panel') as HTMLElement?;
    if (detail == null) return;
    detail.innerHTML = _buildDetailHtml().toJS;
    _attachDetailListeners();
  }

  void _rebuildTabBar() {
    final tabs = _container.querySelectorAll('.attr-tab');
    for (var i = 0; i < tabs.length; i++) {
      final tab = tabs.item(i) as HTMLElement?;
      if (tab == null) continue;
      final idx = int.tryParse(tab.dataset['tab']) ?? -1;
      if (idx == _activeTab) { tab.classList.add('active'); }
      else                   { tab.classList.remove('active'); }
    }
  }

  void _rebuildGrid() {
    final detail = _container.querySelector('#ces-detail-panel') as HTMLElement?;
    if (detail == null) return;
    final oldGrid = detail.querySelector('#ces-attr-grid') as HTMLElement?;
    if (oldGrid == null) return;
    // Replace the element entirely so previous event listeners are discarded.
    final newGrid = document.createElement('div') as HTMLElement;
    newGrid.id        = 'ces-attr-grid';
    newGrid.className = 'attr-grid';
    newGrid.innerHTML = _buildTabContentHtml().toJS;
    oldGrid.parentNode?.insertBefore(newGrid, oldGrid);
    oldGrid.remove();
    _attachGridListeners();
  }

  void _rebuildBudgetBar() {
    final used = coachStringCharsUsed(_coaches, _headers);
    final detail = _container.querySelector('#ces-detail-panel') as HTMLElement?;
    if (detail == null) return;
    final budgetDiv = detail.querySelector('#ces-budget') as HTMLElement?;
    if (budgetDiv != null) {
      budgetDiv.innerHTML = _buildBudgetInnerHtml(used, kCoachStringCharBudget).toJS;
    }
  }

  void _updateNumericCard(
      HTMLElement grid, String key, int newVal, int minV, int maxV) {
    final card = grid.querySelector('.attr-card.numeric[data-key="${_esc(key)}"]') as HTMLElement?;
    if (card == null) return;
    final valueEl = card.querySelector('.numeric-value') as HTMLElement?;
    if (valueEl != null) valueEl.textContent = newVal.toString();
    final pct = maxV > minV ? ((newVal - minV) / (maxV - minV) * 100).round() : 0;
    final barEl = card.querySelector('.numeric-bar-fill') as HTMLElement?;
    if (barEl != null) barEl.style.width = '$pct%';
  }

  void _updateListItemName(int idx, String newName) {
    final row = _container.querySelector('.player-row[data-idx="$idx"]') as HTMLElement?;
    if (row == null) return;
    final nameEl = row.querySelector('.player-row-name') as HTMLElement?;
    if (nameEl != null) nameEl.textContent = newName.isEmpty ? '(unnamed)' : newName;
  }

  // ─── Field write ──────────────────────────────────────────────────────────

  void _writeField(String key, String value) {
    if (_selectedIdx < 0 || _selectedIdx >= _coaches.length) return;
    final coach = _coaches[_selectedIdx];
    _appState.textContent = setFieldInLine(
        _appState.textContent,
        coach.lineIndex,
        key,
        value,
        _headers,
        detectDelimiter(_appState.textContent));
    _lastTextHash = _appState.textContent.hashCode;
    // Re-parse to keep cache in sync with updated text
    final parsed = parseCoachLines(_appState.textContent);
    _headers = parsed.headers;
    _coaches = parsed.coaches;
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  void _resetState() {
    _headers     = [];
    _coaches     = [];
    _lastTextHash = 0;
    _selectedIdx = -1;
    _activeTab   = 0;
    _revokeUrls();
  }

  void _revokeUrls() {
    if (_photoObjectUrl != null) {
      URL.revokeObjectURL(_photoObjectUrl!);
      _photoObjectUrl = null;
    }
    if (_bodyObjectUrl != null) {
      URL.revokeObjectURL(_bodyObjectUrl!);
      _bodyObjectUrl = null;
    }
  }

  static String _makeBlobUrl(Uint8List bytes) {
    final blob = Blob([bytes.toJS].toJS);
    return URL.createObjectURL(blob);
  }
}
