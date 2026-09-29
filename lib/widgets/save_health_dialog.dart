import 'dart:js_interop';
import 'package:nfl2k5tool_dart/nfl2k5tool_dart.dart';
import 'package:web/web.dart';

// ─── Shared dialog helpers (duplicated per-file, matching this codebase's
// existing convention — see lib/widgets/dialogs.dart) ─────────────────────

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

void _wireOverlayClose(HTMLElement overlay, void Function() close) {
  overlay.addEventListener('click', (Event e) {
    if ((e.target as HTMLElement?) == overlay) close();
  }.toJS);
  (overlay.firstElementChild as HTMLElement?)
      ?.addEventListener('click', (Event e) { e.stopPropagation(); }.toJS);
}

String _fmt(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Purely informational, dismiss-only dialog shown right after loading a
/// file whose existing data already has problems this tool can detect --
/// see [checkSaveFileHealth]. No auto-fix is offered: these issues need a
/// manual workaround (see the dialog body), since automatically resetting
/// onto a clean file would silently discard anything outside the text
/// import/export schema (notably all player/coach stats history), and
/// doesn't help at all when the real content genuinely exceeds budget.
class SaveHealthDialog {
  HTMLElement? _overlay;
  JSFunction? _escFn;

  void open(SaveFileHealthIssues health) {
    if (_overlay != null) return;
    if (!health.hasAnyIssue) return;

    final overlay = document.createElement('div') as HTMLElement
      ..className = 'dialog-overlay';

    void close() {
      if (_escFn != null) _removeEscListener(_escFn!);
      overlay.remove();
      _overlay = null;
      _escFn = null;
    }

    final issues = <String>[];
    if (health.playerNamesOverBy > 0) {
      issues.add('Player names need <b>${_fmt(health.playerNamesOverBy)} more bytes</b> '
          'than this save has room for.');
    }
    if (health.coachStringsOverBy > 0) {
      issues.add('Coach strings need <b>${_fmt(health.coachStringsOverBy)} more bytes</b> '
          'than this save has room for.');
    }
    if (health.sharedNamePointers) {
      issues.add('Some players share the same name-storage location, which can '
          'cause names to be overwritten unexpectedly when edited.');
    }
    if (health.teamsWithInvalidPlaybooks.isNotEmpty) {
      final teams = health.teamsWithInvalidPlaybooks.join(', ');
      issues.add('<b>$teams</b> ${health.teamsWithInvalidPlaybooks.length == 1 ? "has" : "have"} '
          'an invalid playbook assigned. Reassign '
          '${health.teamsWithInvalidPlaybooks.length == 1 ? "it" : "them"} to a valid '
          'playbook via the Team Data editor or Text Editor before exporting.');
    }

    overlay.innerHTML = '''
<div class="dialog" style="max-width:480px;width:90%;">
  <div class="dialog-header">
    <span>This Save Has Some Issues</span>
    <span class="material-symbols-outlined dialog-close" id="shd-close">close</span>
  </div>
  <div class="dialog-body" style="font-size:13px;color:var(--color-muted);line-height:1.6;">
    <ul style="margin:0 0 12px;padding-left:20px;">
      ${issues.map((i) => '<li style="margin-bottom:6px;">$i</li>').join()}
    </ul>
    These need to be resolved before edits to the affected data can be saved.
    A common fix: use Open File's <b>Load Default Roster</b> or
    <b>Load Default Franchise</b> option, copy this file's text from the Text
    Editor, paste it over the clean file's text, then export from there.
  </div>
  <div class="dialog-footer">
    <button class="btn btn-filled" id="shd-ok">OK</button>
  </div>
</div>'''.toJS;

    document.body!.append(overlay);
    overlay.querySelector('#shd-ok')?.addEventListener('click', (Event _) {
      close();
    }.toJS);
    overlay.querySelector('#shd-close')?.addEventListener('click', (Event _) {
      close();
    }.toJS);
    _wireOverlayClose(overlay, close);
    _escFn = _addEscListener(close);
    _overlay = overlay;
  }
}
