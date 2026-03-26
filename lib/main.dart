import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart';
import 'package:nfl2k5tool_dart/nfl2k5tool_dart.dart';

import 'app_state.dart';
import 'data/player_data_cache.dart';
import 'data/app_options.dart';
import 'shell/shell.dart';
import 'widgets/top_bar.dart';
import 'widgets/nav_rail.dart';
import 'widgets/status_bar.dart';
import 'screens/player_editor_screen.dart';
import 'screens/schedule_editor_screen.dart';
import 'screens/text_editor_screen.dart';
import 'screens/options_screen.dart';
import 'screens/coach_editor_screen.dart';
import 'screens/team_data_editor_screen.dart';

late AppState appState;
late Shell shell;
late TopBar topBar;
late NavRail navRail;
late StatusBar statusBar;
late PlayerEditorScreen playerEditorScreen;
late ScheduleEditorScreen scheduleEditorScreen;
late TextEditorScreen textEditorScreen;
late OptionsScreen optionsScreen;
late CoachEditorScreen coachEditorScreen;
late TeamDataEditorScreen teamDataEditorScreen;

void main() {
  appState = AppState();

  // Stamp version into the status bar
  (document.getElementById('status-version') as HTMLElement?)
      ?.textContent = 'NFL2K5Tool Web v$appVersion';

  // Restore persisted state
  _restoreTheme();
  _restoreRailCollapsed();
  appState.options = AppOptions.load();

  // Instantiate widgets / screens
  shell = Shell(appState);
  topBar = TopBar(appState);
  navRail = NavRail(appState);
  statusBar = StatusBar(appState);
  playerEditorScreen = PlayerEditorScreen(appState);
  scheduleEditorScreen = ScheduleEditorScreen(appState);
  textEditorScreen = TextEditorScreen(appState);
  optionsScreen = OptionsScreen(appState);
  coachEditorScreen = CoachEditorScreen(appState);
  teamDataEditorScreen = TeamDataEditorScreen(appState);

  // Wire interactions
  topBar.wire(
    onOpen: _openFile,
    onExport: _showExportDialog,
    onThemeToggle: _toggleTheme,
  );
  navRail.wire(onNav: (section) {
    appState.activeSection = section;
    _renderAll();
  });

  // Register global re-render listener
  appState.addListener(_renderAll);

  // Initial render
  _renderAll();

  // Show players screen by default
  appState.activeSection = NavSection.players;
  _renderAll();

  // Parse the photo ZIP directory synchronously at startup.
  // Only ArchiveFile refs are stored — no photo data is decompressed here —
  // so this completes in well under 100 ms and doesn't block the UI.
  PlayerDataCache.ensureLoaded();
}

void _renderAll() {
  shell.render();
  topBar.render();
  navRail.render();
  statusBar.render();
  _renderActiveScreen();
}

void _renderActiveScreen() {
  switch (appState.activeSection) {
    case NavSection.players:
      playerEditorScreen.render();
    case NavSection.schedule:
      scheduleEditorScreen.render();
    case NavSection.textEditor:
      textEditorScreen.render();
    case NavSection.options:
      optionsScreen.render();
    case NavSection.coaches:
      coachEditorScreen.render();
    case NavSection.teamData:
      teamDataEditorScreen.render();
  }
}

// ─── Theme ────────────────────────────────────────────────────────────────────

void _toggleTheme() {
  appState.themeMode = appState.themeMode == 'dark' ? 'light' : 'dark';
  _applyTheme();
  window.localStorage.setItem('theme', appState.themeMode);
  topBar.render();
}

void _applyTheme() {
  if (appState.themeMode == 'light') {
    document.documentElement?.setAttribute('data-theme', 'light');
  } else {
    document.documentElement?.removeAttribute('data-theme');
  }
}

void _restoreTheme() {
  final saved = window.localStorage.getItem('theme');
  if (saved != null && saved == 'light') {
    appState.themeMode = 'light';
  }
  _applyTheme();
}

// ─── Rail collapse persistence ────────────────────────────────────────────────

void _restoreRailCollapsed() {
  final saved = window.localStorage.getItem('railCollapsed');
  if (saved == 'true') appState.railCollapsed = true;
}

// ─── File Open ────────────────────────────────────────────────────────────────

void _openFile() {
  final input = HTMLInputElement()
    ..type = 'file'
    ..accept = '.ps2,.zip,.dat,.max,.psu,.bin,.img';
  // .toJS requires a sync function — spin off async work inside
  input.onchange = (Event _) {
    _readSelectedFile(input);
  }.toJS;
  input.click();
}

void _readSelectedFile(HTMLInputElement input) {
  final file = input.files?.item(0);
  if (file == null) return;
  file.arrayBuffer().toDart.then((buffer) {
    final bytes = Uint8List.view(buffer.toDart);
    _loadBytes(bytes, file.name);
  }).catchError((Object e) {
    statusBar.showMessage('Error reading file: $e');
  });
}

/// Decodes [bytes] into a [SaveSession] based on the file extension in [name].
SaveSession _loadFromBytes(Uint8List bytes, String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.zip'))              return SaveSession.fromXboxZip(bytes);
  if (n.endsWith('.dat'))              return SaveSession.fromRawDat(bytes);
  if (n.endsWith('.img') || n.endsWith('.bin')) { return SaveSession.fromXboxMU(bytes); }
  if (n.endsWith('.max') || n.endsWith('.psu')) { return SaveSession.fromPs2Save(bytes); }
  if (n.endsWith('.ps2'))              return SaveSession.fromPs2Card(bytes);
  throw Exception('Unsupported file extension.');
}

void _loadBytes(Uint8List bytes, String name) {
  try {
    final session = _loadFromBytes(bytes, name);

    final tool = session.engine;
    appState.session = session;
    appState.tool = tool;
    appState.fileName = name;
    appState.fileType =
        tool.saveType == SaveType.Franchise ? 'FRANCHISE' : 'ROSTER';
    appState.textContent =
        appState.buildTextContent(tool, appState.options);
    appState.refreshCounts();
    appState.notify();
    statusBar.showMessage('Loaded: $name');
  } catch (e) {
    statusBar.showMessage('Error loading file: $e');
  }
}

// ─── Export ───────────────────────────────────────────────────────────────────

// Export format descriptor
typedef _ExportFmt = ({String label, String ext});

/// Returns the formats this session can be exported to, based on the input
/// file extension, per the tool's conversion rules.
List<_ExportFmt> _allowedExportFormats(String fileName) {
  final n = fileName.toLowerCase();
  final isXbox = n.endsWith('.zip') || n.endsWith('.bin') || n.endsWith('.img');
  final isPs2  = n.endsWith('.ps2') || n.endsWith('.max') || n.endsWith('.psu');
  final isDat  = n.endsWith('.dat');

  if (isXbox) {
    return [
      (label: 'Xbox Zip (.zip)',                        ext: '.zip'),
      (label: 'Xbox Memory Unit (.bin) — new card',     ext: '.bin'),
      (label: 'Xbox Memory Unit (.img) — new card',     ext: '.img'),
      (label: 'PS2 Max (.max)',                         ext: '.max'),
      (label: 'PS2 PSU (.psu)',                         ext: '.psu'),
      (label: 'PS2 Memory Card (.ps2) — new card',      ext: '.ps2'),
      (label: 'Raw DAT (.dat)',                         ext: '.dat'),
    ];
  } else if (isPs2) {
    return [
      (label: 'PS2 Max (.max)',                         ext: '.max'),
      (label: 'PS2 PSU (.psu)',                         ext: '.psu'),
      (label: 'PS2 Memory Card (.ps2) — new card',      ext: '.ps2'),
      (label: 'Raw DAT (.dat)',                         ext: '.dat'),
    ];
  } else if (isDat) {
    return [
      (label: 'Raw DAT (.dat)',                         ext: '.dat'),
    ];
  }
  return [(label: 'Raw DAT (.dat)', ext: '.dat')];
}

void _showExportDialog() {
  if (!appState.hasFile) return;

  final loaded   = appState.fileName ?? 'export';
  final baseName = loaded.contains('.')
      ? loaded.substring(0, loaded.lastIndexOf('.'))
      : loaded;
  final formats  = _allowedExportFormats(loaded);

  final fmtButtons = formats.map((f) =>
    '<button class="text-sidebar-btn exp-fmt" data-ext="${f.ext}">${f.label}</button>'
  ).join('\n');

  final overlay = HTMLDivElement()..className = 'dialog-overlay';
  overlay.innerHTML = '''
<div class="dialog" style="max-width:420px;width:90%;">
  <div class="dialog-header">
    <span>Export Save</span>
    <span class="material-symbols-outlined dialog-close" id="exp-close">close</span>
  </div>
  <div class="dialog-body" style="padding:16px;">
    <label style="font-size:12px;color:var(--color-muted);display:block;margin-bottom:6px;">
      Filename (without extension)
    </label>
    <input id="exp-filename" type="text"
      style="width:100%;background:var(--color-chip);border:1px solid var(--color-border);
             border-radius:4px;color:var(--color-text);padding:6px 10px;font-size:13px;
             outline:none;box-sizing:border-box;margin-bottom:16px;"
      value="${baseName.replaceAll('"', '&quot;')}">
    <div style="font-size:12px;color:var(--color-muted);margin-bottom:8px;">Format</div>
    <div style="display:flex;flex-direction:column;gap:4px;">
      $fmtButtons
    </div>
  </div>
  <div class="dialog-footer">
    <button class="btn btn-outlined" id="exp-cancel">Cancel</button>
  </div>
</div>'''.toJS;

  document.body!.append(overlay);

  void close() { overlay.remove(); }

  overlay.querySelector('#exp-close')?.addEventListener('click',  (Event _) { close(); }.toJS);
  overlay.querySelector('#exp-cancel')?.addEventListener('click', (Event _) { close(); }.toJS);
  overlay.addEventListener('click', (Event e) {
    if ((e.target as HTMLElement?) == overlay) close();
  }.toJS);
  (overlay.firstElementChild as HTMLElement?)
      ?.addEventListener('click', (Event e) { e.stopPropagation(); }.toJS);

  final fmtBtns = overlay.querySelectorAll('.exp-fmt');
  for (var i = 0; i < fmtBtns.length; i++) {
    final btn = fmtBtns.item(i) as HTMLElement;
    btn.addEventListener('click', (Event _) {
      final ext       = btn.dataset['ext'];
      final nameInput = overlay.querySelector('#exp-filename') as HTMLInputElement?;
      final base      = nameInput?.value.trim();
      final filename  = '${base != null && base.isNotEmpty ? base : baseName}$ext';
      close();
      _exportAs(filename);
    }.toJS);
  }

  JSFunction? escFn;
  escFn = (KeyboardEvent e) {
    if (e.key == 'Escape') {
      document.removeEventListener('keydown', escFn!);
      close();
    }
  }.toJS;
  document.addEventListener('keydown', escFn);

  Future.delayed(Duration.zero, () {
    (overlay.querySelector('#exp-filename') as HTMLInputElement?)
      ?..focus()
      ..select();
  });
}

/// Applies text to binary and downloads the file.
/// [name] must include the extension — the extension determines the format.
void _exportAs(String name) {
  final session = appState.session;
  final tool = appState.tool;
  if (session == null || tool == null) return;

  InputParser(tool).ProcessText(appState.textContent);

  final n = name.toLowerCase();
  try {
    Uint8List? bytes;
    if (n.endsWith('.zip')) {
      bytes = session.exportToXboxZip();
    } else if (n.endsWith('.dat')) {
      bytes = tool.GameSaveData;
    } else if (n.endsWith('.max')) {
      bytes = session.exportToPs2Max();
    } else if (n.endsWith('.psu')) {
      bytes = session.exportToPs2Psu();
    } else if (n.endsWith('.ps2')) {
      bytes = session.injectIntoPs2Card();
    } else if (n.endsWith('.bin') || n.endsWith('.img')) {
      bytes = session.injectIntoXboxMU();
    } else {
      statusBar.showMessage('Export not supported for this format');
      return;
    }
    if (bytes == null) {
      statusBar.showMessage('Export failed: no data');
      return;
    }
    downloadBytes(bytes, name);
    statusBar.showMessage('Downloaded: $name');
  } catch (e) {
    statusBar.showMessage('Export error: $e');
  }
}

void downloadBytes(Uint8List bytes, String filename) {
  final blob = Blob([bytes.toJS].toJS);
  final url = URL.createObjectURL(blob);
  final a = HTMLAnchorElement()
    ..href = url
    ..download = filename;
  document.body!.append(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}
