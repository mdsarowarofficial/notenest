import 'package:flutter/material.dart';

import '../../data/attachment_store.dart';
import '../../theme/nest_theme.dart';

/// The ways a note can start. Requirement 5 and Requirement 8.
///
/// Recording and dictation are deliberately separate choices rather than one
/// "voice" option. They are not two steps of the same thing: recording keeps
/// an audio file you can play back, dictation writes words into the note. The
/// device's recogniser cannot read an audio file back on Android, so one
/// cannot be turned into the other afterwards and the student has to pick
/// before the lecture, not after.
enum CaptureKind { text, photo, pdf, record, dictate }

Future<CaptureKind?> showCaptureSheet(BuildContext context) {
  return showModalBottomSheet<CaptureKind>(
    context: context,
    backgroundColor: NestColor.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const _CaptureSheet(),
  );
}

class _CaptureSheet extends StatelessWidget {
  const _CaptureSheet();

  @override
  Widget build(BuildContext context) {
    // A recording is a file, and the browser build has nowhere to keep files,
    // so that is said here rather than two screens later.
    final filesWork = AttachmentStore.isSupported;

    final options = <_CaptureOption>[
      const _CaptureOption(
        CaptureKind.text,
        'Write a note',
        'Start with a blank page',
        Icons.edit_rounded,
      ),
      _CaptureOption(
        CaptureKind.photo,
        'Photograph handwriting',
        'Crop and straighten a page',
        Icons.photo_camera_rounded,
        badge: filesWork ? null : 'PHONE',
      ),
      _CaptureOption(
        CaptureKind.pdf,
        'Add a PDF',
        'Slides, books, question papers',
        Icons.picture_as_pdf_rounded,
        badge: filesWork ? null : 'PHONE',
      ),
      _CaptureOption(
        CaptureKind.record,
        'Record the lecture',
        'Keeps the audio to play back later',
        Icons.mic_rounded,
        badge: filesWork ? null : 'PHONE',
      ),
      const _CaptureOption(
        CaptureKind.dictate,
        'Dictate into text',
        'Speak and it becomes a study note',
        Icons.graphic_eq_rounded,
      ),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: NestColor.rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Add to your notebook',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 18),
            for (final o in options)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(NestRadius.tile),
                  onTap: () => Navigator.pop(context, o.kind),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: NestColor.paper,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(
                            o.icon,
                            size: 20,
                            color: o.badge == null
                                ? NestColor.pen
                                : NestColor.inkFaint,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      o.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall,
                                    ),
                                  ),
                                  if (o.badge != null) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: NestColor.paper,
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: Text(o.badge!,
                                          style: nestEyebrow.copyWith(
                                              fontSize: 9.5)),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                o.subtitle,
                                style:
                                    Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: NestColor.inkFaint),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CaptureOption {
  const _CaptureOption(
    this.kind,
    this.title,
    this.subtitle,
    this.icon, {
    this.badge,
  });

  final CaptureKind kind;
  final String title;
  final String subtitle;
  final IconData icon;

  /// A short word shown beside the title when the option is limited on this
  /// platform. Null when it works here.
  final String? badge;
}
