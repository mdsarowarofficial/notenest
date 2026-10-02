import 'dart:io';

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../data/attachment_store.dart';
import '../../models/attachment.dart';
import '../../theme/nest_theme.dart';

/// Reads a PDF inside the app, with page navigation. Requirement 5.3.
class PdfViewerPage extends StatefulWidget {
  const PdfViewerPage({super.key, required this.attachment});

  final Attachment attachment;

  @override
  State<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<PdfViewerPage> {
  final _controller = PdfViewerController();

  int _page = 1;
  int _pages = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.attachment.fileName,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, color: NestColor.ink),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<String>(
              future:
                  AttachmentStore.fullPath(widget.attachment.storedName),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return SfPdfViewer.file(
                  File(snapshot.data!),
                  controller: _controller,
                  onDocumentLoaded: (details) => setState(
                    () => _pages = details.document.pages.count,
                  ),
                  onPageChanged: (details) =>
                      setState(() => _page = details.newPageNumber),
                );
              },
            ),
          ),
          if (_pages > 0)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              decoration: const BoxDecoration(
                color: NestColor.card,
                border: Border(
                  top: BorderSide(color: NestColor.rule),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous page',
                      onPressed:
                          _page > 1 ? _controller.previousPage : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Text(
                        'PAGE $_page OF $_pages',
                        textAlign: TextAlign.center,
                        style: nestEyebrow,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next page',
                      onPressed:
                          _page < _pages ? _controller.nextPage : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
