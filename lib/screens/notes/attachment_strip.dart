import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/attachment_store.dart';
import '../../data/note_repository.dart';
import '../../models/attachment.dart';
import '../../models/note.dart';
import '../../theme/nest_theme.dart';
import '../viewer/image_viewer.dart';
import '../viewer/pdf_viewer.dart';

/// The files attached to a note, shown as a row of thumbnails.
///
/// The same strip appears while editing and while reading; only the delete
/// control differs, so a note looks the same in both places.
class AttachmentStrip extends StatefulWidget {
  const AttachmentStrip({
    super.key,
    required this.note,
    this.editable = false,
  });

  final Note note;
  final bool editable;

  @override
  State<AttachmentStrip> createState() => AttachmentStripState();
}

class AttachmentStripState extends State<AttachmentStrip> {
  final _repo = NoteRepository.instance;

  late Future<List<Attachment>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = widget.note.id == null
        ? Future.value(const <Attachment>[])
        : _repo.attachmentsFor(widget.note.id!);
  }

  /// Called by the editor after a new file is attached.
  void reload() => setState(_load);

  Future<void> _remove(Attachment attachment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: NestColor.card,
        title: const Text('Remove this file?'),
        content: Text(
          '${attachment.fileName} will be deleted from the note. This cannot '
          'be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NestColor.redPen),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _repo.removeAttachment(attachment);
    reload();
  }

  void _open(List<Attachment> all, Attachment attachment) {
    if (attachment.type == AttachmentType.pdf) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PdfViewerPage(attachment: attachment),
        ),
      );
      return;
    }
    final images =
        all.where((a) => a.type == AttachmentType.image).toList();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageViewerPage(
          attachments: images,
          initialIndex: images.indexOf(attachment),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Attachment>>(
      future: _future,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <Attachment>[];
        if (items.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('ATTACHED', style: nestEyebrow),
                const SizedBox(width: 8),
                Text('${items.length}', style: nestEyebrow),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 118,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) => _Thumb(
                  attachment: items[i],
                  editable: widget.editable,
                  onOpen: () => _open(items, items[i]),
                  onRemove: () => _remove(items[i]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.attachment,
    required this.editable,
    required this.onOpen,
    required this.onRemove,
  });

  final Attachment attachment;
  final bool editable;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: onOpen,
          child: Container(
            width: 96,
            height: 118,
            decoration: BoxDecoration(
              color: NestColor.paper,
              borderRadius: BorderRadius.circular(NestRadius.tile),
              border: Border.all(color: NestColor.rule),
            ),
            clipBehavior: Clip.antiAlias,
            child: attachment.type == AttachmentType.image
                ? _ImageThumb(storedName: attachment.storedName)
                : _PdfThumb(attachment: attachment),
          ),
        ),
        if (editable)
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: NestColor.o(NestColor.ink, 0.65),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded,
                    size: 14, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}

class _ImageThumb extends StatelessWidget {
  const _ImageThumb({required this.storedName});

  final String storedName;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: AttachmentStore.fullPath(storedName),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return Image.file(
          File(snapshot.data!),
          fit: BoxFit.cover,
          width: 96,
          height: 118,
          errorBuilder: (context, error, stack) => const Center(
            child: Icon(Icons.broken_image_rounded,
                color: NestColor.inkFaint),
          ),
        );
      },
    );
  }
}

class _PdfThumb extends StatelessWidget {
  const _PdfThumb({required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.picture_as_pdf_rounded,
              size: 30, color: NestColor.redPen),
          const SizedBox(height: 8),
          Text(
            attachment.fileName,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, color: NestColor.ink),
          ),
          const SizedBox(height: 4),
          Text(
            attachment.readableSize,
            style: nestEyebrow.copyWith(fontSize: 9.5),
          ),
        ],
      ),
    );
  }
}
