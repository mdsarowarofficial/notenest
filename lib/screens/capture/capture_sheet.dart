import 'package:flutter/material.dart';

import '../../theme/nest_theme.dart';

/// The four ways a note can start. Requirement 5.
///
/// Text, photo and PDF all open real screens. Voice is the one still to come.
enum CaptureKind { text, photo, pdf, voice }

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

  static const _options = <_CaptureOption>[
    _CaptureOption(CaptureKind.text, 'Write a note',
        'Start with a blank page', Icons.edit_rounded, true),
    _CaptureOption(CaptureKind.photo, 'Photograph handwriting',
        'Crop and straighten a page', Icons.photo_camera_rounded, true),
    _CaptureOption(CaptureKind.pdf, 'Add a PDF',
        'Slides, books, question papers', Icons.picture_as_pdf_rounded, true),
    _CaptureOption(CaptureKind.voice, 'Record the lecture',
        'Turns speech into a study note', Icons.mic_rounded, false),
  ];

  @override
  Widget build(BuildContext context) {
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
            for (final o in _options)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(NestRadius.tile),
                  onTap: () => Navigator.pop(context, o.kind),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
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
                            color: o.ready
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
                                  Text(
                                    o.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                  ),
                                  if (!o.ready) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: NestColor.paper,
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: Text('SOON',
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
      this.kind, this.title, this.subtitle, this.icon, this.ready);

  final CaptureKind kind;
  final String title;
  final String subtitle;
  final IconData icon;

  /// Whether the option opens a real screen yet.
  final bool ready;
}
