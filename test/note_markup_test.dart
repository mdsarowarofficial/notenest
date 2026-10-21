import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notenest/data/note_format.dart';
import 'package:notenest/models/note_markup.dart';

TextEditingValue v(String text, int start, [int? end]) => TextEditingValue(
      text: text,
      selection: TextSelection(baseOffset: start, extentOffset: end ?? start),
    );

void main() {
  group('parseMarkup', () {
    test('reads each kind of line', () {
      final blocks = parseMarkup(
        '# Title\n## Sub\n- one\n* two\n1. first\n- [ ] todo\n- [x] done\nplain\n\nlast',
      );
      expect(blocks.map((b) => b.kind), [
        BlockKind.heading,
        BlockKind.heading,
        BlockKind.bullet,
        BlockKind.bullet,
        BlockKind.numbered,
        BlockKind.check,
        BlockKind.check,
        BlockKind.paragraph,
        BlockKind.blank,
        BlockKind.paragraph,
      ]);
      expect(blocks[0].level, 1);
      expect(blocks[1].level, 2);
      expect(blocks[5].checked, isFalse);
      expect(blocks[6].checked, isTrue);
      expect(blocks[4].number, 1);
      expect(blocks[2].text, 'one');
    });

    test('a hash with no space is plain text', () {
      expect(parseMarkup('#hashtag').single.kind, BlockKind.paragraph);
    });
  });

  group('parseInline', () {
    test('splits bold, italic and highlight', () {
      final runs = parseInline('a **b** c *d* ==e== f');
      expect(runs.map((r) => r.text), ['a ', 'b', ' c ', 'd', ' ', 'e', ' f']);
      expect(runs[1].bold, isTrue);
      expect(runs[3].italic, isTrue);
      expect(runs[5].mark, isTrue);
    });

    test('leaves snake_case and lone stars alone', () {
      expect(parseInline('use snake_case_names').length, 1);
      expect(parseInline('2 * 3 * 4').length, 1);
    });

    test('underscore italic works at word edges', () {
      final runs = parseInline('say _hello_ now');
      expect(runs[1].italic, isTrue);
      expect(runs[1].text, 'hello');
    });
  });

  group('plainText and checks', () {
    test('strips the marks', () {
      expect(plainText('# Hi\n- **a**\n- [x] b'), 'Hi\n• a\n☑ b');
    });

    test('toggleCheck flips only that line', () {
      const body = '- [ ] a\n- [x] b\nplain';
      expect(toggleCheck(body, 0), '- [x] a\n- [x] b\nplain');
      expect(toggleCheck(body, 1), '- [ ] a\n- [ ] b\nplain');
      expect(toggleCheck(body, 2), body);
      expect(toggleCheck(body, 9), body);
    });

    test('checkProgress counts', () {
      final p = checkProgress('- [ ] a\n- [x] b\n- [x] c\nx');
      expect(p.done, 2);
      expect(p.total, 3);
    });
  });

  group('toggleInline', () {
    test('wraps a selection and unwraps it again', () {
      final bold = toggleInline(v('hello world', 6, 11), '**');
      expect(bold.text, 'hello **world**');
      expect(bold.selection.start, 8);
      final back = toggleInline(bold, '**');
      expect(back.text, 'hello world');
    });

    test('with no selection leaves the cursor between the marks', () {
      final r = toggleInline(v('ab', 1), '*');
      expect(r.text, 'a**b');
      expect(r.selection.baseOffset, 2);
    });
  });

  group('toggleLineStyle', () {
    test('adds and removes a bullet', () {
      final added = toggleLineStyle(v('one\ntwo', 5), LineStyle.bullet);
      expect(added.text, 'one\n- two');
      final removed = toggleLineStyle(added, LineStyle.bullet);
      expect(removed.text, 'one\ntwo');
    });

    test('numbers several selected lines', () {
      final r = toggleLineStyle(v('a\nb\nc', 0, 5), LineStyle.numbered);
      expect(r.text, '1. a\n2. b\n3. c');
    });

    test('a checklist replaces a bullet', () {
      final r = toggleLineStyle(v('- item', 3), LineStyle.check);
      expect(r.text, '- [ ] item');
    });

    test('heading cycles through three levels then off', () {
      var t = v('Title', 2);
      t = toggleLineStyle(t, LineStyle.heading);
      expect(t.text, '# Title');
      t = toggleLineStyle(t, LineStyle.heading);
      expect(t.text, '## Title');
      t = toggleLineStyle(t, LineStyle.heading);
      expect(t.text, '### Title');
      t = toggleLineStyle(t, LineStyle.heading);
      expect(t.text, 'Title');
    });
  });

  group('ListContinueFormatter', () {
    const f = ListContinueFormatter();

    TextEditingValue enter(String before, String after) => f.formatEditUpdate(
          v(before, before.length),
          v(after, after.length),
        );

    test('Enter on a bullet starts the next bullet', () {
      final r = enter('- one', '- one\n');
      expect(r.text, '- one\n- ');
      expect(r.selection.baseOffset, 8);
    });

    test('Enter on a checkbox starts an unticked one', () {
      expect(enter('- [x] done', '- [x] done\n').text, '- [x] done\n- [ ] ');
    });

    test('Enter on a numbered line counts on', () {
      expect(enter('1. a', '1. a\n').text, '1. a\n2. ');
    });

    test('Enter on an empty item ends the list', () {
      final r = enter('- one\n- ', '- one\n- \n');
      expect(r.text, '- one\n');
      expect(r.selection.baseOffset, 6);
    });

    test('Enter on plain text is untouched', () {
      expect(enter('hello', 'hello\n').text, 'hello\n');
    });
  });
}
