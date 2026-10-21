import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_lock.dart';
import '../theme/nest_theme.dart';

/// Four dots and a numeric keypad.
///
/// Reports the PIN through [onComplete] the moment the last digit goes in.
/// The owner clears the dots after a wrong answer through [PinPadState.clear],
/// reached with a GlobalKey.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.onComplete,
    this.onBiometric,
    this.enabled = true,
  });

  final ValueChanged<String> onComplete;

  /// When set, the bottom-left key is a fingerprint button.
  final VoidCallback? onBiometric;

  final bool enabled;

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> with SingleTickerProviderStateMixin {
  String _pin = '';

  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  /// Empties the dots, shaking them if [wrong].
  void clear({bool wrong = false}) {
    setState(() => _pin = '');
    if (wrong) {
      HapticFeedback.heavyImpact();
      _shake.forward(from: 0);
    }
  }

  void _press(String digit) {
    if (!widget.enabled || _pin.length >= AppLock.pinLength) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += digit);
    if (_pin.length == AppLock.pinLength) widget.onComplete(_pin);
  }

  void _back() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Widget _key(String label, {VoidCallback? onTap, IconData? icon}) {
    return SizedBox(
      width: 78,
      height: 78,
      child: onTap == null
          ? const SizedBox.shrink()
          : Material(
              color: NestColor.paper,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: Center(
                  child: icon != null
                      ? Icon(icon, size: 26, color: NestColor.inkSoft)
                      : Text(
                          label,
                          style: TextStyle(
                            fontFamily: NestFont.display,
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                            color: NestColor.ink,
                          ),
                        ),
                ),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) {
            final dx = _shake.isAnimating
                ? 14 * (1 - _shake.value) * (((_shake.value * 10).floor() % 2 == 0) ? 1 : -1)
                : 0.0;
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < AppLock.pinLength; i++)
                Container(
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 9),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length ? NestColor.pen : Colors.transparent,
                    border: Border.all(
                      color: i < _pin.length ? NestColor.pen : NestColor.inkFaint,
                      width: 2,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 36),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final d in row)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    child: _key(d, onTap: () => _press(d)),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: _key(
                  '',
                  icon: Icons.fingerprint_rounded,
                  onTap: widget.onBiometric,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: _key('0', onTap: () => _press('0')),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: _key('',
                    icon: Icons.backspace_outlined, onTap: _back),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
