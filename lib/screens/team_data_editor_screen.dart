import 'dart:js_interop';
import 'package:web/web.dart';
import 'package:nfl2k5tool_dart/nfl2k5tool_dart.dart' show GamesaveTool, SaveType;

import '../app_state.dart';
import '../data/text_parser.dart';

// ─── Team abbreviation map (full name → 2-3 letter abbrev) ───────────────────

const _kTeamAbbrevs = {
  '49ers':      'SF',  'Bears':     'CHI', 'Bengals':   'CIN', 'Bills':     'BUF',
  'Broncos':    'DEN', 'Browns':    'CLE', 'Buccaneers':'TB',  'Cardinals': 'ARI',
  'Chargers':   'SD',  'Chiefs':    'KC',  'Colts':     'IND', 'Cowboys':   'DAL',
  'Dolphins':   'MIA', 'Eagles':    'PHI', 'Falcons':   'ATL', 'Giants':    'NYG',
  'Jaguars':    'JAX', 'Jets':      'NYJ', 'Lions':     'DET', 'Packers':   'GB',
  'Panthers':   'CAR', 'Patriots':  'NE',  'Raiders':   'OAK', 'Rams':      'STL',
  'Ravens':     'BAL', 'Redskins':  'WAS', 'Saints':    'NO',  'Seahawks':  'SEA',
  'Steelers':   'PIT', 'Texans':    'HOU', 'Titans':    'TEN', 'Vikings':   'MIN',
};

// ─── XSS escape ───────────────────────────────────────────────────────────────

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

// ─── Lookup tables ────────────────────────────────────────────────────────────

const _kStadiums = [
  '[Arizona Stadium]',
  '[Georgia Dome]',
  '[M&T Bank Stadium ]',
  '[Ralph Wilson Stadium]',
  '[B of A Stadium]',
  '[Chicago Field]',
  '[Paul Brown Stadium]',
  '[Texas Stadium]',
  '[INVESCO Field]',
  '[Ford Field]',
  '[Lambeau Field]',
  '[RCA Dome]',
  '[ALLTEL Stadium]',
  '[Arrowhead Stadium]',
  '[Pro Player Stadium]',
  '[H. H. H. Metrodome]',
  '[Gillette Stadium]',
  '[Louisiana Super Dome]',
  '[Giants Stadium]',
  '[Jets Stadium]',
  '[Network Associates]',
  '[Lincoln Financial Field]',
  '[Heinz Field]',
  '[Edward Jones Dome ]',
  '[QUALCOMM Stadium]',
  '[San Francisco Park]',
  '[Qwest Field]',
  '[Tampa Bay Stadium]',
  '[Titans Coliseum]',
  '[Washington Field]',
  '[Cleveland Stadium]',
  '[Aloha Stadium]',
  '[Practice Facility ]',
  '[Visual Concepts Dome]',
  '[Reliant Stadium]',
  '[Future Aloha Stadium]',
  '[Super Bowl 2005]',
  '[Super Bowl 2008]',
  '[Super Bowl 2006]',
  '[Super Bowl 2007]',
  '[Super Bowl Future]',
  '[Ulterior Super Bowl]',
  '[ESPN Stadium]',
  '[Viper Stadium]',
  '[Firecracker Dome]',
  '[Gold Coast Dome]',
  '[Arachnid Park]',
  '[Southwest Dome]',
  '[Mercury Stadium]',
  '[Prehistoric Park]',
  '[Iron Hammer Coliseum]',
  '[Hog Heaven]',
  '[Zoo Dome]',
];

/// Team logo name → numeric logo index mapping.
/// Some custom teams intentionally share the same logo index.
const _kLogos = [
  (name: '49ers',         value:  25),
  (name: 'Bears',         value:   5),
  (name: 'Bengals',       value:   6),
  (name: 'Bills',         value:   3),
  (name: 'Broncos',       value:   8),
  (name: 'Browns',        value:  30),
  (name: 'Buccaneers',    value:  27),
  (name: 'Cardinals',     value:   0),
  (name: 'Chargers',      value:  24),
  (name: 'Chiefs',        value:  13),
  (name: 'Colts',         value:  11),
  (name: 'Cowboys',       value:   7),
  (name: 'Dolphins',      value:  14),
  (name: 'Eagles',        value:  21),
  (name: 'Falcons',       value:   1),
  (name: 'Giants',        value:  18),
  (name: 'Jaguars',       value:  12),
  (name: 'Jets',          value:  19),
  (name: 'Lions',         value:   9),
  (name: 'Packers',       value:  10),
  (name: 'Panthers',      value:   4),
  (name: 'Patriots',      value:  16),
  (name: 'Raiders',       value:  20),
  (name: 'Rams',          value:  23),
  (name: 'Ravens',        value:   2),
  (name: 'Redskins',      value:  29),
  (name: 'Saints',        value:  17),
  (name: 'Seahawks',      value:  26),
  (name: 'Steelers',      value:  22),
  (name: 'Texans',        value:  37),
  (name: 'Titans',        value:  28),
  (name: 'Vikings',       value:  15),
  (name: 'Swamis',        value:  33),
  (name: 'Risky Picks',   value:  46),
  (name: 'Wingadoros',    value:  46),
  (name: 'Hammerheads',   value:  46),
  (name: 'Cheesesteaks',  value:  95),
  (name: 'Locos',         value:  96),
  (name: 'Electra Shock', value:  97),
  (name: 'Funkmasters',   value:  98),
  (name: 'DreamTeam',     value:  99),
  (name: 'FW Alumni',     value:  40),
  (name: 'GP Alumni',     value:  41),
  (name: 'MW Alumni',     value:  42),
  (name: 'NE Alumni',     value:  43),
  (name: 'SE Alumni',     value:  44),
  (name: 'SW Alumni',     value:  45),
  (name: 'AFC',           value:  34),
  (name: 'NFC',           value:  35),
  (name: 'NFL',           value:  31),
];

const _kPlaybooks = [
  'PB_49ers', 'PB_Bears', 'PB_Bengals', 'PB_Bills', 'PB_Broncos', 'PB_Browns',
  'PB_Buccaneers', 'PB_Cardinals', 'PB_Chargers', 'PB_Chiefs', 'PB_Colts',
  'PB_Cowboys', 'PB_Dolphins', 'PB_Eagles', 'PB_Falcons', 'PB_Giants',
  'PB_Jaguars', 'PB_Jets', 'PB_Lions', 'PB_Packers', 'PB_Panthers',
  'PB_Patriots', 'PB_Raiders', 'PB_Rams', 'PB_Ravens', 'PB_Redskins',
  'PB_Saints', 'PB_Seahawks', 'PB_Steelers', 'PB_Texans', 'PB_Titans',
  'PB_Vikings', 'PB_West_Coast', 'PB_General', 'PB_User_A', 'PB_User_B',
];

// ─── TeamDataEditorScreen ─────────────────────────────────────────────────────

class TeamDataEditorScreen {
  final AppState _appState;
  final HTMLElement _container;

  List<String>      _headers = [];
  List<TeamDataRow> _teams   = [];
  int _lastTextHash  = 0;
  int _selectedIdx   = -1;

  /// Each fixed-length field's max character count, captured once when a
  /// team is selected -- not re-derived from `_teams[_selectedIdx]` on
  /// every keystroke, since that would ratchet the limit down if a field
  /// is shrunk then grown back within the same session (the real
  /// engine-side check always measures against the true, still-uncommitted
  /// original binary, so the live UI needs to match that, not the
  /// in-progress text).
  Map<String, int> _maxFieldLen = {};

  TeamDataEditorScreen(AppState appState)
      : _appState = appState,
        _container = document.getElementById('screen-teamData') as HTMLElement;

  // ─── Public entry point ───────────────────────────────────────────────────

  void render() {
    if (!_appState.hasFile) {
      _container.innerHTML = '''
<div class="placeholder-screen">
  <span class="material-symbols-outlined">shield</span>
  <h2>Team Data Editor</h2>
  <p>Open a gamesave file to edit team data.</p>
</div>'''.toJS;
      _resetState();
      return;
    }

    final hash = _appState.textContent.hashCode;
    if (hash != _lastTextHash) {
      _lastTextHash = hash;
      final parsed = parseTeamDataLines(_appState.textContent);
      _headers = parsed.headers;
      _teams   = parsed.teams;
      _selectedIdx = -1;
    }

    if (_teams.isEmpty) {
      _container.innerHTML = '''
<div class="placeholder-screen">
  <span class="material-symbols-outlined">shield</span>
  <h2>Team Data Editor</h2>
  <p>No team data found in the current text.</p>
  <p style="font-size:13px;color:var(--color-text-secondary);">
    Enable <b>Show Team Data</b> in <b>Options</b> to include team data.
  </p>
</div>'''.toJS;
      return;
    }

    _renderFull();
  }

  // ─── Full DOM build ───────────────────────────────────────────────────────

  void _renderFull() {
    final isFranchise = _appState.isFranchise;
    _container.innerHTML = '''
<div class="player-editor">
  <div class="section-header${isFranchise ? ' section-header--pct' : ''}">
    <div class="section-header-row">
      <span class="material-symbols-outlined section-icon">shield</span>
      <span class="section-title">Team Data Editor</span>
      <span class="section-subtitle">${_teams.length} teams</span>
    </div>
    ${isFranchise ? _buildPctHtml() : ''}
  </div>
  <div class="player-editor-body">
    <div class="player-list-panel" id="tde-list-panel">
      ${_buildListHtml()}
    </div>
    <div class="player-attr-panel" id="tde-detail-panel">
      ${_buildDetailHtml()}
    </div>
  </div>
</div>'''.toJS;

    _attachListeners();
  }

  String _buildPctHtml() {
    final tool = _appState.tool;
    if (tool == null) return '';
    final allChecked = GamesaveTool.Teams.every(tool.isTeamPlayerControlled);
    final btnLabel   = allChecked ? 'Uncheck All' : 'Check All';
    final buf = StringBuffer();
    buf.write('<div class="pct-row">'
        '<span class="pct-label">Player Controlled:</span>'
        '<button id="tde-pct-toggle" class="pct-btn">$btnLabel</button>'
        '<div class="pct-checkboxes">');
    for (final team in GamesaveTool.Teams) {
      final abbrev = _kTeamAbbrevs[team] ?? team.substring(0, 3).toUpperCase();
      final checked = tool.isTeamPlayerControlled(team) ? ' checked' : '';
      buf.write('<label class="pct-cb" title="${_esc(team)}">'
          '<input type="checkbox" class="pct-check" data-team="${_esc(team)}"$checked>'
          '<span>${_esc(abbrev)}</span></label>');
    }
    buf.write('</div></div>');
    return buf.toString();
  }

  // ─── List panel ───────────────────────────────────────────────────────────

  String _buildListHtml() {
    final buf = StringBuffer();
    buf.write('<div class="player-list">');
    for (int i = 0; i < _teams.length; i++) {
      final t = _teams[i];
      final sel = i == _selectedIdx ? ' selected' : '';
      buf.write('''
<div class="player-row$sel" data-idx="$i">
  <div class="player-row-info">
    <div class="player-row-name">${_esc(t.nickname.isEmpty ? t.team : t.nickname)}</div>
    <div class="player-row-meta">${_esc(t.abbrev)} · ${_esc(t.city)}</div>
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
  <span class="material-symbols-outlined">shield</span>
  <h3>Select a team</h3>
  <p>Choose a team from the list to edit its data.</p>
</div>''';
    }

    final t       = _teams[_selectedIdx];
    final tool    = _appState.tool;

    // Build team-specific jersey options
    final teamIdx = GamesaveTool.Teams.indexOf(t.team);
    final jerseys = <String>[];
    if (tool != null && teamIdx >= 0) {
      for (int j = 0; ; j++) {
        final name = tool.GetJerseyName(teamIdx, j);
        if (name == null) break;
        jerseys.add(name);
      }
    }
    final curJersey = int.tryParse(t.defaultJersey) ?? 0;
    final jerseyOpts = jerseys.asMap().entries.map((e) {
      final sel = e.key == curJersey ? ' selected' : '';
      return '<option value="${e.key}"$sel>${_esc(e.value)} (${e.key})</option>';
    }).join();

    // Stadium dropdown
    final stadOpts = _kStadiums.map((s) {
      final sel = s == t.stadium ? ' selected' : '';
      return '<option value="${_esc(s)}"$sel>${_esc(s)}</option>';
    }).join();

    // Playbook dropdown
    final pbOpts = _kPlaybooks.map((p) {
      final sel = p == t.playbook ? ' selected' : '';
      return '<option value="${_esc(p)}"$sel>${_esc(p)}</option>';
    }).join();

    return '''
<div style="padding:12px;overflow-y:auto;height:100%;box-sizing:border-box;">
  <div style="font-size:16px;font-weight:600;margin-bottom:12px;color:var(--color-text);">
    ${_esc(t.nickname.isEmpty ? t.team : t.nickname)}
    <span style="font-size:12px;font-weight:400;color:var(--color-muted);margin-left:8px;">${_esc(t.team)}</span>
  </div>

  <div class="attr-grid" id="tde-fields">

    <!-- ── Fixed-length text fields ── -->
    <div style="width:100%;flex-basis:100%;">
      <div style="font-size:11px;color:var(--color-muted);font-style:italic;margin-bottom:8px;">
        &#x24D8;&nbsp;Nickname, Abbreviation, City, and Alt&nbsp;Abbrev are fixed-length fields
        &mdash; each cannot exceed the character count of the original value.
      </div>
      <div style="display:flex;flex-wrap:wrap;gap:8px;">
        ${_textField('Nickname',  'Nickname',      t.nickname)}
        ${_textField('Abbrev',    'Abbreviation',  t.abbrev)}
        ${_textField('City',      'City',          t.city)}
        ${_textField('AbbrAlt',   'Alt Abbrev',    t.abbrAlt)}
      </div>
    </div>

    <!-- ── Dropdown fields — natural-width cards on one row ── -->
    <div class="attr-card dropdown-field" data-key="Stadium" style="width:220px;">
      <div class="attr-card-label">Stadium</div>
      <select class="pes-dropdown tde-dropdown" data-key="Stadium">$stadOpts</select>
    </div>
    <div class="attr-card dropdown-field" data-key="Playbook">
      <div class="attr-card-label">Playbook</div>
      <select class="pes-dropdown tde-dropdown" data-key="Playbook">$pbOpts</select>
    </div>
    <div class="attr-card dropdown-field" data-key="DefaultJersey">
      <div class="attr-card-label">Default Jersey</div>
      <select class="pes-dropdown tde-dropdown" data-key="DefaultJersey">
        ${jerseyOpts.isEmpty
            ? '<option value="${_esc(t.defaultJersey)}">${_esc(t.defaultJersey)}</option>'
            : jerseyOpts}
      </select>
    </div>
    ${_buildLogoDropdown(t.logo)}

    ${_buildSpecialTeamsSection(t)}

  </div>
</div>''';
  }

  // ─── Special teams section ────────────────────────────────────────────────

  static const _kStRoleLabels = [
    ('Holder', 'Holder (FG/PAT)'),
    ('KR1', 'Kick Returner 1'),
    ('KR2', 'Kick Returner 2'),
    ('PK',  'Placekicker'),
    ('PR',  'Punt Returner'),
    ('LS',  'Long Snapper'),
  ];

  String _buildSpecialTeamsSection(TeamDataRow t) {
    final stData = parseSpecialTeamsForTeam(_appState.textContent, t.team);

    final sectionHeader = '''
<div style="width:100%;flex-basis:100%;margin-top:4px;">
  <div style="font-size:11px;font-weight:600;color:var(--color-muted);
              text-transform:uppercase;letter-spacing:0.05em;
              border-top:1px solid var(--color-border);
              padding-top:12px;margin-bottom:8px;">
    Special Teams
  </div>''';

    if (stData == null) {
      // Option is off — show disabled dropdowns with a note
      final disabledCards = _kStRoleLabels.map((r) => '''
  <div class="attr-card dropdown-field" style="width:180px;">
    <div class="attr-card-label">${r.$1}</div>
    <select class="pes-dropdown" disabled><option>—</option></select>
  </div>''').join('\n');

      return '''
$sectionHeader
  <div style="font-size:11px;color:var(--color-muted);font-style:italic;margin-bottom:8px;">
    Enable <b>Show Special Teams</b> in Options to edit these fields.
  </div>
  <div style="display:flex;flex-wrap:wrap;gap:8px;">
$disabledCards
  </div>
</div>''';
    }

    // Build the option list once — shared across all 4 dropdowns
    final optionsBuf = StringBuffer();
    for (final opt in stData.rosterOptions) {
      optionsBuf.write('<option value="${_esc(opt.posDepth)}">'
          '${_esc(opt.posDepth)} \u2014 ${_esc(opt.displayName)}</option>');
    }
    final allOptions = optionsBuf.toString();

    final dropdowns = _kStRoleLabels.map((r) {
      final slot = stData.slots[r.$1];
      final cur  = slot?.value ?? '';
      // Inject selected attr into the matching option
      final opts = allOptions.replaceFirst(
          'value="${_esc(cur)}"',
          'value="${_esc(cur)}" selected');
      return '''
  <div class="attr-card dropdown-field" style="width:180px;">
    <div class="attr-card-label">${_esc(r.$2)}</div>
    <select class="pes-dropdown tde-st-dropdown"
            data-line="${slot?.lineIndex ?? -1}"
            data-role="${_esc(r.$1)}">
      $opts
    </select>
  </div>''';
    }).join('\n');

    final autoUpdateNote = _appState.options.autoUpdateDepthCharts
        ? '''
  <div style="font-size:11px;color:var(--color-muted);margin-bottom:8px;display:flex;align-items:flex-start;gap:4px;">
    <span class="material-symbols-outlined" style="font-size:14px;line-height:1.4;">warning</span>
    <span><b>Auto Update Depth Charts</b> is ON — Holder, KR1, KR2, PR, and LS will be
    reset to its own picks (punter as Holder; fastest returners; a center at LS)
    every time you Apply/Export, overriding any choices made here. <b>PK is not
    affected.</b> Turn off <b>Auto Update Depth Charts</b> in Options to keep your
    own picks.</span>
  </div>'''
        : '''
  <div style="font-size:11px;color:var(--color-muted);font-style:italic;margin-bottom:8px;">
    <b>Auto Update Depth Charts</b> is off, so your picks here are kept as-is on
    Apply/Export.
  </div>''';

    return '''
$sectionHeader
$autoUpdateNote
  <div style="display:flex;flex-wrap:wrap;gap:8px;">
$dropdowns
  </div>
</div>''';
  }

  String _textField(String key, String label, String value) {
    final max = _maxFieldLen[key];
    final maxAttr = max != null ? ' maxlength="$max"' : '';
    final hint = max != null
        ? ' <span class="tde-char-hint" style="float:right;font-weight:400;">${value.length}/$max</span>'
        : '';
    return '''
<div class="attr-card text-field" data-key="${_esc(key)}">
  <div class="attr-card-label">${_esc(label)}$hint</div>
  <input type="text" class="pes-text-input tde-text-input" data-key="${_esc(key)}"
    value="${_esc(value)}"$maxAttr>
</div>''';
  }

  String _buildLogoDropdown(String curLogoStr) {
    final curVal   = int.tryParse(curLogoStr) ?? 0;
    final hasMatch = _kLogos.any((l) => l.value == curVal);
    final buf = StringBuffer();
    if (!hasMatch) {
      buf.write('<option value="${_esc(curLogoStr)}" selected>(unknown: ${_esc(curLogoStr)})</option>');
    }
    bool selectedOnce = false;
    for (final l in _kLogos) {
      final doSelect = hasMatch && !selectedOnce && l.value == curVal;
      if (doSelect) selectedOnce = true;
      buf.write('<option value="${l.value}"${doSelect ? ' selected' : ''}>${_esc(l.name)}</option>');
    }
    return '''
<div class="attr-card dropdown-field" data-key="Logo">
  <div class="attr-card-label">Team Logo</div>
  <select class="pes-dropdown tde-dropdown" data-key="Logo">${buf.toString()}</select>
</div>''';
  }

  // ─── Event wiring ─────────────────────────────────────────────────────────

  void _attachListeners() {
    // Player controlled checkboxes + toggle button (franchise only)
    if (_appState.isFranchise) {
      final header = _container.querySelector('.section-header') as HTMLElement?;
      header?.addEventListener('change', (Event e) {
        final target = e.target as HTMLElement?;
        if (target == null || !target.classList.contains('pct-check')) return;
        final team = target.dataset['team'];
        if (team.isEmpty) return;
        _togglePlayerControlled(team, (target as HTMLInputElement).checked);
      }.toJS);

      (_container.querySelector('#tde-pct-toggle') as HTMLButtonElement?)
          ?.addEventListener('click', (Event _) {
        final tool = _appState.tool;
        if (tool == null) return;
        final allChecked = GamesaveTool.Teams.every(tool.isTeamPlayerControlled);
        if (allChecked) {
          for (final team in GamesaveTool.Teams) {
            tool.setTeamPlayerControlled(team, false);
          }
        } else {
          tool.setAllTeamsPlayerControlled();
        }
        _updatePlayerControlledLine();
      }.toJS);
    }

    // List selection
    final listPanel = _container.querySelector('#tde-list-panel') as HTMLElement?;
    listPanel?.addEventListener('click', (Event e) {
      final row = (e.target as HTMLElement?)?.closest('.player-row') as HTMLElement?;
      if (row == null) return;
      final idx = int.tryParse(row.dataset['idx']) ?? -1;
      if (idx >= 0 && idx < _teams.length) _selectTeam(idx);
    }.toJS);

    _attachDetailListeners();
  }

  void _togglePlayerControlled(String team, bool value) {
    final tool = _appState.tool;
    if (tool == null) return;
    tool.setTeamPlayerControlled(team, value);
    _updatePlayerControlledLine();
  }

  void _updatePlayerControlledLine() {
    final tool = _appState.tool;
    if (tool == null) return;
    final newLines = tool.getPlayerControlledTeams()
        .split('\n')
        .where((l) => l.isNotEmpty)
        .toList();
    final lines = _appState.textContent.split('\n');
    final out = <String>[];
    bool replaced = false;
    int i = 0;
    while (i < lines.length) {
      if (!replaced && lines[i].startsWith('PlayerControlled=')) {
        out.addAll(newLines);
        replaced = true;
        i++;
        while (i < lines.length && lines[i].startsWith('# PlayerControlledTeams=')) {
          i++;
        }
      } else {
        out.add(lines[i]);
        i++;
      }
    }
    _appState.textContent = out.join('\n');
    // Keep hash in sync so the re-render doesn't reset team selection
    _lastTextHash = _appState.textContent.hashCode;
    _appState.notify();
  }

  void _attachDetailListeners() {
    final detail = _container.querySelector('#tde-detail-panel') as HTMLElement?;
    if (detail == null) return;

    // Live character counter for fixed-length text fields.
    detail.addEventListener('input', (Event e) {
      final target = e.target as HTMLElement?;
      if (target == null || !target.classList.contains('tde-text-input')) return;
      final input = target as HTMLInputElement;
      final key = input.dataset['key'];
      final max = _maxFieldLen[key];
      if (max == null) return;
      final card = detail.querySelector('.attr-card[data-key="${_esc(key)}"]') as HTMLElement?;
      final hint = card?.querySelector('.tde-char-hint') as HTMLElement?;
      if (hint != null) hint.textContent = '${input.value.length}/$max';
    }.toJS);

    // 'focusout' (unlike 'blur') bubbles, so this delegates correctly from
    // the detail panel -- see the identical fix and note in
    // coach_editor_screen.dart / player_editor_screen.dart. A plain 'blur'
    // listener here would never fire for a descendant input's blur at all,
    // silently discarding every typed edit.
    detail.addEventListener('focusout', (Event e) {
      final target = e.target as HTMLElement?;
      if (target == null || !target.classList.contains('tde-text-input')) return;
      final key = (target as HTMLInputElement).dataset['key'];
      _writeField(key, target.value);
    }.toJS);

    // Team data dropdowns
    detail.addEventListener('change', (Event e) {
      final target = e.target as HTMLElement?;
      if (target == null || !target.classList.contains('tde-dropdown')) return;
      _writeField(target.dataset['key'], (target as HTMLSelectElement).value);
    }.toJS);

    // Special teams dropdowns
    detail.addEventListener('change', (Event e) {
      final target = e.target as HTMLElement?;
      if (target == null || !target.classList.contains('tde-st-dropdown')) return;
      final lineIndex = int.tryParse(target.dataset['line']) ?? -1;
      final role      = target.dataset['role'];
      final value     = (target as HTMLSelectElement).value;
      if (lineIndex >= 0 && role.isNotEmpty) _writeStSlot(lineIndex, role, value);
    }.toJS);

    // Numeric +/-
    detail.addEventListener('click', (Event e) {
      final target = e.target as HTMLElement?;
      if (target == null) return;
      final isInc = target.classList.contains('tde-inc');
      final isDec = target.classList.contains('tde-dec');
      if (!isInc && !isDec) return;
      final key  = target.dataset['key'];
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
      _updateNumericCard(detail, key, next, minV, maxV);
    }.toJS);
  }

  // ─── Selection ────────────────────────────────────────────────────────────

  void _selectTeam(int idx) {
    final rows = _container.querySelectorAll('.player-row');
    for (var i = 0; i < rows.length; i++) {
      (rows.item(i) as HTMLElement?)?.classList.remove('selected');
    }
    _container.querySelector('.player-row[data-idx="$idx"]')?.classList.add('selected');
    _selectedIdx = idx;
    final t = _teams[idx];
    _maxFieldLen = {
      'Nickname': t.nickname.length,
      'Abbrev': t.abbrev.length,
      'City': t.city.length,
      'AbbrAlt': t.abbrAlt.length,
    };
    _rebuildDetail();
  }

  void _rebuildDetail() {
    final detail = _container.querySelector('#tde-detail-panel') as HTMLElement?;
    if (detail == null) return;
    detail.innerHTML = _buildDetailHtml().toJS;
    _attachDetailListeners();
  }

  void _updateNumericCard(HTMLElement root, String key, int newVal, int minV, int maxV) {
    final card = root.querySelector('.attr-card.numeric[data-key="${_esc(key)}"]') as HTMLElement?;
    if (card == null) return;
    final valueEl = card.querySelector('.numeric-value') as HTMLElement?;
    if (valueEl != null) valueEl.textContent = newVal.toString();
    final pct = maxV > minV ? ((newVal - minV) / (maxV - minV) * 100).round() : 0;
    final barEl = card.querySelector('.numeric-bar-fill') as HTMLElement?;
    if (barEl != null) barEl.style.width = '$pct%';
  }

  // ─── Field write ──────────────────────────────────────────────────────────

  void _writeField(String key, String value) {
    if (_selectedIdx < 0 || _selectedIdx >= _teams.length) return;
    final team = _teams[_selectedIdx];
    _appState.textContent = setFieldInLine(
        _appState.textContent,
        team.lineIndex,
        key,
        value,
        _headers,
        detectDelimiter(_appState.textContent));
    _lastTextHash = _appState.textContent.hashCode;
    // Re-parse to keep row data in sync
    final parsed = parseTeamDataLines(_appState.textContent);
    _headers = parsed.headers;
    _teams   = parsed.teams;
    // Update list item label if nickname/abbrev/city changed
    if (key == 'Nickname' || key == 'Abbrev' || key == 'City') {
      _updateListItem(_selectedIdx);
    }
  }

  void _writeStSlot(int lineIndex, String role, String newValue) {
    final lines = _appState.textContent.split('\n');
    if (lineIndex < 0 || lineIndex >= lines.length) return;
    lines[lineIndex] = '$role,$newValue';
    _appState.textContent = lines.join('\n');
    _lastTextHash = _appState.textContent.hashCode;
  }

  void _updateListItem(int idx) {
    if (idx < 0 || idx >= _teams.length) return;
    final t = _teams[idx];
    final row = _container.querySelector('.player-row[data-idx="$idx"]') as HTMLElement?;
    if (row == null) return;
    final nameEl = row.querySelector('.player-row-name') as HTMLElement?;
    if (nameEl != null) nameEl.textContent = t.nickname.isEmpty ? t.team : t.nickname;
    final metaEl = row.querySelector('.player-row-meta') as HTMLElement?;
    if (metaEl != null) metaEl.textContent = '${t.abbrev} · ${t.city}';
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  void _resetState() {
    _headers     = [];
    _teams       = [];
    _lastTextHash = 0;
    _selectedIdx = -1;
  }
}
