import 'dart:js_interop';
import 'package:web/web.dart';
import 'package:nfl2k5tool_dart/nfl2k5tool_dart.dart';
import '../app_state.dart';
import '../widgets/player_name_overflow_dialog.dart';

const _kTextCommandsContent = '''
====== LookupAndModify ======
If we wish to modify player data without specifying all the data we can use this feature.
It is meant to be used in conjunction with the 'Key' command.
The 'Position','fname' and 'lname' attributes must be specified for player lookup.

Example:
    LookupAndModify
    Key= Position,fname,lname,Photo
    QB,Jimmy,Garoppolo,0481,
    QB,Nick,Mullens,0799,
    RB,Tevin,Coleman,0187,
    RB,Matt,Breida,0242,

The above example will lookup the specified players and set their photo the the one specified.

====== LookupAndVerify ======
Example:
    LookupAndVerify
    Key= Position,fname,lname,Photo
    QB,Jimmy,Garoppolo,0481,
    QB,Nick,Mullens,0799,
    RB,Tevin,Coleman,0187,
    RB,Matt,Breida,0242,
# Will produce error message for differences

====== ApplyFormula ======
Can be used to modify players meeting specified attributes.
The 'Global Edit Form' Can be used to craft and apply formulas.
The formulas will print to the console when they are run from the
Global edit form so you can more easily see/create/use/re-use them.

Basic syntax:
    ApplyFormula(<formula>, <target attribute>, < target value>, [positions], <Mode (optional)>)

Examples:
    # For all kickers, punters or quarterbacks who have a white turtleneck, take away 1 speed point
    ApplyFormula('Turtleneck = White','Speed',-1, [K,P,QB], Add)

    # For all quarterbacks who wear a RightGlove, set their RightGlove to 'None'
    ApplyFormula('RightGlove <> None','RightGlove','None', [QB])

    # For all quarterbacks who have speed greater than 80, set their 'Stamana' to 95% of what it currently is
    ApplyFormula('Speed > 80','Stamina',95, [QB], Percent)

    # For all kickers and punters, set their stanama to '95'
    ApplyFormula('Always','Stamina',95, [K,P])
''';

class TextEditorScreen {
  final AppState _appState;
  final HTMLElement _container;

  // Persistent UI state
  int  _fontSize         = 13;
  bool _sidebarCollapsed = true;   // hidden by default
  int  _sidebarWidth     = 180;
  bool _wrapEnabled      = false;
  bool? _lastHasFile;

  // Search state
  String    _searchTerm    = '';
  List<int> _matchOffsets  = [];
  int       _matchIndex    = -1;
  HTMLElement? _searchOverlay;
  JSFunction?  _searchEscFn;

  TextEditorScreen(this._appState)
      : _container =
            document.getElementById('screen-textEditor') as HTMLElement;

  // ─── Entry point ──────────────────────────────────────────────────────────

  void render() {
    final area = _container.querySelector('#te-area') as HTMLTextAreaElement?;
    if (area != null) {
      if (area.value != _appState.textContent) {
        area.value = _appState.textContent;
        _syncGutter(area);
        _updateStatus(area);
        if (_searchTerm.isNotEmpty) { _rerunSearch(); }
      }
      if (_lastHasFile != _appState.hasFile) {
        _lastHasFile = _appState.hasFile;
        _updateSidebarButtonStates();
      }
      return;
    }

    _lastHasFile = _appState.hasFile;
    _container.innerHTML = _buildHtml().toJS;
    _wire();
  }

  // ─── HTML ─────────────────────────────────────────────────────────────────

  String _buildHtml() {
    final dis = _appState.hasFile ? '' : ' disabled';
    return '''
<div class="section-header">
  <span class="material-symbols-outlined section-icon">edit_note</span>
  <span class="section-title">Text Editor</span>
  <div class="te-font-ctrl">
    <button id="te-font-dec" class="btn btn-outlined te-font-btn">−</button>
    <span id="te-font-size" class="te-font-label">${_fontSize}px</span>
    <button id="te-font-inc" class="btn btn-outlined te-font-btn">+</button>
  </div>
</div>
<div class="text-editor">

  ${_buildSidebarHtml(dis)}

  <div class="text-editor-column">

    <div class="text-toolbar">
      <button class="text-toolbar-btn" id="te-find-btn" title="Ctrl+F">🔍</button>
      <button class="text-toolbar-btn" id="te-advanced-btn">Advanced</button>
      <button class="text-toolbar-btn${_wrapEnabled ? ' active' : ''}" id="te-wrap-btn"
        >Wrap: ${_wrapEnabled ? 'On' : 'Off'}</button>
    </div>

    <div class="text-body">
      <div class="text-gutter" id="te-gutter">
        <div class="text-gutter-inner" id="te-gutter-inner"
          style="font-size:${_fontSize}px;">${_gutterText(_appState.textContent)}</div>
      </div>
      <div class="text-area-wrap">
        <textarea id="te-area" class="text-area"
          style="font-size:${_fontSize}px;${_wrapEnabled ? 'white-space:pre-wrap;overflow-wrap:break-word;' : ''}"
          spellcheck="false" autocorrect="off" autocapitalize="off"></textarea>
      </div>
    </div>

    <div class="text-status-bar" id="te-status">Ln 1, Col 1   0 lines   0 chars</div>
  </div>
</div>''';
  }

  String _buildSidebarHtml(String dis) {
    final widthStyle = _sidebarCollapsed
        ? ''
        : ' style="position:relative;width:${_sidebarWidth}px;min-width:${_sidebarWidth}px;"';
    return '''
<div class="text-advanced-sidebar${_sidebarCollapsed ? ' collapsed' : ''}"
    id="te-sidebar"$widthStyle>
  <div class="text-sidebar-header">
    ${_sidebarCollapsed ? '' : '<span>Advanced</span>'}
    <span class="material-symbols-outlined" id="te-sidebar-toggle"
      style="cursor:pointer;font-size:16px;flex-shrink:0;">
      ${_sidebarCollapsed ? 'chevron_right' : 'chevron_left'}
    </span>
  </div>
  ${_sidebarCollapsed ? '' : '''
  <button class="text-sidebar-btn" id="te-apply"$dis>Apply to Save</button>
  <button class="text-sidebar-btn" id="te-list"$dis>List Contents</button>
  <button class="text-sidebar-btn" id="te-reset-key"$dis>Reset Key</button>
  <button class="text-sidebar-btn" id="te-auto-fix"$dis>Auto Fix Skin/Face</button>
  <button class="text-sidebar-btn" id="te-text-commands">Text Commands</button>
  <button class="text-sidebar-btn" id="te-clear">Clear</button>
  <div id="te-resize"
    style="position:absolute;right:0;top:0;bottom:0;width:4px;cursor:col-resize;"></div>
  '''}
</div>''';
  }

  // ─── Wiring ───────────────────────────────────────────────────────────────

  void _wire() {
    final area = _container.querySelector('#te-area') as HTMLTextAreaElement?;
    if (area == null) return;

    area.value = _appState.textContent;
    _syncGutter(area);
    _updateStatus(area);

    _wireFontControls(area);
    _wireTextarea(area);
    _wireSidebarToggleAndResize(area);
    _wireSidebarButtons(area);
    _wireToolbar(area);
  }

  // ─── Font controls ────────────────────────────────────────────────────────

  void _wireFontControls(HTMLTextAreaElement area) {
    _container.querySelector('#te-font-dec')?.addEventListener('click', (Event _) {
      if (_fontSize > 8) { _fontSize--; _applyFontSize(area); }
    }.toJS);
    _container.querySelector('#te-font-inc')?.addEventListener('click', (Event _) {
      if (_fontSize < 28) { _fontSize++; _applyFontSize(area); }
    }.toJS);
  }

  void _applyFontSize(HTMLTextAreaElement area) {
    area.style.fontSize = '${_fontSize}px';
    (_container.querySelector('#te-font-size') as HTMLElement?)?.textContent = '${_fontSize}px';
    (_container.querySelector('#te-gutter-inner') as HTMLElement?)?.style.fontSize = '${_fontSize}px';
  }

  // ─── Textarea ─────────────────────────────────────────────────────────────

  void _wireTextarea(HTMLTextAreaElement area) {
    area.addEventListener('input', (Event _) {
      _appState.textContent = area.value;
      _appState.refreshCounts();
      _syncGutter(area);
      _updateStatus(area);
      if (_searchTerm.isNotEmpty) _rerunSearch();
    }.toJS);

    area.addEventListener('click', (Event _) { _updateStatus(area); }.toJS);
    area.addEventListener('keyup',  (Event _) { _updateStatus(area); }.toJS);

    area.addEventListener('scroll', (Event _) {
      (_container.querySelector('#te-gutter') as HTMLElement?)?.scrollTop = area.scrollTop;
    }.toJS);

    area.addEventListener('keydown', (Event e) {
      final ke = e as KeyboardEvent;
      if (ke.ctrlKey && ke.key == 'f') {
        e.preventDefault();
        _openSearchPopup(area);
        return;
      }
      if (ke.key == 'F3') {
        e.preventDefault();
        ke.shiftKey ? _prevMatch(area) : _nextMatch(area);
      }
    }.toJS);
  }

  // ─── Toolbar ──────────────────────────────────────────────────────────────

  void _wireToolbar(HTMLTextAreaElement area) {
    _container.querySelector('#te-find-btn')?.addEventListener('click', (Event _) {
      _openSearchPopup(area);
    }.toJS);

    _container.querySelector('#te-advanced-btn')?.addEventListener('click', (Event _) {
      _sidebarCollapsed = !_sidebarCollapsed;
      _rebuildSidebar(area);
    }.toJS);

    _container.querySelector('#te-wrap-btn')?.addEventListener('click', (Event _) {
      _wrapEnabled = !_wrapEnabled;
      if (_wrapEnabled) {
        area.style.whiteSpace   = 'pre-wrap';
        area.style.overflowWrap = 'break-word';
      } else {
        area.style.whiteSpace   = 'pre';
        area.style.overflowWrap = 'normal';
      }
      final btn = _container.querySelector('#te-wrap-btn') as HTMLElement?;
      btn?.classList.toggle('active', _wrapEnabled);
      if (btn != null) btn.textContent = 'Wrap: ${_wrapEnabled ? 'On' : 'Off'}';
    }.toJS);
  }

  // ─── Sidebar ──────────────────────────────────────────────────────────────

  void _wireSidebarToggleAndResize(HTMLTextAreaElement area) {
    _container.querySelector('#te-sidebar-toggle')?.addEventListener('click', (Event _) {
      _sidebarCollapsed = !_sidebarCollapsed;
      _rebuildSidebar(area);
    }.toJS);
    _attachResizeHandle(area);
  }

  void _attachResizeHandle(HTMLTextAreaElement area) {
    final handle  = _container.querySelector('#te-resize')  as HTMLElement?;
    final sidebar = _container.querySelector('#te-sidebar') as HTMLElement?;
    if (handle == null || sidebar == null) return;

    handle.addEventListener('mousedown', (Event e) {
      final startX = (e as MouseEvent).clientX;
      final startW = _sidebarWidth;
      sidebar.style.transition = 'none';
      late final JSFunction onMove, onUp;
      onMove = (Event ev) {
        final dx = (ev as MouseEvent).clientX - startX;
        _sidebarWidth = (startW + dx).clamp(120, 400).toInt();
        sidebar.style.width    = '${_sidebarWidth}px';
        sidebar.style.minWidth = '${_sidebarWidth}px';
      }.toJS;
      onUp = (Event _) {
        sidebar.style.transition = '';
        document.removeEventListener('mousemove', onMove);
        document.removeEventListener('mouseup',  onUp);
      }.toJS;
      document.addEventListener('mousemove', onMove);
      document.addEventListener('mouseup',  onUp);
    }.toJS);
  }

  void _rebuildSidebar(HTMLTextAreaElement area) {
    final sidebar = _container.querySelector('#te-sidebar') as HTMLElement?;
    if (sidebar == null) return;

    if (_sidebarCollapsed) {
      sidebar.classList.add('collapsed');
      sidebar.style.removeProperty('width');
      sidebar.style.removeProperty('min-width');
    } else {
      sidebar.classList.remove('collapsed');
      sidebar.style.width    = '${_sidebarWidth}px';
      sidebar.style.minWidth = '${_sidebarWidth}px';
      sidebar.style.position = 'relative';
    }

    final dis = _appState.hasFile ? '' : ' disabled';
    sidebar.innerHTML = '''
<div class="text-sidebar-header">
  ${_sidebarCollapsed ? '' : '<span>Advanced</span>'}
  <span class="material-symbols-outlined" id="te-sidebar-toggle"
    style="cursor:pointer;font-size:16px;flex-shrink:0;">
    ${_sidebarCollapsed ? 'chevron_right' : 'chevron_left'}
  </span>
</div>
${_sidebarCollapsed ? '' : '''
<button class="text-sidebar-btn" id="te-apply"$dis>Apply to Save</button>
<button class="text-sidebar-btn" id="te-list"$dis>List Contents</button>
<button class="text-sidebar-btn" id="te-reset-key"$dis>Reset Key</button>
<button class="text-sidebar-btn" id="te-auto-fix"$dis>Auto Fix Skin/Face</button>
<button class="text-sidebar-btn" id="te-text-commands">Text Commands</button>
<button class="text-sidebar-btn" id="te-clear">Clear</button>
<div id="te-resize"
  style="position:absolute;right:0;top:0;bottom:0;width:4px;cursor:col-resize;"></div>
'''}'''.toJS;

    sidebar.querySelector('#te-sidebar-toggle')?.addEventListener('click', (Event _) {
      _sidebarCollapsed = !_sidebarCollapsed;
      _rebuildSidebar(area);
    }.toJS);
    if (!_sidebarCollapsed) {
      _wireSidebarButtons(area);
      _attachResizeHandle(area);
    }
  }

  void _wireSidebarButtons(HTMLTextAreaElement area) {
    _container.querySelector('#te-apply')?.addEventListener('click',
        (Event _) { _applyToSave(); }.toJS);
    _container.querySelector('#te-list')?.addEventListener('click',
        (Event _) { _listContents(area); }.toJS);
    _container.querySelector('#te-reset-key')?.addEventListener('click',
        (Event _) { _doProcessText('Key=', 'Key reset'); }.toJS);
    _container.querySelector('#te-auto-fix')?.addEventListener('click',
        (Event _) { _doProcessText('AutoFixSkinFromPhoto', 'Auto fix applied'); }.toJS);
    _container.querySelector('#te-text-commands')?.addEventListener('click',
        (Event _) { _showTextCommandsModal(); }.toJS);
    _container.querySelector('#te-clear')?.addEventListener('click', (Event _) {
      _appState.textContent = '';
      area.value = '';
      _appState.refreshCounts();
      _syncGutter(area);
      _updateStatus(area);
      _appState.notify();
    }.toJS);
  }

  void _updateSidebarButtonStates() {
    final hasFile = _appState.hasFile;
    for (final id in ['te-apply', 'te-list', 'te-reset-key', 'te-auto-fix']) {
      final btn = _container.querySelector('#$id') as HTMLButtonElement?;
      if (btn != null) btn.disabled = !hasFile;
    }
  }

  // ─── Gutter ───────────────────────────────────────────────────────────────

  String _gutterText(String text) {
    final n = text.isEmpty ? 1 : '\n'.allMatches(text).length + 1;
    return List.generate(n, (i) => (i + 1).toString()).join('\n');
  }

  void _syncGutter(HTMLTextAreaElement area) {
    (_container.querySelector('#te-gutter-inner') as HTMLElement?)?.textContent =
        _gutterText(area.value);
  }

  // ─── Status bar ───────────────────────────────────────────────────────────

  void _updateStatus(HTMLTextAreaElement area) {
    final status = _container.querySelector('#te-status') as HTMLElement?;
    if (status == null) return;
    final text   = area.value;
    final sel    = area.selectionStart;
    final before = text.substring(0, sel).split('\n');
    final ln     = before.length;
    final col    = before.last.length + 1;
    final totalLines = text.isEmpty ? 0 : text.split('\n').length;
    final chars  = text.length;
    var s = 'Ln $ln, Col $col   $totalLines lines   $chars chars';
    if (_searchTerm.isNotEmpty) {
      s += _matchOffsets.isNotEmpty
          ? '   •   ${_matchIndex + 1}/${_matchOffsets.length} matches'
          : '   •   0 matches';
    }
    status.textContent = s;
  }

  // ─── Search popup ─────────────────────────────────────────────────────────

  void _openSearchPopup(HTMLTextAreaElement area) {
    if (_searchOverlay != null) return;

    final overlay = document.createElement('div') as HTMLElement
      ..className = 'dialog-overlay';
    overlay.innerHTML = '''
<div class="dialog te-search-dialog">
  <div class="dialog-header">
    <span>Find</span>
    <span class="material-symbols-outlined dialog-close">close</span>
  </div>
  <div class="dialog-body" style="padding:12px 16px;">
    <input id="te-search-input" type="text" placeholder="Search\u2026"
      style="width:100%;background:var(--color-chip);border:1px solid var(--color-border);
             border-radius:4px;color:var(--color-text);padding:6px 10px;font-size:13px;
             outline:none;box-sizing:border-box;"
      autocomplete="off" spellcheck="false">
  </div>
  <div class="dialog-footer">
    <button class="btn btn-outlined" id="te-search-cancel">Cancel</button>
    <button class="btn btn-filled" id="te-search-ok">OK</button>
  </div>
</div>'''.toJS;
    document.body!.append(overlay);
    _searchOverlay = overlay;

    final input = overlay.querySelector('#te-search-input') as HTMLInputElement?;
    if (input != null) {
      input.value = _searchTerm;
      Future.delayed(Duration.zero, () { input.focus(); input.select(); });
    }

    void close(bool confirm) {
      final fn = _searchEscFn;
      if (fn != null) document.removeEventListener('keydown', fn);
      _searchEscFn = null;
      _searchOverlay?.remove();
      _searchOverlay = null;

      if (confirm) {
        _searchTerm = input?.value ?? '';
        _runSearch();
        _updateStatus(area);
        if (_matchOffsets.isNotEmpty) _jumpTo(area, 0);
      } else {
        _searchTerm   = '';
        _matchOffsets = [];
        _matchIndex   = -1;
        _updateStatus(area);
      }
      area.focus();
    }

    // ESC → cancel
    late final JSFunction escFn;
    escFn = (Event e) {
      if ((e as KeyboardEvent).key == 'Escape') close(false);
    }.toJS;
    document.addEventListener('keydown', escFn);
    _searchEscFn = escFn;

    // Backdrop click → cancel
    overlay.addEventListener('click', (Event e) {
      if ((e.target as HTMLElement?) == overlay) close(false);
    }.toJS);
    (overlay.firstElementChild as HTMLElement?)
        ?.addEventListener('click', (Event e) { e.stopPropagation(); }.toJS);

    overlay.querySelector('.dialog-close')
        ?.addEventListener('click', (Event _) { close(false); }.toJS);
    overlay.querySelector('#te-search-cancel')
        ?.addEventListener('click', (Event e) { e.stopPropagation(); close(false); }.toJS);
    overlay.querySelector('#te-search-ok')
        ?.addEventListener('click', (Event e) { e.stopPropagation(); close(true); }.toJS);

    input?.addEventListener('keydown', (Event e) {
      if ((e as KeyboardEvent).key == 'Enter') { e.preventDefault(); close(true); }
    }.toJS);
  }

  // ─── Search logic ─────────────────────────────────────────────────────────

  void _runSearch() {
    _matchOffsets = [];
    _matchIndex   = -1;
    if (_searchTerm.isEmpty) return;
    final text = _appState.textContent.toLowerCase();
    final term = _searchTerm.toLowerCase();
    int start = 0;
    while (true) {
      final idx = text.indexOf(term, start);
      if (idx < 0) break;
      _matchOffsets.add(idx);
      start = idx + 1;
    }
  }

  void _rerunSearch() {
    final prev = _matchIndex;
    _runSearch();
    if (_matchOffsets.isNotEmpty) {
      _matchIndex = prev.clamp(0, _matchOffsets.length - 1);
    }
  }

  void _jumpTo(HTMLTextAreaElement area, int index) {
    if (_matchOffsets.isEmpty) return;
    _matchIndex = index.clamp(0, _matchOffsets.length - 1);
    final start = _matchOffsets[_matchIndex];
    area.focus();
    area.setSelectionRange(start, start + _searchTerm.length);
    final linesBefore  = '\n'.allMatches(area.value.substring(0, start)).length;
    final lineHeightPx = _fontSize * 1.5;
    area.scrollTop =
        (linesBefore * lineHeightPx - area.clientHeight / 2 + lineHeightPx)
            .clamp(0, double.infinity);
    _updateStatus(area);
  }

  void _nextMatch(HTMLTextAreaElement area) {
    if (_matchOffsets.isEmpty) return;
    _jumpTo(area, (_matchIndex + 1) % _matchOffsets.length);
  }

  void _prevMatch(HTMLTextAreaElement area) {
    if (_matchOffsets.isEmpty) return;
    _jumpTo(area, (_matchIndex - 1 + _matchOffsets.length) % _matchOffsets.length);
  }

  // ─── Sidebar actions ──────────────────────────────────────────────────────

  void _applyToSave() {
    final tool = _appState.tool;
    if (tool == null) return;
    StaticUtils.Errors.clear();
    processTextWithNameCheck(
      tool: tool,
      text: _appState.textContent,
      onDone: (result) {
        final msgs = [
          if (!result.success) ...result.warnings,
          ...StaticUtils.Errors,
        ];
        _showFeedbackModal(msgs.isEmpty ? 'Done — no errors.' : msgs.join('\n'));
      },
      onCancelled: () => _showFeedbackModal('Cancelled — no changes applied.'),
    );
  }

  void _listContents(HTMLTextAreaElement area) {
    final tool = _appState.tool;
    if (tool == null) return;
    _appState.textContent =
        _appState.buildTextContent(tool, _appState.options);
    area.value = _appState.textContent;
    _appState.refreshCounts();
    _syncGutter(area);
    _updateStatus(area);
    _appState.notify();
  }

  void _doProcessText(String command, String successPrefix) {
    final tool = _appState.tool;
    if (tool == null) return;
    StaticUtils.Errors.clear();
    InputParser(tool).ProcessText(command);
    final result = StaticUtils.Errors.isEmpty
        ? '$successPrefix — no errors.'
        : StaticUtils.Errors.join('\n');
    _showFeedbackModal(result);
  }

  // ─── Feedback modal ───────────────────────────────────────────────────────

  void _showFeedbackModal(String text) {
    final overlay = document.createElement('div') as HTMLElement
      ..className = 'dialog-overlay';
    overlay.innerHTML = '''
<div class="dialog" style="max-width:600px;width:90%;max-height:80vh;">
  <div class="dialog-header">
    <span>Result</span>
    <span class="material-symbols-outlined dialog-close" id="te-modal-x">close</span>
  </div>
  <div class="dialog-body">
    <pre style="margin:0;font-size:12px;white-space:pre-wrap;word-break:break-word;
      color:var(--color-text);">${_esc(text)}</pre>
  </div>
  <div class="dialog-footer">
    <button class="btn btn-outlined" id="te-modal-copy">Copy to Clipboard</button>
    <button class="btn btn-filled" id="te-modal-close">Close</button>
  </div>
</div>'''.toJS;
    document.body!.append(overlay);

    void close() { overlay.remove(); }
    overlay.querySelector('#te-modal-x')?.addEventListener('click', (Event _) { close(); }.toJS);
    overlay.querySelector('#te-modal-close')?.addEventListener('click', (Event _) { close(); }.toJS);
    overlay.querySelector('#te-modal-copy')?.addEventListener('click', (Event _) {
      window.navigator.clipboard.writeText(text);
    }.toJS);

    JSFunction? escFn;
    escFn = (KeyboardEvent e) {
      if (e.key == 'Escape') {
        document.removeEventListener('keydown', escFn!);
        close();
      }
    }.toJS;
    document.addEventListener('keydown', escFn);
  }

  // ─── Text Commands modal ──────────────────────────────────────────────────

  void _showTextCommandsModal() {
    final overlay = document.createElement('div') as HTMLElement
      ..className = 'dialog-overlay';
    overlay.innerHTML = '''
<div class="dialog" style="max-width:680px;width:90%;max-height:80vh;display:flex;flex-direction:column;">
  <div class="dialog-header">
    <span>Text Commands</span>
    <span class="material-symbols-outlined dialog-close">close</span>
  </div>
  <div class="dialog-body" style="overflow-y:auto;flex:1;padding:16px;">
    <pre style="margin:0;font-size:12px;line-height:1.6;white-space:pre-wrap;
                word-break:break-word;color:var(--color-text);
                font-family:monospace;">${_esc(_kTextCommandsContent)}</pre>
  </div>
</div>'''.toJS;
    document.body!.append(overlay);

    void close() { overlay.remove(); }

    overlay.querySelector('.dialog-close')
        ?.addEventListener('click', (Event _) { close(); }.toJS);
    overlay.addEventListener('click', (Event e) {
      if ((e.target as HTMLElement?) == overlay) close();
    }.toJS);
    (overlay.firstElementChild as HTMLElement?)
        ?.addEventListener('click', (Event e) { e.stopPropagation(); }.toJS);

    JSFunction? escFn;
    escFn = (KeyboardEvent e) {
      if (e.key == 'Escape') {
        document.removeEventListener('keydown', escFn!);
        close();
      }
    }.toJS;
    document.addEventListener('keydown', escFn);
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
