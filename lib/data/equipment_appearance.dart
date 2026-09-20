// Visual cues for Appearance-tab equipment fields, ported from the old
// WinForms UI's PictureChooser logic (OLD_UI/Forms/PlayerEditForm.cs).

/// Maps an appearance field key to the prefix used when building its
/// equipment-image filename. FaceMask/Shoe use the raw value as the
/// filename; Glove/Wrist/Elbow/NeckRoll prepend their type name (e.g.
/// LeftGlove='Type1' -> 'GloveType1.jpg'). A key with no entry here isn't
/// image-backed at all (e.g. Skin — see [skinColorHex] instead).
const Map<String, String> kEquipmentImagePrefix = {
  'FaceMask': '',
  'LeftShoe': '',
  'RightShoe': '',
  'LeftGlove': 'Glove',
  'RightGlove': 'Glove',
  'LeftWrist': 'Wrist',
  'RightWrist': 'Wrist',
  'LeftElbow': 'Elbow',
  'RightElbow': 'Elbow',
  'NeckRoll': 'NeckRoll',
};

/// Returns the equipment-image filename (no extension, case as constructed
/// — PlayerDataCache.getEquipmentImage matches case-insensitively) for
/// [fieldKey]'s [value], or null if [fieldKey] has no image asset (use
/// [skinColorHex] for Skin instead).
String? equipmentImageFilename(String fieldKey, String value) {
  final prefix = kEquipmentImagePrefix[fieldKey];
  if (prefix == null) return null;
  return '$prefix$value';
}

/// Hex color for a Skin value like 'Skin14', ported from the old WinForms
/// UI's hardcoded skin-tone table — Skin never had an image asset, it was
/// always a colored label. Values absent here (Skin7/8/15/16 — "no one has
/// these" per the original code's own comment) fall back to black.
const Map<String, String> kSkinColors = {
  'Skin1': '#F2D4CA', 'Skin9': '#F2D4CA', 'Skin17': '#F2D4CA',
  'Skin2': '#C88C84', 'Skin18': '#C88C84',
  'Skin3': '#8E5C4F',
  'Skin4': '#7B4B41',
  'Skin5': '#653D35',
  'Skin6': '#4E2F2A',
  'Skin10': '#A36A5F',
  'Skin11': '#C68D82',
  'Skin12': '#653D35',
  'Skin13': '#7B4B41',
  'Skin14': '#643E31',
  'Skin19': '#653D35',
  'Skin20': '#663E35',
  'Skin21': '#5A3730',
  'Skin22': '#482D26',
};

/// Skin values light enough to need dark (not white) text on their swatch —
/// mirrors the old UI's per-swatch foreground color choice exactly.
const Set<String> kLightSkinValues = {'Skin1', 'Skin9', 'Skin17'};

/// Hex color for [skinValue] (e.g. 'Skin14'), defaulting to black for the
/// handful of values the original game never actually used.
String skinColorHex(String skinValue) => kSkinColors[skinValue] ?? '#000000';

/// Text color ('#000000' or '#FFFFFF') that reads clearly against
/// [skinColorHex]'s swatch for [skinValue].
String skinTextColor(String skinValue) =>
    kLightSkinValues.contains(skinValue) ? '#000000' : '#FFFFFF';
