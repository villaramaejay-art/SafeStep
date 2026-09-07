import 'package:flutter_test/flutter_test.dart';
import 'package:safe_step/utils/text_format.dart';

/// "contact(s)" is the mark of software nobody finished, and it was in five
/// places. These keep it out.
void main() {
  group('TextFormat.count', () {
    test('one is singular', () {
      expect(TextFormat.count(1, 'contact'), '1 contact');
      expect(TextFormat.count(1, 'alert'), '1 alert');
    });

    test('anything else is plural', () {
      expect(TextFormat.count(0, 'contact'), '0 contacts');
      expect(TextFormat.count(2, 'contact'), '2 contacts');
      expect(TextFormat.count(21, 'alert'), '21 alerts');
    });

    test('an irregular plural can be given', () {
      expect(TextFormat.count(1, 'entry', 'entries'), '1 entry');
      expect(TextFormat.count(3, 'entry', 'entries'), '3 entries');
    });

    test('the noun alone matches the number', () {
      expect(TextFormat.noun(1, 'zone'), 'zone');
      expect(TextFormat.noun(2, 'zone'), 'zones');
    });
  });
}
