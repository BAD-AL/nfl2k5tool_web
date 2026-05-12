import 'package:nfl2k5tool_dart/nfl2k5tool_dart.dart';
import 'data/app_options.dart';
import 'data/text_parser.dart';

enum NavSection { options, players, schedule, coaches, teamData, textEditor }

class AppState {
  // File state
  SaveSession? session;
  GamesaveTool? tool;
  String textContent = '';
  String? fileName;
  String? fileType; // 'FRANCHISE' | 'ROSTER' | null
  int teamCount = 0;
  int playerCount = 0;
  String? statusMessage;

  // UI state
  NavSection activeSection = NavSection.players;
  bool railCollapsed = false;
  String themeMode = 'dark'; // 'dark' | 'light'

  // Options
  AppOptions options = AppOptions();

  bool get hasFile => tool != null;
  bool get isFranchise => fileType == 'FRANCHISE';

  // §15.9 Schedule text extraction
  String? get scheduleText {
    const marker = '\nYEAR=';
    final pos = textContent.indexOf(marker);
    return pos >= 0 ? textContent.substring(pos + 1) : null;
  }

  void updateScheduleInText(String newScheduleText) {
    const marker = '\nYEAR=';
    final pos = textContent.indexOf(marker);
    final playerSection =
        pos >= 0 ? textContent.substring(0, pos) : textContent;
    textContent = '$playerSection\n$newScheduleText';
  }

  // §15.8 Text content construction
  String buildTextContent(GamesaveTool t, AppOptions opts) {
    final buf = StringBuffer();
    if (opts.showPlayers || opts.showFreeAgents || opts.showDraftClass) {
      buf.write(t.GetKey(opts.showAttributes, opts.showAppearance));
      buf.write('\n');
    }
    buf.write('\n# Uncomment line below to Set Salary Cap -> 198.2M\n');
    buf.write('# SET(0x9ACCC, 0x38060300)\n\n');
    if (opts.showPlayers) {
      buf.write(t.GetLeaguePlayers(
          opts.showAttributes, opts.showAppearance, opts.showSpecialTeams));
    }
    if (opts.showFreeAgents) {
      buf.write(t.GetTeamPlayers(
          'FreeAgents', opts.showAttributes, opts.showAppearance, false));
    }
    if (opts.showDraftClass) {
      buf.write(t.GetTeamPlayers(
          'DraftClass', opts.showAttributes, opts.showAppearance, false));
    }
    if (opts.showCoaches) {
      t.CoachKey = t.CoachKeyAll; // always use full key
      buf.write(t.GetCoachDataAll());
    }
    if (opts.showTeamData) {
      buf.write('\n\n');
      if (t.saveType == SaveType.Franchise) buf.write(t.getPlayerControlledTeams());
      buf.write(t.GetTeamDataAll());
    }
    if (opts.showSchedule && t.saveType == SaveType.Franchise) {
      SchedulerHelper.showDateTime = opts.showScheduleDateTime;
      buf.write('\n\n#Schedule\n');
      buf.write(t.GetSchedule());
      SchedulerHelper.showDateTime = false;
    }
    if (opts.autoUpdateDepthCharts) buf.write('\nAutoUpdateDepthChart');
    if (opts.autoUpdatePhotos) buf.write('\nAutoUpdatePhoto');
    if (opts.autoUpdatePBP) buf.write('\nAutoUpdatePBP');
    if (opts.autoFixSkinFromPhoto) buf.write('\nAutoFixSkinFromPhoto');
    return buf.toString();
  }

  // Recompute teamCount/playerCount from current textContent
  void refreshCounts() {
    final (t, p) = countTeamsAndPlayers(textContent);
    teamCount = t;
    playerCount = p;
  }

  // Listener pattern
  final _listeners = <void Function()>[];
  void addListener(void Function() fn) => _listeners.add(fn);
  void notify() {
    for (final fn in _listeners) {
      fn();
    }
  }
}
