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

/// Runs [text] through [tool] with a player-name overflow check first.
///
/// The check is cheap and silent — the vast majority of saves are under
/// budget and this returns via [onDone] with no UI shown at all. Only when
/// player names would overflow the fixed-size storage pool does
/// [PlayerNameOverflowDialog] appear, offering dedup/truncation reduction
/// options before the real commit happens.
///
/// If the user cancels the dialog, [tool]'s GameSaveData is restored to its
/// state from before this function ran (undoing the non-name attribute
/// writes that PlayerNames.fromTool's collect pass already made) and
/// [onCancelled] is called instead of [onDone].
void processTextWithNameCheck({
  required GamesaveTool tool,
  required String text,
  required void Function(CommitResult result) onDone,
  required void Function() onCancelled,
}) {
  final names = collectPlayerNamesFromText(tool, text);

  void finish() {
    onDone(commitPlayerNamesAndApplyRest(tool, text, names));
  }

  if (names.requiredBytes <= PlayerNames.budget) {
    finish();
    return;
  }

  PlayerNameOverflowDialog().open(
    names: names,
    onProceed: finish,
    onCancel: () {
      final snap = names.preCollectSnapshot;
      if (snap != null) tool.GameSaveData!.setAll(0, snap);
      onCancelled();
    },
  );
}

/// Shows the player-name space-budget dialog: lets the user pick dedup or
/// truncation to close the deficit (or tells them neither can, if neither
/// technique's best case covers it), and applies the chosen minimal plan.
class PlayerNameOverflowDialog {
  HTMLElement? _overlay;
  JSFunction? _escFn;
  String? _selected; // 'dedup' | 'truncation'

  void open({
    required PlayerNames names,
    required void Function() onProceed,
    required void Function() onCancel,
  }) {
    if (_overlay != null) return;

    final deficit = names.requiredBytes - PlayerNames.budget;
    final dedup = names.planDedup();
    final trunc = names.planTruncation();
    final dedupSufficient = dedup.totalSavings >= deficit;
    final truncSufficient = trunc.totalSavings >= deficit;
    final anySufficient = dedupSufficient || truncSufficient;

    final overlay = document.createElement('div') as HTMLElement
      ..className = 'dialog-overlay';

    void close() {
      if (_escFn != null) _removeEscListener(_escFn!);
      overlay.remove();
      _overlay = null;
      _escFn = null;
    }

    if (!anySufficient) {
      overlay.innerHTML = '''
<div class="dialog" style="max-width:440px;width:90%;">
  <div class="dialog-header">Player Names Won't Fit</div>
  <div class="dialog-body" style="font-size:13px;color:var(--color-text-secondary);line-height:1.5;">
    Player names need <b>${_fmt(deficit)} more bytes</b> than the save file has room for
    (best-case merging duplicate names saves ${_fmt(dedup.totalSavings)}; best-case shortening
    free-agent first names saves ${_fmt(trunc.totalSavings)} — neither is enough on its own).
    <br><br>
    These tools can't resolve this automatically. Shorten or remove some player names
    in the Text Editor, then try again.
  </div>
  <div class="dialog-footer">
    <button class="btn btn-outlined" id="pno-cancel">Cancel</button>
  </div>
</div>'''.toJS;
      document.body!.append(overlay);
      overlay.querySelector('#pno-cancel')?.addEventListener('click', (Event _) {
        close();
        onCancel();
      }.toJS);
      _wireOverlayClose(overlay, () { close(); onCancel(); });
      _escFn = _addEscListener(() { close(); onCancel(); });
      _overlay = overlay;
      return;
    }

    String card(String id, String title, int savings, bool sufficient, String desc) => '''
<div class="pno-option-card" data-id="$id" style="border:1px solid var(--color-border);border-radius:8px;
  padding:12px;margin-bottom:10px;cursor:pointer;">
  <div style="font-weight:600;font-size:13px;margin-bottom:4px;">$title</div>
  <div style="font-size:12px;color:var(--color-muted);margin-bottom:6px;">
    Saves up to ${_fmt(savings)} bytes
    ${sufficient ? '' : '<span style="color:var(--color-gold);">— won\'t fully resolve this on its own</span>'}
  </div>
  <div style="font-size:12px;color:var(--color-text-secondary);line-height:1.4;">$desc</div>
</div>''';

    overlay.innerHTML = '''
<div class="dialog" style="max-width:480px;width:90%;">
  <div class="dialog-header">
    <span>Player Names Won't Fit</span>
    <span class="material-symbols-outlined dialog-close" id="pno-close">close</span>
  </div>
  <div class="dialog-body">
    <div style="font-size:13px;color:var(--color-text-secondary);margin-bottom:14px;">
      Player names need <b>${_fmt(deficit)} more bytes</b> than the save file has room for.
      Pick one way to make room:
    </div>
    ${card('dedup', 'Merge duplicate names', dedup.totalSavings, dedupSufficient,
        'No name text changes — players who already share an identical first or last name '
        'will share one copy in storage instead of separate copies. This permanently changes '
        'how those names are stored internally.')}
    ${card('truncation', 'Shorten free-agent first names', trunc.totalSavings, truncSufficient,
        'Free-agent first names longer than 4 characters become an initial (e.g. "Donald" '
        '→ "D."), starting with the lowest-priority free agents. Last names are never changed.')}
  </div>
  <div class="dialog-footer">
    <button class="btn btn-outlined" id="pno-cancel">Cancel</button>
    <button class="btn btn-filled" id="pno-apply" disabled>Apply &amp; Continue</button>
  </div>
</div>'''.toJS;

    document.body!.append(overlay);

    final cards = overlay.querySelectorAll('.pno-option-card');
    final applyBtn = overlay.querySelector('#pno-apply') as HTMLButtonElement;

    void selectCard(String id) {
      _selected = id;
      for (var i = 0; i < cards.length; i++) {
        final el = cards.item(i) as HTMLElement;
        final isSelected = el.dataset['id'] == id;
        el.style.borderColor = isSelected ? 'var(--color-gold)' : 'var(--color-border)';
        el.style.background = isSelected ? 'var(--color-active-bg)' : '';
      }
      applyBtn.disabled = false;
    }

    for (var i = 0; i < cards.length; i++) {
      final el = cards.item(i) as HTMLElement;
      el.addEventListener('click', (Event _) { selectCard(el.dataset['id']); }.toJS);
    }

    applyBtn.onclick = (Event _) {
      final sel = _selected;
      if (sel == null) return;
      if (sel == 'dedup') {
        names.applyDedup(names.planDedup(targetBytes: deficit));
      } else {
        names.applyTruncation(names.planTruncation(targetBytes: deficit));
      }
      close();
      onProceed();
    }.toJS;

    overlay.querySelector('#pno-close')?.addEventListener('click', (Event _) {
      close();
      onCancel();
    }.toJS);
    overlay.querySelector('#pno-cancel')?.addEventListener('click', (Event _) {
      close();
      onCancel();
    }.toJS);
    _wireOverlayClose(overlay, () { close(); onCancel(); });
    _escFn = _addEscListener(() { close(); onCancel(); });
    _overlay = overlay;
  }
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
