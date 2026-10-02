import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/attachment_store.dart';
import '../../models/attachment.dart';
import '../../theme/nest_theme.dart';

/// Full-screen look at photographed pages, with pinch to zoom.
///
/// Handwriting is often small, so zoom is the point of this screen rather than
/// a nicety.
class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({
    super.key,
    required this.attachments,
    this.initialIndex = 0,
  });

  final List<Attachment> attachments;
  final int initialIndex;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NestColor.ink,
      appBar: AppBar(
        backgroundColor: NestColor.ink,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.attachments.length == 1
              ? 'Page'
              : 'Page ${_index + 1} of ${widget.attachments.length}',
          style: const TextStyle(fontSize: 16, color: Colors.white),
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.attachments.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => FutureBuilder<String>(
          future: AttachmentStore.fullPath(widget.attachments[i].storedName),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: Image.file(
                  File(snapshot.data!),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) => const Center(
                    child: Text(
                      'This page could not be opened.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
