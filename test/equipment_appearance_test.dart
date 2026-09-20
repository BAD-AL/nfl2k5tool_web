import 'package:test/test.dart';
import 'package:nfl2k5tool_web/data/equipment_appearance.dart';

void main() {
  group('equipmentImageFilename', () {
    test('FaceMask uses the raw value as the filename (no prefix)', () {
      expect(equipmentImageFilename('FaceMask', 'FaceMask14'), 'FaceMask14');
    });

    test('LeftShoe/RightShoe use the raw value as the filename', () {
      expect(equipmentImageFilename('LeftShoe', 'Shoe3'), 'Shoe3');
      expect(equipmentImageFilename('RightShoe', 'Taped'), 'Taped');
    });

    test('LeftGlove/RightGlove prepend "Glove"', () {
      expect(equipmentImageFilename('LeftGlove', 'Type1'), 'GloveType1');
      expect(equipmentImageFilename('RightGlove', 'None'), 'GloveNone');
    });

    test('LeftWrist/RightWrist prepend "Wrist"', () {
      expect(equipmentImageFilename('LeftWrist', 'SingleWhite'), 'WristSingleWhite');
    });

    test('LeftElbow/RightElbow prepend "Elbow"', () {
      expect(equipmentImageFilename('LeftElbow', 'White'), 'ElbowWhite');
    });

    test('NeckRoll prepends "NeckRoll"', () {
      expect(equipmentImageFilename('NeckRoll', 'Collar'), 'NeckRollCollar');
    });

    test('a non-image-backed field (Skin) returns null', () {
      expect(equipmentImageFilename('Skin', 'Skin14'), isNull);
    });

    test('an unrelated field returns null', () {
      expect(equipmentImageFilename('BodyType', 'Normal'), isNull);
    });
  });

  group('skinColorHex / skinTextColor', () {
    test('a known light skin value gets its color and dark text', () {
      expect(skinColorHex('Skin1'), '#F2D4CA');
      expect(skinTextColor('Skin1'), '#000000');
    });

    test('a known dark skin value gets its color and light text', () {
      expect(skinColorHex('Skin22'), '#482D26');
      expect(skinTextColor('Skin22'), '#FFFFFF');
    });

    test('an unused skin value (e.g. Skin7) falls back to black with white text', () {
      expect(skinColorHex('Skin7'), '#000000');
      expect(skinTextColor('Skin7'), '#FFFFFF');
    });

    test('every Skin1..Skin22 value resolves to a 7-character hex color', () {
      for (int i = 1; i <= 22; i++) {
        final hex = skinColorHex('Skin$i');
        expect(hex, matches(RegExp(r'^#[0-9A-Fa-f]{6}$')),
            reason: 'Skin$i produced an invalid hex color: $hex');
      }
    });
  });
}
