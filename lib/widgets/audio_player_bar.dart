import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../data/attachment_store.dart';
import '../models/attachment.dart';
import '../models/transcript.dart';
import '../theme/nest_theme.dart';
import '../l10n/strings.dart';

/// Plays back a recording attached to a note.
///
/// The length shown before playback starts comes from the database column
/// written when the recording was made, not from the file, so the bar is
/// correct the moment it appears rather than after the player has loaded.
class AudioPlayerBar extends StatefulWidget {
  const AudioPlayerBar({super.key, required this.attachment});

  final Attachment attachment;

  @override
  State<AudioPlayerBar> createState() => _AudioPlayerBarState();
}

class _AudioPlayerBarState extends State<AudioPlayerBar> {
  final _player = AudioPlayer();
  final _subscriptions = <StreamSubscription<dynamic>>[];

  Duration _position = Duration.zero;
  Duration? _length;
  bool _playing = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _length = widget.attachment.duration;

    _subscriptions.addAll([
      _player.onPositionChanged.listen((p) {
        if (mounted) setState(() => _position = p);
      }),
      _player.onDurationChanged.listen((d) {
        // The file is the authority once it is loaded; the stored value was
        // only there so the bar had a length to show straight away.
        if (mounted && d > Duration.zero) setState(() => _length = d);
      }),
      _player.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _playing = false;
            _position = Duration.zero;
          });
        }
      }),
      _player.onPlayerStateChanged.listen((state) {
        if (mounted) setState(() => _playing = state == PlayerState.playing);
      }),
    ]);
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      return;
    }

    if (!AttachmentStore.isSupported) {
      setState(() => _error = tr('Playback needs the phone app.'));
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final path = await AttachmentStore.fullPath(widget.attachment.storedName);
      await _player.play(DeviceFileSource(path));
    } catch (_) {
      if (mounted) {
        setState(() => _error = tr('This recording could not be played.'));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _seek(double seconds) async {
    final to = Duration(milliseconds: (seconds * 1000).round());
    setState(() => _position = to);
    await _player.seek(to);
  }

  @override
  Widget build(BuildContext context) {
    final length = _length ?? Duration.zero;
    final maxSeconds = length.inMilliseconds / 1000;
    final atSeconds =
        (_position.inMilliseconds / 1000).clamp(0.0, maxSeconds <= 0 ? 0.0 : maxSeconds);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(
        color: NestColor.card,
        borderRadius: BorderRadius.circular(NestRadius.tile),
        boxShadow: NestShadow.resting,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 42,
                height: 42,
                child: FilledButton(
                  onPressed: _loading ? null : _toggle,
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(42, 42),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          _playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 22,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.mic_rounded,
                            size: 13, color: NestColor.inkFaint),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            widget.attachment.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      trp('{0} / {1}{2}', [formatClock(_position), formatClock(length), widget.attachment.readableSize.isEmpty ? '' : '  ·  ${widget.attachment.readableSize}']),
                      style: nestEyebrow.copyWith(letterSpacing: ls(0.3)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (maxSeconds > 0)
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: NestColor.pen,
                inactiveTrackColor: NestColor.rule,
                thumbColor: NestColor.pen,
              ),
              child: Slider(
                value: atSeconds.toDouble(),
                max: maxSeconds,
                onChanged: _seek,
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 2),
              child: Text(
                _error!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: NestColor.redPen),
              ),
            ),
        ],
      ),
    );
  }
}
