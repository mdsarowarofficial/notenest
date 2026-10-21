import 'package:flutter/material.dart';

import '../../data/attachment_store.dart';
import '../../data/note_repository.dart';
import '../../data/voice_recorder.dart';
import '../../models/attachment.dart';
import '../../models/note.dart';
import '../../models/transcript.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_level_meter.dart';
import '../../l10n/strings.dart';

/// Records a lecture and files it against a note. Requirement 8.1.
///
/// The note is created first and the audio is written straight into the
/// attachment folder, so a long recording is never held in memory and the
/// file survives the app being killed mid-lecture.
class RecordPage extends StatefulWidget {
  const RecordPage({super.key, this.existing, this.initialSubjectId});

  /// Set when recording is started from inside an open note, so the audio is
  /// added to that note instead of a new one.
  final Note? existing;

  final int? initialSubjectId;

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  final _repo = NoteRepository.instance;
  final _recorder = VoiceRecorder();

  String? _message;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _begin();
    });
  }

  @override
  void dispose() {
    // VoiceRecorder.dispose() stops and deletes anything still recording, so
    // leaving this screen cannot orphan a file in the attachment folder.
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _begin() async {
    final failure = await _recorder.start();
    if (!mounted) return;
    if (failure != null) setState(() => _message = failure.message);
  }

  Future<void> _togglePause() async {
    if (_recorder.isRecording) {
      await _recorder.pause();
    } else if (_recorder.isPaused) {
      await _recorder.resume();
    } else {
      await _begin();
    }
  }

  Future<void> _discard() async {
    await _recorder.discard();
    if (mounted) Navigator.pop(context);
  }

  /// Which subject a new recording is filed under. Asked before the recorder
  /// stops, so closing the sheet changes nothing and the lecture carries on.
  /// Returns the subject's id, [_noSubject], or null if the sheet was closed.
  static const _noSubject = -1;

  Future<int?> _askSubject() {
    final subjects = _repo.subjects();
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: NestColor.card,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 4),
                child: Text(
                  tr('File this recording under'),
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              for (final s in subjects)
                ListTile(
                  leading: CircleAvatar(radius: 7, backgroundColor: s.color),
                  title: Text(s.name),
                  subtitle: Text(s.code),
                  onTap: () => Navigator.pop(sheetContext, s.id),
                ),
              ListTile(
                leading: const Icon(Icons.folder_off_outlined),
                title: Text(tr('No subject yet')),
                onTap: () => Navigator.pop(sheetContext, _noSubject),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;

    // A recording started from inside a note, or from a subject, already knows
    // where it belongs. Only a loose one needs asking.
    int? subjectId = widget.initialSubjectId;
    if (widget.existing == null &&
        subjectId == null &&
        _repo.subjects().isNotEmpty) {
      final picked = await _askSubject();
      if (picked == null || !mounted) return;
      subjectId = picked == _noSubject ? null : picked;
    }

    setState(() => _saving = true);

    final recording = await _recorder.stop();
    if (!mounted) return;

    if (recording == null) {
      setState(() {
        _saving = false;
        _message = tr('Nothing was recorded, so there is nothing to keep. Tap '
            'the microphone to start again.');
      });
      return;
    }

    // A recording needs a note to belong to: the open one if this was started
    // from inside a note, otherwise a fresh one.
    final note = widget.existing ??
        await _repo.createNote(
          title: tr('Lecture recording'),
          subjectId: subjectId,
        );

    await _repo.addAttachment(
      note: note,
      type: AttachmentType.audio,
      fileName: 'lecture-${formatClock(recording.duration)}.m4a',
      storedName: recording.storedName,
      sizeBytes: recording.sizeBytes,
      durationMs: recording.duration.inMilliseconds,
    );

    if (!mounted) return;
    Navigator.pop(context, _repo.noteById(note.id!) ?? note);
  }

  Future<bool> _confirmLeave() async {
    if (!_recorder.isActive) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: NestColor.card,
        title: Text(tr('Throw this recording away?')),
        content: Text(
          trp('{0} has been recorded and has not been saved to a note yet.', [formatClock(_recorder.elapsed)]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('Keep recording')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NestColor.redPen),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr('Throw away')),
          ),
        ],
      ),
    );
    return leave == true;
  }

  @override
  Widget build(BuildContext context) {
    final unsupported = !AttachmentStore.isSupported;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave()) await _discard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            tr('Record the lecture'),
            style: TextStyle(
              fontFamily: NestFont.display,
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: NestColor.ink,
            ),
          ),
        ),
        body: ListenableBuilder(
          listenable: _recorder,
          builder: (context, _) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
                child: Column(
                  children: [
                    if (_message != null) _Notice(text: _message!),
                    if (unsupported && _message == null)
                      _Notice(
                        text: tr('Recording saves a file, so it needs the phone '
                            'app. In the browser build you can still use '
                            'Dictate, which writes straight into the note.'),
                      ),
                    // The timer, the meter and the buttons add up to more than
                    // a short phone has, especially once a notice is showing.
                    // Centred when there is room, scrollable when there is
                    // not — a Spacer alone would just overflow.
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) => SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints:
                                BoxConstraints(minHeight: box.maxHeight),
                            child: _display(context),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _saving ? null : _discard,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 54),
                              foregroundColor: NestColor.redPen,
                            ),
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 18),
                            label: Text(tr('Discard')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _PauseButton(
                          recording: _recorder.isRecording,
                          enabled: !_saving && !unsupported,
                          onTap: _togglePause,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed:
                                _saving || !_recorder.isActive ? null : _save,
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: Text(_saving ? tr('Saving…') : tr('Save')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The state, the clock and the level trace — everything the student watches
/// while recording.
extension on _RecordPageState {
  Widget _display(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 12),
        Text(
          _recorder.isPaused
              ? tr('PAUSED')
              : _recorder.isRecording
                  ? tr('RECORDING')
                  : tr('READY'),
          style: nestEyebrow.copyWith(
            color: _recorder.isRecording
                ? NestColor.redPen
                : NestColor.inkFaint,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          formatClock(_recorder.elapsed),
          style: TextStyle(
            fontFamily: NestFont.mono,
            fontSize: 54,
            height: 1,
            fontWeight: FontWeight.w700,
            letterSpacing: ls(-1),
            color: NestColor.ink,
          ),
        ),
        const SizedBox(height: 28),
        NestLevelMeter(
          history: _recorder.history,
          live: _recorder.isRecording,
        ),
        const SizedBox(height: 12),
        Text(
          _recorder.isRecording
              ? tr('The line moves with your voice, so you can see it is hearing '
                  'the room.')
              : _recorder.isPaused
                  ? tr('Paused. The time stops where it is and carries on when '
                      'you resume.')
                  : tr('Nothing is being recorded yet.'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _PauseButton extends StatelessWidget {
  const _PauseButton({
    required this.recording,
    required this.enabled,
    required this.onTap,
  });

  final bool recording;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 62,
      height: 54,
      child: FilledButton(
        onPressed: enabled ? onTap : null,
        style: FilledButton.styleFrom(
          backgroundColor:
              recording ? NestColor.paperDeep : NestColor.redPen,
          foregroundColor: recording ? NestColor.ink : Colors.white,
          padding: EdgeInsets.zero,
        ),
        child: Icon(
          recording ? Icons.pause_rounded : Icons.mic_rounded,
          size: 22,
        ),
      ),
    );
  }
}

/// A short explanation in red pen, used for permission and platform messages.
class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NestColor.o(NestColor.redPen, 0.08),
        borderRadius: BorderRadius.circular(NestRadius.tile),
        border: Border(
          left: BorderSide(color: NestColor.redPen, width: 3),
        ),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
