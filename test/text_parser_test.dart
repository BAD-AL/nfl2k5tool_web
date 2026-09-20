import 'dart:io';
import 'package:test/test.dart';
import 'package:nfl2k5tool_web/data/text_parser.dart';

void main() {
  // ── detectDelimiter ───────────────────────────────────────────────────────

  group('detectDelimiter', () {
    test('returns comma for comma-heavy text', () {
      expect(detectDelimiter('a,b,c;d'), ',');
    });

    test('returns semicolon for semicolon-heavy text', () {
      expect(detectDelimiter('a;b;c,d'), ';');
    });

    test('defaults to comma when equal', () {
      expect(detectDelimiter('a,b;c'), ',');
    });
  });

  // ── splitCsv ──────────────────────────────────────────────────────────────

  group('splitCsv', () {
    test('T-PARSE-01: basic player row splits correctly', () {
      const line = 'QB,Tom,Brady,12';
      final f = splitCsv(line);
      expect(f[0], 'QB');
      expect(f[1], 'Tom');
      expect(f[2], 'Brady');
      expect(f[3], '12');
    });

    test('T-PARSE-02: height with inch mark is a literal, not a quote opener', () {
      const line = "QB,Tom,Brady,12,6'0\",226";
      final f = splitCsv(line);
      expect(f[4], "6'0\"");
      expect(f[5], '226');
    });

    test('T-PARSE-03: quoted field with comma parses as single field', () {
      const line = '"Smith, Jr.",Tom,1,';
      final f = splitCsv(line);
      expect(f[0], 'Smith, Jr.');
      expect(f[1], 'Tom');
    });

    test('escaped double-quote inside quoted field', () {
      const line = '"He said ""hi""",next';
      final f = splitCsv(line);
      expect(f[0], 'He said "hi"');
      expect(f[1], 'next');
    });

    test('empty trailing field from trailing comma', () {
      const line = 'a,b,';
      final f = splitCsv(line);
      expect(f.length, 3);
      expect(f[2], '');
    });

    test('semicolon delimiter respected when passed explicitly', () {
      const line = 'a;b;c';
      final f = splitCsv(line, ';');
      expect(f, ['a', 'b', 'c']);
    });
  });

  // ── quoteCsvField ─────────────────────────────────────────────────────────

  group('quoteCsvField', () {
    test('T-PARSE-04: bare inch mark is NOT requoted', () {
      expect(quoteCsvField("6'0\""), "6'0\"");
    });

    test('T-PARSE-04: field with comma IS quoted', () {
      expect(quoteCsvField('Smith, Jr.'), '"Smith, Jr."');
    });

    test('plain field unchanged', () {
      expect(quoteCsvField('Brady'), 'Brady');
    });

    test('field with newline is quoted', () {
      expect(quoteCsvField('a\nb'), '"a\nb"');
    });
  });

  // ── splitCsv + quoteCsvField roundtrip ────────────────────────────────────

  group('CSV roundtrip', () {
    test('height value roundtrips cleanly', () {
      const original = "QB,Tom,Brady,6'0\",226,";
      final fields = splitCsv(original);
      final rejoined = fields.map(quoteCsvField).join(',');
      expect(splitCsv(rejoined), fields);
    });

    test('quoted comma field roundtrips cleanly', () {
      const original = '"Smith, Jr.",Tom,1,';
      final fields = splitCsv(original);
      final rejoined = fields.map(quoteCsvField).join(',');
      expect(splitCsv(rejoined)[0], 'Smith, Jr.');
    });
  });

  // ── setFieldInLine ────────────────────────────────────────────────────────

  group('setFieldInLine', () {
    const sampleText = '#fname,lname,Position,Speed\n'
        'Team = Bears    Players:2\n'
        'Tom,Brady,QB,85\n'
        'Peyton,Manning,QB,72\n';

    const headers = ['fname', 'lname', 'Position', 'Speed'];

    test('replaces a single field correctly', () {
      final result = setFieldInLine(sampleText, 2, 'Speed', '90', headers);
      final lines = result.split('\n');
      expect(lines[2], 'Tom,Brady,QB,90');
    });

    test('all other fields on the line are unchanged', () {
      final result = setFieldInLine(sampleText, 2, 'Speed', '90', headers);
      final f = splitCsv(result.split('\n')[2]);
      expect(f[0], 'Tom');
      expect(f[1], 'Brady');
      expect(f[2], 'QB');
      expect(f[3], '90');
    });

    test('all other lines in the text are unchanged', () {
      final result = setFieldInLine(sampleText, 2, 'Speed', '90', headers);
      final lines = result.split('\n');
      expect(lines[0], '#fname,lname,Position,Speed');
      expect(lines[1], 'Team = Bears    Players:2');
      expect(lines[3], 'Peyton,Manning,QB,72');
    });

    test('returns text unchanged for unknown column', () {
      final result = setFieldInLine(sampleText, 2, 'NonExistent', '99', headers);
      expect(result, sampleText);
    });

    test('returns text unchanged for out-of-range line index', () {
      final result = setFieldInLine(sampleText, 99, 'Speed', '99', headers);
      expect(result, sampleText);
    });
  });

  // ── swapLines ─────────────────────────────────────────────────────────────

  group('swapLines', () {
    test('swaps two lines correctly', () {
      const text = 'a\nb\nc';
      final result = swapLines(text, 0, 2);
      expect(result.split('\n'), ['c', 'b', 'a']);
    });

    test('returns text unchanged for invalid index', () {
      const text = 'a\nb';
      expect(swapLines(text, 0, 5), text);
    });
  });

  // ── parseActiveColumns ────────────────────────────────────────────────────

  group('parseActiveColumns', () {
    test('reads the # header line as the Key (actual file format)', () {
      // Line 1 of the real file: #Position,fname,lname,JerseyNumber,...
      const text = '#Position,fname,lname,JerseyNumber,Speed,\n'
          '\n'
          '# Uncomment line below\n'
          '# SET(0x9ACCC, 0x38060300)\n'
          '\n'
          'Team = Bears    Players:53\n'
          'QB,Tom,Brady,12,85,\n';
      final cols = parseActiveColumns(text);
      expect(cols, ['Position', 'fname', 'lname', 'JerseyNumber', 'Speed']);
    });

    test('ignores comment lines (# followed by space)', () {
      const text = '# This is a comment\n#Position,fname,lname,\n';
      final cols = parseActiveColumns(text);
      expect(cols, ['Position', 'fname', 'lname']);
    });

    test('handles optional #Key= prefix form', () {
      const text = '#Key=fname,lname,Position,Speed,\n';
      expect(parseActiveColumns(text), ['fname', 'lname', 'Position', 'Speed']);
    });

    test('trailing comma does not produce empty column', () {
      const text = '#Position,fname,lname,\n';
      final cols = parseActiveColumns(text);
      expect(cols, ['Position', 'fname', 'lname']);
      expect(cols, isNot(contains('')));
    });

    test('returns empty list when no key line found', () {
      const text = '# Only comments here\n# Another comment\n';
      expect(parseActiveColumns(text), isEmpty);
    });
  });

  // ── parseTeamBlocksForDisplay ─────────────────────────────────────────────

  group('parseTeamBlocksForDisplay', () {
    // Matches the actual file format: key on line 1, team names with Players:N
    const sampleText = '#Position,fname,lname,JerseyNumber,YearsPro\n'
        '\n'
        'Team = Bears    Players:53\n'
        'QB,Tom,Brady,12,7\n'
        'QB,Peyton,Manning,18,10\n'
        '\n'
        'Team = Packers    Players:53\n'
        'QB,Aaron,Rodgers,12,3\n';

    test('T-PARSE-05: extracts correct team count', () {
      final blocks = parseTeamBlocksForDisplay(sampleText);
      expect(blocks.length, 2);
    });

    test('team names strip the Players:N annotation', () {
      final blocks = parseTeamBlocksForDisplay(sampleText);
      expect(blocks[0].name, 'Bears');
      expect(blocks[1].name, 'Packers');
    });

    test('player counts per team are correct', () {
      final blocks = parseTeamBlocksForDisplay(sampleText);
      expect(blocks[0].players.length, 2);
      expect(blocks[1].players.length, 1);
    });

    test('player fields are correctly mapped', () {
      final blocks = parseTeamBlocksForDisplay(sampleText);
      final player = blocks[0].players[0];
      expect(player.firstName, 'Tom');
      expect(player.lastName, 'Brady');
      expect(player.position, 'QB');
      expect(player.jerseyNumber, '12');
    });

    test('lineIndex points to the correct line in textContent', () {
      final blocks = parseTeamBlocksForDisplay(sampleText);
      final player = blocks[0].players[0];
      // Line 0: #key, Line 1: blank, Line 2: Team = Bears, Line 3: Tom Brady
      expect(player.lineIndex, 3);
      // Line 4: Peyton Manning, Line 5: blank, Line 6: Team = Packers, Line 7: Aaron Rodgers
      expect(blocks[1].players[0].lineIndex, 7);
    });

    test('KR1/KR2/PR/LS special-teams lines are not treated as players', () {
      // With Show Special Teams on, these 4 lines appear inside the team
      // block right after the real player rows (see GetTeamPlayers). They
      // belong to the Team Data screen's Special Teams section, not the
      // Player Editor's list.
      const text = '#Position,fname,lname,JerseyNumber\n'
          'Team = Bears    Players:2\n'
          'QB,Tom,Brady,12\n'
          'WR,Randy,Moss,84\n'
          'KR1,WR1\n'
          'KR2,WR2\n'
          'PR,WR1\n'
          'LS,C1\n';
      final blocks = parseTeamBlocksForDisplay(text);
      expect(blocks.length, 1);
      expect(blocks[0].players.length, 2,
          reason: 'Only Tom Brady and Randy Moss are real players');
      expect(blocks[0].players.map((p) => p.fullName),
          ['Tom Brady', 'Randy Moss']);
    });
  });

  // ── countTeamsAndPlayers ──────────────────────────────────────────────────

  group('countTeamsAndPlayers', () {
    test('returns correct team and player counts', () {
      const text = '#fname,lname\nTeam = Bears    Players:2\nTom,Brady\nPeyton,Manning\n'
          'Team = Packers    Players:1\nAaron,Rodgers\n';
      final (teams, players) = countTeamsAndPlayers(text);
      expect(teams, 2);
      expect(players, 3);
    });

    test('returns (0, 0) for empty text', () {
      final (teams, players) = countTeamsAndPlayers('');
      expect(teams, 0);
      expect(players, 0);
    });

    test('KR1/KR2/PR/LS special-teams lines are not counted as players', () {
      const text = '#fname,lname\n'
          'Team = Bears    Players:2\n'
          'Tom,Brady\n'
          'Randy,Moss\n'
          'KR1,WR1\n'
          'KR2,WR2\n'
          'PR,WR1\n'
          'LS,C1\n';
      final (teams, players) = countTeamsAndPlayers(text);
      expect(teams, 1);
      expect(players, 2);
    });
  });

  // ── parseCoachLines ───────────────────────────────────────────────────────

  group('parseCoachLines', () {
    const sampleText = 'CoachKEY=Coach,Team,FirstName,LastName,Body,Photo,Info1\n'
        'Coach,49ers,Dennis,Erickson,[Dennis Erickson],101,Offensive guru\n'
        'Coach,Bears,Lovie,Smith,[Lovie Smith],202,Defensive mind\n';

    test('parses header columns from CoachKEY= line', () {
      final result = parseCoachLines(sampleText);
      expect(result.headers,
          ['Coach', 'Team', 'FirstName', 'LastName', 'Body', 'Photo', 'Info1']);
    });

    test('parses correct number of coach rows', () {
      expect(parseCoachLines(sampleText).coaches.length, 2);
    });

    test('coach field getters return correct values', () {
      final c = parseCoachLines(sampleText).coaches[0];
      expect(c.team, '49ers');
      expect(c.firstName, 'Dennis');
      expect(c.lastName, 'Erickson');
      expect(c.body, '[Dennis Erickson]');
      expect(c.photo, '101');
    });

    test('fullName concatenates firstName and lastName', () {
      final c = parseCoachLines(sampleText).coaches[0];
      expect(c.fullName, 'Dennis Erickson');
    });

    test('lineIndex points to correct line', () {
      final coaches = parseCoachLines(sampleText).coaches;
      // Line 0: header, Line 1: 49ers, Line 2: Bears
      expect(coaches[0].lineIndex, 1);
      expect(coaches[1].lineIndex, 2);
    });

    test('bracketed Body field is preserved verbatim', () {
      final c = parseCoachLines(sampleText).coaches[1];
      expect(c.body, '[Lovie Smith]');
    });

    test('returns empty lists when no CoachKEY= line present', () {
      final result = parseCoachLines('# no coach data here\nsome,other,line\n');
      expect(result.headers, isEmpty);
      expect(result.coaches, isEmpty);
    });

    test('CoachKEY= match is case-insensitive', () {
      const text = 'coachkey=Coach,Team,FirstName\nCoach,Browns,Romeo\n';
      final result = parseCoachLines(text);
      expect(result.headers, isNotEmpty);
      expect(result.coaches.length, 1);
    });

    test('non-Coach data lines between coach rows are ignored', () {
      const text = 'CoachKEY=Coach,Team,FirstName,LastName\n'
          '# a comment\n'
          'Team = Bears    Players:53\n'
          'Coach,Bears,Lovie,Smith\n';
      final coaches = parseCoachLines(text).coaches;
      expect(coaches.length, 1);
      expect(coaches[0].lineIndex, 3);
    });
  });

  // ── parseTeamDataLines ────────────────────────────────────────────────────

  group('parseTeamDataLines', () {
    const sampleText =
        'TeamDataKey=TeamData,Team,Nickname,Abbrev,City,AbbrAlt,Stadium,Playbook,DefaultJersey,Logo\n'
        'TeamData,49ers,Niners,SF,San Francisco,SFO,[San Francisco Park],PB_49ers,0,5\n'
        'TeamData,Bears,Bears,CHI,Chicago,CHI,[Chicago Field],PB_Bears,1,10\n';

    test('parses header columns from TeamDataKey= line', () {
      final result = parseTeamDataLines(sampleText);
      expect(result.headers, contains('Team'));
      expect(result.headers, contains('Stadium'));
      expect(result.headers, contains('Playbook'));
    });

    test('parses correct number of team rows', () {
      expect(parseTeamDataLines(sampleText).teams.length, 2);
    });

    test('team field getters return correct values', () {
      final t = parseTeamDataLines(sampleText).teams[0];
      expect(t.team, '49ers');
      expect(t.nickname, 'Niners');
      expect(t.abbrev, 'SF');
      expect(t.city, 'San Francisco');
      expect(t.abbrAlt, 'SFO');
      expect(t.playbook, 'PB_49ers');
      expect(t.defaultJersey, '0');
      expect(t.logo, '5');
    });

    test('bracketed Stadium field is preserved verbatim', () {
      final t = parseTeamDataLines(sampleText).teams[0];
      expect(t.stadium, '[San Francisco Park]');
    });

    test('lineIndex points to correct line', () {
      final teams = parseTeamDataLines(sampleText).teams;
      // Line 0: header, Line 1: 49ers, Line 2: Bears
      expect(teams[0].lineIndex, 1);
      expect(teams[1].lineIndex, 2);
    });

    test('returns empty lists when no TeamDataKey= line present', () {
      final result = parseTeamDataLines('# no team data\nsome,line\n');
      expect(result.headers, isEmpty);
      expect(result.teams, isEmpty);
    });

    test('TeamDataKey= match is case-insensitive', () {
      const text = 'teamdatakey=TeamData,Team,Nickname\nTeamData,Cowboys,Cowboys\n';
      final result = parseTeamDataLines(text);
      expect(result.headers, isNotEmpty);
      expect(result.teams.length, 1);
    });
  });

  // ── coachStringBytesUsed ──────────────────────────────────────────────────

  group('coachStringBytesUsed', () {
    const headers = ['Coach', 'Team', 'FirstName', 'LastName', 'Body', 'Photo',
        'Info1', 'Info2', 'Info3'];

    CoachRow _makeCoach(Map<String, String> fields) =>
        CoachRow(lineIndex: 0, fields: fields);

    test('empty string costs 2 bytes (null terminator only)', () {
      final coach = _makeCoach({'FirstName': '', 'LastName': '', 'Info1': '', 'Info2': '', 'Info3': ''});
      // 5 fields × (0+1)×2 = 10
      expect(coachStringBytesUsed([coach], headers), 10);
    });

    test('"Dennis" costs 14 bytes', () {
      // (6+1)*2 = 14
      final coach = _makeCoach({'FirstName': 'Dennis', 'LastName': '', 'Info1': '', 'Info2': '', 'Info3': ''});
      expect(coachStringBytesUsed([coach], headers), 14 + 2 + 2 + 2 + 2);
    });

    test('single coach with known strings totals correctly', () {
      // "Dennis"=7, "Erickson"=9, "Info A"=7, ""=1, ""=1  → ×2 = 50
      final coach = _makeCoach({
        'FirstName': 'Dennis',   // (6+1)*2 = 14
        'LastName': 'Erickson',  // (8+1)*2 = 18
        'Info1': 'Info A',       // (6+1)*2 = 14
        'Info2': '',             // (0+1)*2 = 2
        'Info3': '',             // (0+1)*2 = 2
      });
      expect(coachStringBytesUsed([coach], headers), 14 + 18 + 14 + 2 + 2);
    });

    test('two coaches sum their bytes', () {
      final c1 = _makeCoach({'FirstName': 'A', 'LastName': 'B', 'Info1': '', 'Info2': '', 'Info3': ''});
      final c2 = _makeCoach({'FirstName': 'C', 'LastName': 'D', 'Info1': '', 'Info2': '', 'Info3': ''});
      // each: (1+1)*2 + (1+1)*2 + 2+2+2 = 4+4+6 = 14; two coaches = 28
      expect(coachStringBytesUsed([c1, c2], headers), 28);
    });

    test('fields absent from headers are not counted', () {
      // headers without Info2 and Info3
      const narrowHeaders = ['Coach', 'Team', 'FirstName', 'LastName', 'Body', 'Photo', 'Info1'];
      final coach = _makeCoach({
        'FirstName': 'X',  // (1+1)*2 = 4
        'LastName': 'Y',   // (1+1)*2 = 4
        'Info1': 'Z',      // (1+1)*2 = 4
        'Info2': 'AAAA',   // not in headers — excluded
        'Info3': 'BBBB',   // not in headers — excluded
      });
      expect(coachStringBytesUsed([coach], narrowHeaders), 4 + 4 + 4);
    });

    test('empty coach list returns 0', () {
      expect(coachStringBytesUsed([], headers), 0);
    });
  });

  // ── kCoachStringBudget ────────────────────────────────────────────────────

  group('kCoachStringBudget', () {
    test('equals 5297 (0x14B1)', () {
      expect(kCoachStringBudget, 5297);
      expect(kCoachStringBudget, 0x14b1);
    });
  });

  // ── kCoachStringCharBudget ────────────────────────────────────────────────

  group('kCoachStringCharBudget', () {
    test('equals half of kCoachStringBudget (2648)', () {
      expect(kCoachStringCharBudget, 2648);
      expect(kCoachStringCharBudget, kCoachStringBudget ~/ 2);
    });
  });

  // ── coachStringCharsUsed ──────────────────────────────────────────────────

  group('coachStringCharsUsed', () {
    const headers = ['Coach', 'Team', 'FirstName', 'LastName', 'Body', 'Photo',
        'Info1', 'Info2', 'Info3'];

    CoachRow makeCoach(Map<String, String> fields) =>
        CoachRow(lineIndex: 0, fields: fields);

    test('equals coachStringBytesUsed divided by 2', () {
      final coach = makeCoach({'FirstName': 'Dennis', 'LastName': 'Erickson',
          'Info1': '', 'Info2': '', 'Info3': ''});
      expect(coachStringCharsUsed([coach], headers),
          coachStringBytesUsed([coach], headers) ~/ 2);
    });

    test('empty strings: 5 null terminators = 5 chars', () {
      final coach = makeCoach({'FirstName': '', 'LastName': '', 'Info1': '', 'Info2': '', 'Info3': ''});
      // bytes: 5 × (0+1)×2 = 10 → chars: 10÷2 = 5
      expect(coachStringCharsUsed([coach], headers), 5);
    });

    test('"Dennis" (6 chars) costs 7 chars (6 + null terminator)', () {
      final coach = makeCoach({'FirstName': 'Dennis', 'LastName': '', 'Info1': '', 'Info2': '', 'Info3': ''});
      // FirstName: (6+1)×2=14 bytes → 7 chars; others: 1 each → 4 chars; total=11
      expect(coachStringCharsUsed([coach], headers), 11);
    });

    test('empty list returns 0', () {
      expect(coachStringCharsUsed([], headers), 0);
    });
  });

  // ── Real file integration ─────────────────────────────────────────────────

  group('Real file: Base2004Fran_Orig', () {
    late String fileText;

    setUpAll(() {
      fileText = File('test/test_files/Base2004Fran_Orig.output.ab.app.sch.txt')
          .readAsStringSync();
    });

    test('parseActiveColumns returns the full column list from line 1', () {
      final cols = parseActiveColumns(fileText);
      expect(cols, isNotEmpty);
      expect(cols.first, 'Position');
      expect(cols, contains('fname'));
      expect(cols, contains('lname'));
      expect(cols, contains('Speed'));
      expect(cols, contains('Photo'));
    });

    test('parseTeamBlocksForDisplay finds 32 teams', () {
      final blocks = parseTeamBlocksForDisplay(fileText);
      expect(blocks.length, 32);
    });

    test('first team is 49ers with 53 players', () {
      final blocks = parseTeamBlocksForDisplay(fileText);
      expect(blocks.first.name, '49ers');
      expect(blocks.first.players.length, 53);
    });

    test('first player of 49ers has correct fields', () {
      final blocks = parseTeamBlocksForDisplay(fileText);
      final p = blocks.first.players.first;
      expect(p.position, 'CB');
      expect(p.firstName, 'Ahmed');
      expect(p.lastName, 'Plummer');
      expect(p.jerseyNumber, '29');
    });

    test('player with quoted college (Miami, FL) parses correctly', () {
      final blocks = parseTeamBlocksForDisplay(fileText);
      final niners = blocks.first;
      final rumph = niners.players.firstWhere((p) => p.lastName == 'Rumph');
      expect(rumph.fields['College'], 'Miami, FL');
    });

    test('height with inch mark parses as single field', () {
      final blocks = parseTeamBlocksForDisplay(fileText);
      final niners = blocks.first;
      final plummer = niners.players.first;
      expect(plummer.fields['Height'], "6'0\"");
    });

    test('countTeamsAndPlayers returns 32 teams and 32*53 players', () {
      final (teams, players) = countTeamsAndPlayers(fileText);
      expect(teams, 32);
      expect(players, 32 * 53);
    });

    test('setFieldInLine on real player line: Speed edit roundtrips correctly', () {
      final blocks = parseTeamBlocksForDisplay(fileText);
      final cols = parseActiveColumns(fileText);
      final p = blocks.first.players.first; // Ahmed Plummer, Speed=90
      expect(p.fields['Speed'], '90');

      final updated = setFieldInLine(fileText, p.lineIndex, 'Speed', '99', cols);
      final reparse = parseTeamBlocksForDisplay(updated);
      final updatedPlayer = reparse.first.players.first;
      expect(updatedPlayer.fields['Speed'], '99');
      // All other fields unchanged
      expect(updatedPlayer.firstName, 'Ahmed');
      expect(updatedPlayer.fields['Height'], "6'0\"");
      expect(updatedPlayer.fields['College'], 'Ohio State');
    });
  });
}
