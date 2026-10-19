import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/doc_paginator.dart';
import '../../data/document_service.dart';
import '../../data/page_renderer.dart';
import '../../models/doc_text.dart';
import '../../theme/nest_theme.dart';
import 'doc_page_sheet.dart';

/// PDF to Word, and Word to PDF.
///
/// Both directions go through [DocBlock]s, so the screen only has to know
/// which way round it is. What it will not do is pretend: the limits are
/// written on the screen itself, before the student picks a file, because
/// finding out afterwards that the tables are gone is worse than being told.
class ConvertPage extends StatefulWidget {
  const ConvertPage({super.key});

  @override
  State<ConvertPage> createState() => _ConvertPageState();
}

class _ConvertPageState extends State<ConvertPage> {
  final _pageKey = GlobalKey();

  PickedDocument? _picked;
  List<DocBlock>? _blocks;
  List<List<DocBlock>>? _pages;

  bool _busy = false;
  String? _error;

  /// Which page is on screen while a PDF is being assembled.
  ///
  /// Each page has to be genuinely painted to be captured, so exporting walks
  /// through them one at a time and the student watches it happen. That is not
  /// a progress animation — it is the work.
  int? _rendering;

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final picked = await DocumentService.pickDocument();
      final blocks = picked.kind == PickedKind.pdf
          ? DocumentService.blocksFromPdf(picked.bytes)
          : DocumentService.blocksFromDocx(picked.bytes);

      setState(() {
        _picked = picked;
        _blocks = blocks;
        _pages = picked.kind == PickedKind.docx
            ? paginateBlocks(blocks)
            : null;
        _busy = false;
      });
    } on DocumentException catch (e) {
      setState(() {
        _busy = false;
        if (e.error != DocumentError.cancelled) _error = e.message;
      });
    } catch (_) {
      setState(() {
        _busy = false;
        _error = 'That file could not be read.';
      });
    }
  }

  Future<void> _saveAsWord() async {
    final picked = _picked;
    final blocks = _blocks;
    if (picked == null || blocks == null || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final bytes = DocumentService.buildDocx(blocks);
      final shared =
          await DocumentService.shareDocx(bytes, '${picked.stem}.docx');
      if (!mounted) return;
      setState(() => _busy = false);
      if (shared) _say('${picked.stem}.docx sent');
    } on DocumentException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'The Word file could not be made.';
        });
      }
    }
  }

  Future<void> _saveAsPdf() async {
    final picked = _picked;
    final pages = _pages;
    if (picked == null || pages == null || pages.isEmpty || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final shots = <Uint8List>[];
      for (var i = 0; i < pages.length; i++) {
        setState(() => _rendering = i);
        // capture() waits for the frame itself, so the page on screen is the
        // one that gets photographed.
        shots.add(await PageRenderer.capture(_pageKey));
        if (!mounted) return;
      }

      setState(() => _rendering = null);
      final bytes = await DocumentService.pdfFromPageImages(shots);
      final shared =
          await DocumentService.sharePdf(bytes, '${picked.stem}.pdf');
      if (!mounted) return;
      setState(() => _busy = false);
      if (shared) _say('${picked.stem}.pdf sent');
    } on DocumentException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _rendering = null;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _rendering = null;
          _error = 'The PDF could not be made.';
        });
      }
    }
  }

  void _say(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final picked = _picked;
    final blocks = _blocks;
    final pages = _pages;

    // The page currently being photographed, or page one as a preview.
    final sheetIndex = _rendering ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Convert a file')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 30),
        children: [
          if (picked == null) ...[
            const _WhatThisDoes(),
            const SizedBox(height: 20),
          ],

          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: NestColor.o(NestColor.redPen, 0.08),
                borderRadius: BorderRadius.circular(NestRadius.tile),
              ),
              child: Text(
                _error!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: NestColor.redPen),
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (picked != null && blocks != null) ...[
            _Summary(
              picked: picked,
              blocks: blocks,
              pageCount: pages?.length,
            ),
            const SizedBox(height: 18),
          ],

          // A Word file turns into pages, and those pages are what the PDF
          // holds, so they are shown rather than described.
          if (pages != null && pages.isNotEmpty) ...[
            Text(
              _rendering == null
                  ? 'PAGE 1 OF ${pages.length}'
                  : 'RENDERING PAGE ${_rendering! + 1} OF ${pages.length}',
              style: nestEyebrow,
            ),
            const SizedBox(height: 8),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 330),
                child: AspectRatio(
                  aspectRatio: PageRenderer.a4Ratio,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: NestColor.o(NestColor.ink, 0.16),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: RepaintBoundary(
                      key: _pageKey,
                      child: DocPageSheet(
                        blocks: pages[sheetIndex.clamp(0, pages.length - 1)],
                        pageNumber: sheetIndex + 1,
                        pageCount: pages.length,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],

          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.folder_open_rounded, size: 18),
            label: Text(picked == null ? 'Pick a PDF or Word file' : 'Pick another'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
          ),

          if (picked != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy
                    ? null
                    : picked.kind == PickedKind.pdf
                        ? _saveAsWord
                        : _saveAsPdf,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.ios_share_rounded, size: 18),
                label: Text(
                  _busy
                      ? 'Working…'
                      : picked.kind == PickedKind.pdf
                          ? 'Save as Word (.docx)'
                          : 'Save as PDF',
                ),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 54)),
              ),
            ),
          ],

          const SizedBox(height: 20),
          const _Limits(),
        ],
      ),
    );
  }
}

class _WhatThisDoes extends StatelessWidget {
  const _WhatThisDoes();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NestColor.card,
        borderRadius: BorderRadius.circular(NestRadius.card),
        boxShadow: NestShadow.resting,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 4, height: 16, color: NestColor.pen),
              const SizedBox(width: 8),
              Text('BOTH WAYS',
                  style: nestEyebrow.copyWith(color: NestColor.pen)),
            ],
          ),
          const SizedBox(height: 12),
          const _Direction(
            from: 'PDF',
            to: 'Word',
            line: 'Pulls the text out and gives it back as a .docx you can '
                'edit. Headings are guessed from how the lines are written.',
          ),
          const SizedBox(height: 10),
          const _Direction(
            from: 'Word',
            to: 'PDF',
            line: 'Lays the text out on A4 pages and exports them. You see '
                'the pages before you export.',
          ),
        ],
      ),
    );
  }
}

class _Direction extends StatelessWidget {
  const _Direction({required this.from, required this.to, required this.line});

  final String from;
  final String to;
  final String line;

  @override
  Widget build(BuildContext context) {
    // The label sits above its line: a fixed-width label column ran out of
    // room at larger text sizes and overlapped the description.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(from, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_right_alt_rounded,
                size: 16, color: NestColor.inkFaint),
            const SizedBox(width: 4),
            Text(to, style: Theme.of(context).textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: 2),
        Text(line, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.picked,
    required this.blocks,
    required this.pageCount,
  });

  final PickedDocument picked;
  final List<DocBlock> blocks;
  final int? pageCount;

  @override
  Widget build(BuildContext context) {
    final headings = blocks.where((b) => b.isHeading).length;
    final lists = blocks.where((b) => b.isListItem).length;

    final parts = <String>[
      '${wordsIn(blocks)} words',
      if (headings > 0) '$headings ${headings == 1 ? 'heading' : 'headings'}',
      if (lists > 0) '$lists list ${lists == 1 ? 'item' : 'items'}',
      if (pageCount != null) '$pageCount ${pageCount == 1 ? 'page' : 'pages'}',
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NestColor.paper,
        borderRadius: BorderRadius.circular(NestRadius.tile),
      ),
      child: Row(
        children: [
          Icon(
            picked.kind == PickedKind.pdf
                ? Icons.picture_as_pdf_rounded
                : Icons.article_rounded,
            size: 20,
            color: NestColor.pen,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  picked.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  parts.join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Said before the file is picked, not after it disappoints.
class _Limits extends StatelessWidget {
  const _Limits();

  @override
  Widget build(BuildContext context) {
    const limits = [
      'Text, headings and lists travel. Tables keep their words but lose '
          'their shape; images, columns and footnotes are dropped.',
      'A scanned PDF has no text in it, only pictures of text. Reading those '
          'needs OCR, which NoteNest does not do — it will say so rather than '
          'hand back an empty file.',
      'A Word → PDF export holds each page as an image, which is how Bengali '
          'comes out right. The text in it cannot be selected.',
      'An old .doc is a different format from .docx. Open it in Word and save '
          'it again first.',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('WHAT IT WILL AND WILL NOT DO', style: nestEyebrow),
        const SizedBox(height: 8),
        for (final line in limits)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 5),
                  child: Icon(Icons.circle, size: 4, color: NestColor.inkFaint),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child:
                      Text(line, style: Theme.of(context).textTheme.bodySmall),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
