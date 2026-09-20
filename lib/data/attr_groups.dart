/// Attribute type — determines which widget is rendered for an attr card.
enum AttrType {
  numeric, text, dropdown, slider, datePicker, autocomplete, mappedId,
  /// A thumbnail (or color swatch, for Skin) + label trigger that opens an
  /// anchored popover listing every option with its own thumbnail/swatch —
  /// see PlayerEditorScreen._buildImagePopoverCard.
  imagePopover,
}

/// Definition of a single player/coach attribute.
class AttrDef {
  final String key;       // CSV column header name (must match Key exactly)
  final String label;     // display label in the UI
  final AttrType type;
  final List<String> options; // for dropdown
  final int min;          // for numeric / slider
  final int max;          // for numeric / slider

  AttrDef({
    required this.key,
    required this.label,
    required this.type,
    this.options = const [],
    this.min = 0,
    this.max = 99,
  });
}

/// A tab group of attribute definitions.
class AttrGroup {
  final String tabLabel;
  final List<AttrDef> attrs;
  AttrGroup({required this.tabLabel, required this.attrs});
}

// ─── Height options ───────────────────────────────────────────────────────────

/// 5'0" through 7'0" in 1-inch steps (73 values).
final List<String> kHeightOptions = () {
  final heights = <String>[];
  for (int totalInches = 60; totalInches <= 84; totalInches++) {
    final feet = totalInches ~/ 12;
    final inches = totalInches % 12;
    heights.add("$feet'$inches\"");
  }
  return heights;
}();

// ─── Attribute group definitions ──────────────────────────────────────────────

/// All possible attribute groups for the player editor.
/// At render time, filter against the active Key columns from the loaded file.
// ignore: prefer_const_declarations
final List<AttrGroup> kAttrGroups = [
  // ── Tab 1: Athletic ────────────────────────────────────────────────────────
  AttrGroup(tabLabel: 'Athletic', attrs: [
    AttrDef(key: 'Speed',      label: 'Speed',      type: AttrType.numeric),
    AttrDef(key: 'Agility',    label: 'Agility',    type: AttrType.numeric),
    AttrDef(key: 'Strength',   label: 'Strength',   type: AttrType.numeric),
    AttrDef(key: 'Jumping',    label: 'Jumping',    type: AttrType.numeric),
    AttrDef(key: 'Stamina',    label: 'Stamina',    type: AttrType.numeric),
    AttrDef(key: 'Durability', label: 'Durability', type: AttrType.numeric),
  ]),

  // ── Tab 2: Skills ──────────────────────────────────────────────────────────
  AttrGroup(tabLabel: 'Skills', attrs: [
    AttrDef(key: 'PassAccuracy',     label: 'Pass Accuracy',     type: AttrType.numeric),
    AttrDef(key: 'PassArmStrength',  label: 'Arm Strength',      type: AttrType.numeric),
    AttrDef(key: 'PassReadCoverage', label: 'Read Coverage',     type: AttrType.numeric),
    AttrDef(key: 'Scramble',         label: 'Scramble',          type: AttrType.numeric),
    AttrDef(
      key: 'PowerRunStyle', label: 'Run Style', type: AttrType.dropdown,
      options: ['Finesse', 'Balanced', 'Power'],
    ),
    AttrDef(key: 'Coverage',     label: 'Coverage',      type: AttrType.numeric),
    AttrDef(key: 'PassRush',     label: 'Pass Rush',     type: AttrType.numeric),
    AttrDef(key: 'RunCoverage',  label: 'Run Coverage',  type: AttrType.numeric),
    AttrDef(key: 'PassBlocking', label: 'Pass Blocking', type: AttrType.numeric),
    AttrDef(key: 'RunBlocking',  label: 'Run Blocking',  type: AttrType.numeric),
    AttrDef(key: 'Catch',        label: 'Catch',         type: AttrType.numeric),
    AttrDef(key: 'RunRoute',     label: 'Run Route',     type: AttrType.numeric),
    AttrDef(key: 'BreakTackle',  label: 'Break Tackle',  type: AttrType.numeric),
    AttrDef(key: 'HoldOntoBall', label: 'Hold Onto Ball',type: AttrType.numeric),
    AttrDef(key: 'Tackle',       label: 'Tackle',        type: AttrType.numeric),
    AttrDef(key: 'KickPower',    label: 'Kick Power',    type: AttrType.numeric),
    AttrDef(key: 'KickAccuracy', label: 'Kick Accuracy', type: AttrType.numeric),
  ]),

  // ── Tab 3: Mental ──────────────────────────────────────────────────────────
  AttrGroup(tabLabel: 'Mental', attrs: [
    AttrDef(key: 'Leadership',    label: 'Leadership',    type: AttrType.numeric),
    AttrDef(key: 'Composure',     label: 'Composure',     type: AttrType.numeric),
    AttrDef(key: 'Consistency',   label: 'Consistency',   type: AttrType.numeric),
    AttrDef(key: 'Aggressiveness',label: 'Aggressiveness',type: AttrType.numeric),
  ]),

  // ── Tab 4: Appearance ─────────────────────────────────────────────────────
  AttrGroup(tabLabel: 'Appearance', attrs: [
    AttrDef(
      key: 'BodyType', label: 'Body Type', type: AttrType.dropdown,
      options: ['Skinny', 'Normal', 'Large', 'ExtraLarge'],
    ),
    AttrDef(
      key: 'Skin', label: 'Skin', type: AttrType.imagePopover,
      options: [for (int i = 1; i <= 22; i++) 'Skin$i'],
    ),
    AttrDef(
      key: 'Face', label: 'Face', type: AttrType.dropdown,
      options: [for (int i = 1; i <= 15; i++) 'Face$i'],
    ),
    AttrDef(
      key: 'Dreads', label: 'Dreads', type: AttrType.dropdown,
      options: ['No', 'Yes'],
    ),
    AttrDef(
      key: 'Helmet', label: 'Helmet', type: AttrType.dropdown,
      options: ['Standard', 'Revolution'],
    ),
    AttrDef(
      key: 'FaceMask', label: 'Face Mask', type: AttrType.imagePopover,
      options: [for (int i = 1; i <= 27; i++) 'FaceMask$i'],
    ),
    AttrDef(
      key: 'Visor', label: 'Visor', type: AttrType.dropdown,
      options: ['None', 'Dark', 'Clear'],
    ),
    AttrDef(
      key: 'EyeBlack', label: 'Eye Black', type: AttrType.dropdown,
      options: ['No', 'Yes'],
    ),
    AttrDef(
      key: 'MouthPiece', label: 'Mouth Piece', type: AttrType.dropdown,
      options: ['No', 'Yes'],
    ),
    AttrDef(
      key: 'LeftGlove', label: 'Left Glove', type: AttrType.imagePopover,
      options: ['None', 'Type1', 'Type2', 'Type3', 'Type4', 'Team1', 'Team2', 'Team3', 'Team4', 'Taped'],
    ),
    AttrDef(
      key: 'RightGlove', label: 'Right Glove', type: AttrType.imagePopover,
      options: ['None', 'Type1', 'Type2', 'Type3', 'Type4', 'Team1', 'Team2', 'Team3', 'Team4', 'Taped'],
    ),
    AttrDef(
      key: 'LeftWrist', label: 'Left Wrist', type: AttrType.imagePopover,
      options: ['None', 'SingleWhite', 'DoubleWhite', 'SingleBlack', 'DoubleBlack', 'NeopreneSmall', 'NeopreneLarge', 'ElasticSmall', 'ElasticLarge', 'SingleTeam', 'DoubleTeam', 'TapedSmall', 'TapedLarge', 'Quarterback'],
    ),
    AttrDef(
      key: 'RightWrist', label: 'Right Wrist', type: AttrType.imagePopover,
      options: ['None', 'SingleWhite', 'DoubleWhite', 'SingleBlack', 'DoubleBlack', 'NeopreneSmall', 'NeopreneLarge', 'ElasticSmall', 'ElasticLarge', 'SingleTeam', 'DoubleTeam', 'TapedSmall', 'TapedLarge', 'Quarterback'],
    ),
    AttrDef(
      key: 'LeftElbow', label: 'Left Elbow', type: AttrType.imagePopover,
      options: ['None', 'White', 'Black', 'WhiteBlackStripe', 'BlackWhiteStripe', 'BlackTeamStripe', 'Team', 'WhiteTeamStripe', 'Elastic', 'Neoprene', 'WhiteTurf', 'BlackTurf', 'Taped', 'HighWhite', 'HighBlack', 'HighTeam'],
    ),
    AttrDef(
      key: 'RightElbow', label: 'Right Elbow', type: AttrType.imagePopover,
      options: ['None', 'White', 'Black', 'WhiteBlackStripe', 'BlackWhiteStripe', 'BlackTeamStripe', 'Team', 'WhiteTeamStripe', 'Elastic', 'Neoprene', 'WhiteTurf', 'BlackTurf', 'Taped', 'HighWhite', 'HighBlack', 'HighTeam'],
    ),
    AttrDef(
      key: 'Sleeves', label: 'Sleeves', type: AttrType.dropdown,
      options: ['None', 'White', 'Black', 'Team'],
    ),
    AttrDef(
      key: 'LeftShoe', label: 'Left Shoe', type: AttrType.imagePopover,
      options: ['Shoe1', 'Shoe2', 'Shoe3', 'Shoe4', 'Shoe5', 'Shoe6', 'Taped'],
    ),
    AttrDef(
      key: 'RightShoe', label: 'Right Shoe', type: AttrType.imagePopover,
      options: ['Shoe1', 'Shoe2', 'Shoe3', 'Shoe4', 'Shoe5', 'Shoe6', 'Taped'],
    ),
    AttrDef(
      key: 'NeckRoll', label: 'Neck Roll', type: AttrType.imagePopover,
      options: ['None', 'Collar', 'Roll', 'Washboard', 'Bulging'],
    ),
    AttrDef(
      key: 'Turtleneck', label: 'Turtleneck', type: AttrType.dropdown,
      options: ['None', 'White', 'Black', 'Team'],
    ),
  ]),

  // ── Tab 5: Identity ────────────────────────────────────────────────────────
  AttrGroup(tabLabel: 'Identity', attrs: [
    AttrDef(key: 'fname',        label: 'First Name',    type: AttrType.text),
    AttrDef(key: 'lname',        label: 'Last Name',     type: AttrType.text),
    AttrDef(key: 'JerseyNumber', label: 'Jersey #',      type: AttrType.numeric, min: 0, max: 99),
    AttrDef(
      key: 'Position', label: 'Position', type: AttrType.dropdown,
      options: ['QB', 'K', 'P', 'WR', 'CB', 'FS', 'SS', 'RB', 'FB', 'TE', 'OLB', 'ILB', 'C', 'G', 'T', 'DT', 'DE'],
    ),
    AttrDef(key: 'College',      label: 'College',       type: AttrType.dropdown),
    AttrDef(key: 'DOB',          label: 'Date of Birth', type: AttrType.datePicker),
    AttrDef(key: 'YearsPro',     label: 'Years Pro',     type: AttrType.numeric, min: 0, max: 99),
    AttrDef(
      key: 'Hand', label: 'Handedness', type: AttrType.dropdown,
      options: ['Right', 'Left'],
    ),
    AttrDef(key: 'Weight', label: 'Weight', type: AttrType.slider, min: 100, max: 400),
    AttrDef(
      key: 'Height', label: 'Height', type: AttrType.dropdown,
      // options resolved at runtime from kHeightOptions (not const)
    ),
    AttrDef(key: 'Photo', label: 'Photo',    type: AttrType.mappedId),
    AttrDef(key: 'PBP',   label: 'PBP Name', type: AttrType.mappedId),
  ]),
];
