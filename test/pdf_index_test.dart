import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:notenest/data/pdf_index.dart';
import 'package:pdf/widgets.dart' as pw;

Future<List<int>> makePdf(List<String> pages) async {
  final doc = pw.Document();
  for (final text in pages) {
    doc.addPage(pw.Page(build: (_) => pw.Text(text)));
  }
  return doc.save();
}

void main() {
  test('words inside a PDF come out of it', () async {
    final bytes = await makePdf([
      'Photosynthesis happens in the chloroplasts of a leaf.',
      'Second page talks about mitochondria.',
    ]);
    final text = extractPdfText(Uint8List.fromList(bytes));
    expect(text.toLowerCase(), contains('chloroplasts'));
    expect(text.toLowerCase(), contains('mitochondria'));
  });

  test('a file that is not a PDF gives an empty string, not an error', () {
    expect(extractPdfText(Uint8List.fromList([1, 2, 3, 4])), '');
  });

  test('the snippet is centred on the match', () {
    const text =
        'Aaaa bbbb cccc dddd eeee ffff gggg hhhh. The mitochondria is the '
        'powerhouse of the cell and makes ATP. Iiii jjjj kkkk llll mmmm.';
    final s = pdfSnippet(text, ['mitochondria'])!;
    expect(s, contains('mitochondria'));
    expect(s.startsWith('… '), isTrue);
    expect(s.endsWith(' …'), isTrue);
  });

  test('no snippet when nothing matches', () {
    expect(pdfSnippet('hello world', ['zebra']), isNull);
  });

  test('the first matching term is used', () {
    expect(pdfSnippet('alpha beta gamma', ['gamma', 'alpha']), contains('gamma'));
  });
}
