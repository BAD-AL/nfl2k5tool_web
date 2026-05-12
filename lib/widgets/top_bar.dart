import 'dart:js_interop';
import 'package:web/web.dart';
import '../app_state.dart';

const _otherLinks = [
  ('Older version (1.0.1)',    'https://bad-al.github.io/nfl2k5tool_web/v1.0.1/'),
  ('NFL2K4 Tool (web)',        'https://bad-al.github.io/nfl2k4tool_web/'),
  ('PS2 Memory Card Manager',  'https://bad-al.github.io/mymc_web/'),
  ('XBOX Memory Card Manager', 'https://bad-al.github.io/xbmut_web/'),
  ('Game Faqs saves',          'https://gamefaqs.gamespot.com/ps2/919830-espn-nfl-2k5/saves'),
  ('Operation Sports link',    'https://forums.operationsports.com/forums/espn-nfl-2k5-football/881901-nfl2k5tool.html'),
  ('PS2 Emulator',             'https://pcsx2.net/'),
  ('OG XBOX Emulator',         'https://xemu.app/'),
];

class TopBar {
  final AppState appState;

  final HTMLButtonElement _btnOpen;
  final HTMLButtonElement _btnExport;
  final HTMLElement _fileBadge;
  final HTMLElement _fileBadgeType;
  final HTMLElement _fileBadgeName;
  final HTMLButtonElement _btnTheme;
  final HTMLElement _themeIcon;
  final HTMLButtonElement _btnOtherLinks;

  TopBar(this.appState)
      : _btnOpen = document.getElementById('btn-open') as HTMLButtonElement,
        _btnExport =
            document.getElementById('btn-export') as HTMLButtonElement,
        _fileBadge = document.getElementById('file-badge') as HTMLElement,
        _fileBadgeType =
            document.getElementById('file-badge-type') as HTMLElement,
        _fileBadgeName =
            document.getElementById('file-badge-name') as HTMLElement,
        _btnTheme = document.getElementById('btn-theme') as HTMLButtonElement,
        _themeIcon = document.getElementById('theme-icon') as HTMLElement,
        _btnOtherLinks =
            document.getElementById('btn-other-links') as HTMLButtonElement;

  void wire({
    required void Function() onOpen,
    required void Function() onExport,
    required void Function() onThemeToggle,
  }) {
    _btnOpen.onClick.listen((_) => onOpen());
    _btnExport.onClick.listen((_) => onExport());
    _btnTheme.onClick.listen((_) => onThemeToggle());
    _btnOtherLinks.addEventListener('click', (Event _) { _showLinksModal(); }.toJS);
  }

  void _showLinksModal() {
    final overlay = document.createElement('div') as HTMLElement
      ..className = 'dialog-overlay';

    final rows = _otherLinks.map((entry) {
      final label = entry.$1;
      final raw   = entry.$2;
      // Split optional text prefix from the URL (e.g. "Forum: https://...")
      final httpIdx = raw.indexOf('https://');
      final prefix  = httpIdx > 0 ? raw.substring(0, httpIdx) : '';
      final url     = httpIdx >= 0 ? raw.substring(httpIdx) : raw;
      final prefixHtml = prefix.isNotEmpty
          ? '<span style="color:var(--color-muted);font-size:11px;">$prefix</span>'
          : '';
      return '''
<a href="$url" target="_blank" rel="noopener" class="other-link-row">
  <span class="other-link-label">$label</span>
  <span class="other-link-url">$prefixHtml$url</span>
</a>''';
    }).join('\n');

    overlay.innerHTML = '''
<div class="dialog" style="max-width:520px;width:90%;">
  <div class="dialog-header">
    <span>Other Links</span>
    <span class="material-symbols-outlined dialog-close">close</span>
  </div>
  <div class="dialog-body" style="padding:8px 0;">
$rows
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

  void render() {
    _btnExport.disabled = !appState.hasFile;

    if (appState.hasFile && appState.fileName != null) {
      _fileBadgeType.textContent = appState.fileType ?? '';
      _fileBadgeName.textContent = appState.fileName ?? '';
      _fileBadge.removeAttribute('hidden');
    } else {
      _fileBadge.setAttribute('hidden', '');
    }

    if (appState.themeMode == 'light') {
      _themeIcon.textContent = 'light_mode';
      _btnTheme.title = 'Switch to Dark mode';
    } else {
      _themeIcon.textContent = 'dark_mode';
      _btnTheme.title = 'Switch to Light mode';
    }
  }
}
