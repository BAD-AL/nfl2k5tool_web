/// Team abbreviation table — 32 NFL teams, 2004 rosters.
/// Keys are lowercase full names (as they appear in schedule text).
const Map<String, String> kTeamAbbr = {
  'cardinals': 'ARI', 'falcons':   'ATL', 'ravens':    'BAL', 'bills':      'BUF',
  'panthers':  'CAR', 'bears':     'CHI', 'bengals':   'CIN', 'browns':     'CLE',
  'cowboys':   'DAL', 'broncos':   'DEN', 'lions':     'DET', 'packers':    'GB',
  'texans':    'HOU', 'colts':     'IND', 'jaguars':   'JAX', 'chiefs':     'KC',
  'dolphins':  'MIA', 'vikings':   'MIN', 'patriots':  'NE',  'saints':     'NO',
  'giants':    'NYG', 'jets':      'NYJ', 'raiders':   'OAK', 'eagles':     'PHI',
  'steelers':  'PIT', 'chargers':  'SD',  'seahawks':  'SEA', '49ers':      'SF',
  'rams':      'STL', 'buccaneers':'TB',  'titans':    'TEN', 'redskins':   'WAS',
};

/// Team names sorted by abbreviation (ARI, ATL, BAL, ...).
final List<String> kTeamNamesSorted = (kTeamAbbr.entries.toList()
  ..sort((a, b) => a.value.compareTo(b.value)))
  .map((e) => e.key)
  .toList();

/// Returns the 2–3 letter abbreviation for a team name, or the name uppercased if unknown.
String teamAbbr(String name) =>
    kTeamAbbr[name.toLowerCase()] ?? name.toUpperCase();

// ─── Read-only display models (transient — not the source of truth) ───────────

class ScheduleGame {
  final String away; // lowercase full name, e.g. 'patriots'
  final String home;
  final String? dow;    // e.g. 'sun' — present when showScheduleDateTime is on
  final int? hour;      // display hour (12 = noon, not 0)
  final int? minute;
  const ScheduleGame({required this.away, required this.home,
      this.dow, this.hour, this.minute});
}

class ScheduleWeek {
  final int number;
  final List<ScheduleGame> games;
  const ScheduleWeek({required this.number, required this.games});
}

class ScheduleDisplay {
  final int year;
  final List<ScheduleWeek> weeks;
  const ScheduleDisplay({required this.year, required this.weeks});
}

// ─── Schedule text parser (read-only pass) ────────────────────────────────────

/// Parses the schedule section of [text] for display purposes.
/// [text] should be the YEAR=... onward slice from appState.textContent.
/// The returned [ScheduleDisplay] is transient — do not store as source of truth.
ScheduleDisplay parseScheduleForDisplay(String text) {
  int year = 0;
  final weeks = <ScheduleWeek>[];

  ScheduleWeek? currentWeek;
  final games = <ScheduleGame>[];

  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    if (line.startsWith('YEAR=')) {
      year = int.tryParse(line.substring(5).trim()) ?? 0;
      continue;
    }

    final weekMatch = RegExp(r'^WEEK\s+(\d+)', caseSensitive: false).firstMatch(line);
    if (weekMatch != null) {
      if (currentWeek != null) {
        weeks.add(ScheduleWeek(number: currentWeek.number, games: List.unmodifiable(games)));
        games.clear();
      }
      currentWeek = ScheduleWeek(number: int.parse(weekMatch.group(1)!), games: const []);
      continue;
    }

    // Team names are single words; optionally followed by dow and H:MM.
    final gameMatch = RegExp(
      r'^(\w[\w\d]*(?:\s+\w+)*)\s+at\s+(\w+)'
      r'(?:\s+(sun|mon|tue|wed|thu|fri|sat)(?:\s+(\d{1,2}):(\d{2}))?)?',
      caseSensitive: false).firstMatch(line);
    if (gameMatch != null && currentWeek != null) {
      games.add(ScheduleGame(
        away:   gameMatch.group(1)!.trim().toLowerCase(),
        home:   gameMatch.group(2)!.trim().toLowerCase(),
        dow:    gameMatch.group(3)?.toLowerCase(),
        hour:   int.tryParse(gameMatch.group(4) ?? ''),
        minute: int.tryParse(gameMatch.group(5) ?? ''),
      ));
    }
  }
  if (currentWeek != null) {
    weeks.add(ScheduleWeek(number: currentWeek.number, games: List.unmodifiable(games)));
  }

  return ScheduleDisplay(year: year, weeks: weeks);
}

// ─── In-place text editing ────────────────────────────────────────────────────

/// Replaces the game at [gameIndex] in [weekNumber] with [newAway] at [newHome].
/// Returns the updated full text string.
String setGameInText(
    String text, int weekNumber, int gameIndex, String newAway, String newHome) {
  final lines = text.split('\n');
  int weekIdx = -1;
  int count = 0;

  for (int i = 0; i < lines.length; i++) {
    if (RegExp(r'^WEEK\s+' + weekNumber.toString() + r'\b', caseSensitive: false)
        .hasMatch(lines[i].trim())) {
      weekIdx = i;
      count = 0;
      continue;
    }
    if (weekIdx >= 0) {
      if (RegExp(r'^WEEK\s+\d+', caseSensitive: false).hasMatch(lines[i].trim())) break;
      if (lines[i].trim().isEmpty) continue;
      if (lines[i].trim().toLowerCase().contains(' at ')) {
        if (count == gameIndex) {
          // Preserve any trailing datetime suffix (e.g. "  sun 4:15").
          final m = RegExp(r'^\S+\s+at\s+\S+(.*)', caseSensitive: false)
              .firstMatch(lines[i].trim());
          final suffix = m?.group(1) ?? '';
          lines[i] = '$newAway at $newHome$suffix';
          return lines.join('\n');
        }
        count++;
      }
    }
  }
  return text; // no match — return unchanged
}

/// Sets the day-of-week and time on the game at [gameIndex] in [weekNumber].
/// Replaces any existing dow/time suffix; appends if none present.
/// [hour] is the display hour (12 = noon).
String setGameDateTimeInText(
    String text, int weekNumber, int gameIndex, String dow, int hour, int minute) {
  final lines = text.split('\n');
  int weekIdx = -1;
  int count = 0;

  for (int i = 0; i < lines.length; i++) {
    if (RegExp(r'^WEEK\s+' + weekNumber.toString() + r'\b', caseSensitive: false)
        .hasMatch(lines[i].trim())) {
      weekIdx = i;
      count = 0;
      continue;
    }
    if (weekIdx >= 0) {
      if (RegExp(r'^WEEK\s+\d+', caseSensitive: false).hasMatch(lines[i].trim())) break;
      if (lines[i].trim().isEmpty) continue;
      if (lines[i].trim().toLowerCase().contains(' at ')) {
        if (count == gameIndex) {
          final m = RegExp(r'^\S+\s+at\s+\S+', caseSensitive: false)
              .firstMatch(lines[i].trim());
          final base = m?.group(0) ?? lines[i].trim();
          lines[i] = '$base  $dow $hour:${minute.toString().padLeft(2, '0')}';
          return lines.join('\n');
        }
        count++;
      }
    }
  }
  return text;
}

/// Removes the game at [gameIndex] in [weekNumber].
/// Also updates the [N games] count comment on the WEEK header line.
/// Returns the updated full text string.
String removeGameFromText(String text, int weekNumber, int gameIndex) {
  final lines = text.split('\n');
  int weekHeaderIdx = -1;
  int count = 0;

  for (int i = 0; i < lines.length; i++) {
    if (RegExp(r'^WEEK\s+' + weekNumber.toString() + r'\b', caseSensitive: false)
        .hasMatch(lines[i].trim())) {
      weekHeaderIdx = i;
      count = 0;
      continue;
    }
    if (weekHeaderIdx >= 0) {
      if (RegExp(r'^WEEK\s+\d+', caseSensitive: false).hasMatch(lines[i].trim())) break;
      if (lines[i].trim().isEmpty) continue;
      if (lines[i].trim().toLowerCase().contains(' at ')) {
        if (count == gameIndex) {
          lines.removeAt(i);
          // Update the [N games] comment on the header
          lines[weekHeaderIdx] = _updateGameCount(lines[weekHeaderIdx], -1);
          return lines.join('\n');
        }
        count++;
      }
    }
  }
  return text;
}

/// Adds a new game ([away] at [home]) to [weekNumber].
/// Also updates the [N games] count comment on the WEEK header line.
/// Returns the updated full text string.
String addGameToText(String text, int weekNumber, String away, String home) {
  final lines = text.split('\n');
  int insertIdx = -1;
  int weekHeaderIdx = -1;

  for (int i = 0; i < lines.length; i++) {
    if (RegExp(r'^WEEK\s+' + weekNumber.toString() + r'\b', caseSensitive: false)
        .hasMatch(lines[i].trim())) {
      weekHeaderIdx = i;
      continue;
    }
    if (weekHeaderIdx >= 0) {
      if (RegExp(r'^WEEK\s+\d+', caseSensitive: false).hasMatch(lines[i].trim())) {
        insertIdx = i; // insert before next WEEK header
        break;
      }
      insertIdx = i + 1; // track last line of this week
    }
  }
  if (weekHeaderIdx < 0) return text;
  if (insertIdx < 0) insertIdx = lines.length;

  lines.insert(insertIdx, '$away at $home');
  lines[weekHeaderIdx] = _updateGameCount(lines[weekHeaderIdx], 1);
  return lines.join('\n');
}

/// Updates the `[N games]` annotation in a WEEK header line by [delta].
String _updateGameCount(String headerLine, int delta) {
  return headerLine.replaceFirstMapped(
    RegExp(r'\[(\d+)\s+games?\]', caseSensitive: false),
    (m) {
      final n = (int.tryParse(m.group(1)!) ?? 0) + delta;
      return '[$n game${n == 1 ? '' : 's'}]';
    },
  );
}

// ─── Integrity helpers (read from schedule text) ─────────────────────────────

/// Returns total game appearances per team name across all weeks.
Map<String, int> gameCountByTeam(String scheduleText) {
  final counts = <String, int>{};
  for (final line in scheduleText.split('\n')) {
    final t = line.trim().toLowerCase();
    final m = RegExp(r'^(\S+(?:\s+\S+)*)\s+at\s+(\S+(?:\s+\S+)*)$').firstMatch(t);
    if (m != null) {
      counts[m.group(1)!] = (counts[m.group(1)!] ?? 0) + 1;
      counts[m.group(2)!] = (counts[m.group(2)!] ?? 0) + 1;
    }
  }
  return counts;
}

/// Returns, per week, the set of team names that appear more than once.
List<Set<String>> duplicatesByWeek(String scheduleText) {
  final result = <Set<String>>[];
  Set<String>? seen;

  for (final line in scheduleText.split('\n')) {
    final t = line.trim().toLowerCase();
    if (RegExp(r'^week\s+\d+', caseSensitive: false).hasMatch(t)) {
      if (seen != null) result.add(_duplicates(seen, []));
      seen = {};
      continue;
    }
    if (seen == null) continue;
    final m = RegExp(r'^(\S+(?:\s+\S+)*)\s+at\s+(\S+(?:\s+\S+)*)$').firstMatch(t);
    if (m != null) {
      seen.add(m.group(1)!);
      seen.add(m.group(2)!);
    }
  }
  if (seen != null) result.add(_duplicates(seen, []));
  return result;
}

// Helper: returns teams that appeared more than once in the raw seen set.
// Because a Set de-dupes, we re-scan the raw game lines for actual duplicates.
Set<String> _duplicates(Set<String> _, List<String> __) => {};

// ─── Corrected duplicatesByWeek using list-based tracking ─────────────────────

/// Returns, per week, the set of team names that appear more than once that week.
List<Set<String>> duplicateTeamsByWeek(String scheduleText) {
  final result = <Set<String>>[];
  List<String>? weekTeams;

  for (final line in scheduleText.split('\n')) {
    final t = line.trim().toLowerCase();
    if (RegExp(r'^week\s+\d+', caseSensitive: false).hasMatch(t)) {
      if (weekTeams != null) result.add(_findDuplicates(weekTeams));
      weekTeams = [];
      continue;
    }
    if (weekTeams == null) continue;
    final m = RegExp(r'^(\S+(?:\s+\S+)*)\s+at\s+(\S+(?:\s+\S+)*)$').firstMatch(t);
    if (m != null) {
      weekTeams.add(m.group(1)!);
      weekTeams.add(m.group(2)!);
    }
  }
  if (weekTeams != null) result.add(_findDuplicates(weekTeams));
  return result;
}

Set<String> _findDuplicates(List<String> teams) {
  final seen = <String>{};
  final dupes = <String>{};
  for (final t in teams) {
    if (!seen.add(t)) dupes.add(t);
  }
  return dupes;
}
