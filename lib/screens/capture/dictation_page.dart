import 'package:flutter/material.dart';

import '../../data/dictation.dart';
import '../../models/transcript.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_level_meter.dart';

/// Speaks a lecture straight into text. Requirement 8.2.
///
/// The device's own recogniser is used, so nothing is uploaded anywhere. It is
/// built for short commands, which is why [Dictation] restarts it whenever the
/// speaker pauses; the counter at the bottom shows how often that has
/// happened, because a word spoken during a handover is the one thing this
/// approach can lose.
///
/// Returns the transcript to whoever pushed this screen, or null if nothing
/// was said.
class DictationPage extends StatefulWidget {
  const DictationPage({super.key});

  @override
  State<DictationPage> createState() => _DictationPageState();
}

class _DictationPageState extends State<DictationPage> {
  final _dictation = Dictation();
  final _scroll = ScrollController();

  int _lastLength = 0;

  @override
  void initState() {
    super.initState();
    _dictation.addListener(_followText);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _dictation.prepare();
    });
  }

  @override
  void dispose() {
    _dictation.removeListener(_followText);
    _dictation.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the newest words in view, the way a notepad scrolls under a pen.
  void _followText() {
    final length = _dictation.text.length;
    if (length == _lastLength) return;
    _lastLength = length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _toggle() async {
    if (_dictation.wanted) {
      await _dictation.stop();
    } else {
      await _dictation.start();
    }
  }

  Future<void> _use() async {
    await _dictation.stop();
    if (!mounted) return;
    Navigator.pop(context, _dictation.text);
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: NestColor.card,
        title: const Text('Clear the transcript?'),
        content: const Text(
          'Everything dictated so far will be removed. The microphone stays '
          'on, so you can start again straight away.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NestColor.redPen),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) _dictation.reset();
  }

  Future<void> _pickLanguage() async {
    final locales = _dictation.locales;
    if (locales.isEmpty) return;

    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: NestColor.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
          children: [
            const Text('RECOGNITION LANGUAGE', style: nestEyebrow),
            const SizedBox(height: 6),
            Text(
              'These are the languages this device can recognise. Adding more '
              'is done in the phone speech settings, not here.',
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            for (final locale in locales)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(locale.name, style: const TextStyle(fontSize: 14)),
                trailing: locale.id == _dictation.localeId
                    ? const Icon(Icons.check_rounded,
                        size: 18, color: NestColor.pen)
                    : null,
                onTap: () => Navigator.pop(sheetContext, locale.id),
              ),
          ],
        ),
      ),
    );

    if (picked == null || !mounted) return;
    final wasListening = _dictation.wanted;
    await _dictation.stop();
    _dictation.localeId = picked;
    if (wasListening) await _dictation.start();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _dictation,
      builder: (context, _) {
        final listening = _dictation.wanted;

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Dictate',
              style: TextStyle(
                fontFamily: NestFont.display,
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: NestColor.ink,
              ),
            ),
            actions: [
              if (_dictation.locales.isNotEmpty)
                IconButton(
                  tooltip: 'Recognition language',
                  icon: const Icon(Icons.language_rounded),
                  onPressed: _pickLanguage,
                ),
              if (!_dictation.isEmpty)
                IconButton(
                  tooltip: 'Clear transcript',
                  icon: const Icon(Icons.backspace_outlined),
                  onPressed: _clear,
                ),
              const SizedBox(width: 4),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
              child: Column(
                children: [
                  if (_dictation.error != null)
                    _Notice(text: _dictation.error!),
                  Expanded(child: _transcript(context, listening)),
                  const SizedBox(height: 14),
                  _Footer(
                    words: wordCount(_dictation.text),
                    restarts: _dictation.restarts,
                    listening: listening,
                    live: _dictation.isListening,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      NestMicPulse(
                        level: _dictation.level,
                        active: _dictation.isListening,
                        child: SizedBox(
                          width: 62,
                          height: 62,
                          child: FilledButton(
                            onPressed: _toggle,
                            style: FilledButton.styleFrom(
                              shape: const CircleBorder(),
                              padding: EdgeInsets.zero,
                              backgroundColor: listening
                                  ? NestColor.redPen
                                  : NestColor.pen,
                            ),
                            child: Icon(
                              listening
                                  ? Icons.stop_rounded
                                  : Icons.mic_rounded,
                              size: 26,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _dictation.isEmpty ? null : _use,
                          icon: const Icon(Icons.arrow_forward_rounded,
                              size: 18),
                          label: const Text('Use this text'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _transcript(BuildContext context, bool listening) {
    if (_dictation.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              listening ? Icons.hearing_rounded : Icons.mic_none_rounded,
              size: 34,
              color: NestColor.inkFaint,
            ),
            const SizedBox(height: 16),
            Text(
              listening ? 'Listening…' : 'Tap the microphone and talk',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                listening
                    ? 'Words appear as the device recognises them. Pauses are '
                        'fine — it starts itself again.'
                    // Deliberately not "nothing leaves your phone". The
                    // recogniser belongs to the device, but on Android and in
                    // the browser it normally passes the audio on to the
                    // platform speech service — only an installed offline
                    // language pack keeps it local. Claiming otherwise would
                    // be a privacy promise the app cannot keep.
                    : 'The listening is done by the recogniser built into '
                        'this device. Unless it has an offline language pack, '
                        'that passes the audio on to the platform speech '
                        'service. You can fix the words on the next screen.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      controller: _scroll,
      child: Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 6),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(
              fontSize: 16.5,
              height: 1.6,
              color: NestColor.ink,
            ),
            children: [
              TextSpan(text: _dictation.committed.trim()),
              if (_dictation.partial.trim().isNotEmpty)
                TextSpan(
                  // In-flight words are drawn in pencil: the recogniser can
                  // still replace them, and showing them in the same ink as
                  // the rest would make the text look like it was rewriting
                  // itself.
                  text: ' ${_dictation.partial.trim()}',
                  style: const TextStyle(color: NestColor.inkFaint),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.words,
    required this.restarts,
    required this.listening,
    required this.live,
  });

  final int words;
  final int restarts;
  final bool listening;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final bits = <String>[
      '$words ${words == 1 ? 'WORD' : 'WORDS'}',
      if (restarts > 0) '$restarts RESTARTS',
    ];

    return Column(
      children: [
        Container(height: 1, color: NestColor.rule),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: live
                    ? NestColor.redPen
                    : listening
                        ? NestColor.highlight
                        : NestColor.inkFaint,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              live
                  ? 'LISTENING'
                  : listening
                      ? 'RESTARTING'
                      : 'STOPPED',
              style: nestEyebrow.copyWith(
                color: live ? NestColor.redPen : NestColor.inkFaint,
              ),
            ),
            const Spacer(),
            Text(bits.join('  ·  '), style: nestEyebrow),
          ],
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NestColor.o(NestColor.redPen, 0.08),
        borderRadius: BorderRadius.circular(NestRadius.tile),
        border: const Border(
          left: BorderSide(color: NestColor.redPen, width: 3),
        ),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
