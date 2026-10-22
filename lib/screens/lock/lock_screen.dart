import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/app_lock.dart';
import '../../data/auth_repository.dart';
import '../../data/note_repository.dart';
import '../../l10n/strings.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/pin_pad.dart';
import '../auth/login_page.dart';

/// The app's Navigator, reachable from outside the widget tree. The lock sits
/// above the Navigator, so after signing out from the lock screen it needs a
/// way to send the app back to the login page.
final nestNavigatorKey = GlobalKey<NavigatorState>();

/// Puts the lock screen over the app whenever the app is locked.
///
/// The lock is drawn above the Navigator, so it covers every page, dialog and
/// sheet at once rather than each of them having to remember to hide itself.
class LockGate extends StatelessWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLock.instance,
      builder: (context, _) {
        final locked = AppLock.instance.locked;
        return Stack(
          children: [
            // Covering the app is not enough: a screen reader and keyboard
            // focus still reach whatever is underneath, so while locked the
            // app below is hidden from both.
            ExcludeSemantics(
              excluding: locked,
              child: ExcludeFocus(excluding: locked, child: child),
            ),
            if (locked) const Positioned.fill(child: LockScreen()),
          ],
        );
      },
    );
  }
}

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pad = GlobalKey<PinPadState>();
  final _password = TextEditingController();
  Timer? _tick;

  bool _forgot = false;
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Offer the fingerprint straight away; the keypad is there if it fails.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && AppLock.instance.biometric) {
        AppLock.instance.unlockWithBiometric();
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _password.dispose();
    super.dispose();
  }

  void _tryPin(String pin) {
    final lock = AppLock.instance;
    if (lock.check(pin)) {
      lock.unlock();
      return;
    }
    _pad.currentState?.clear(wrong: true);
    final wait = lock.waitSeconds;
    setState(() {
      _message = wait > 0
          ? trp('Too many tries. Wait {0} seconds.', [wait])
          : tr('That PIN is not right.');
    });
    if (wait > 0) {
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        final left = lock.waitSeconds;
        setState(() => _message =
            left > 0 ? trp('Too many tries. Wait {0} seconds.', [left]) : null);
        if (left == 0) t.cancel();
      });
    }
  }

  Future<void> _checkPassword() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final ok = await AuthRepository.instance.checkPassword(_password.text);
    if (!mounted) return;
    if (ok) {
      await AppLock.instance.disable();
      return;
    }
    setState(() {
      _busy = false;
      _message = tr('That password is not right.');
    });
  }

  Future<void> _signOutAndOpenLogin() async {
    setState(() => _busy = true);
    await AuthRepository.instance.signOut();
    NoteRepository.instance.clear();
    await AppLock.instance.disable();
    nestNavigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final lock = AppLock.instance;

    return Material(
      color: NestColor.ground,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: _forgot ? _forgotView(t) : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: NestColor.tintPen,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Icon(Icons.lock_rounded, size: 30, color: NestColor.pen),
                ),
                const SizedBox(height: 18),
                Text(tr('NoteNest is locked'), style: t.headlineSmall),
                const SizedBox(height: 6),
                Text(tr('Enter your PIN'), style: t.bodyMedium),
                SizedBox(
                  height: 40,
                  child: Center(
                    child: Text(
                      _message ?? '',
                      style: TextStyle(
                        fontFamily: NestFont.body,
                        fontSize: 13,
                        color: NestColor.redPen,
                      ),
                    ),
                  ),
                ),
                PinPad(
                  key: _pad,
                  enabled: lock.waitSeconds == 0,
                  onComplete: _tryPin,
                  onBiometric: lock.biometric
                      ? () => lock.unlockWithBiometric()
                      : null,
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => setState(() {
                    _forgot = true;
                    _message = null;
                  }),
                  child: Text(tr('Forgot your PIN?')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _forgotView(TextTheme t) {
    final usesGoogle = AuthRepository.instance.currentUserUsesGoogle;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr('Forgot your PIN?'), style: t.headlineSmall),
          const SizedBox(height: 10),
          Text(
            usesGoogle
                ? tr('This account signs in with Google, so there is no '
                    'password to check. You can turn the lock off by signing '
                    'out; your notes stay on this phone, and signing in again '
                    'brings you straight back to them.')
                : tr('Type your NoteNest password and the lock will be turned '
                    'off. You can set a new PIN afterwards in Settings.'),
            style: t.bodyMedium,
          ),
          const SizedBox(height: 18),
          if (!usesGoogle) ...[
            TextField(
              controller: _password,
              obscureText: true,
              autofocus: true,
              onSubmitted: (_) => _checkPassword(),
              decoration: InputDecoration(hintText: tr('Your password')),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _busy ? null : _checkPassword,
              child: Text(tr('Turn the lock off')),
            ),
          ] else
            FilledButton(
              onPressed: _busy ? null : _signOutAndOpenLogin,
              child: Text(tr('Sign out and turn the lock off')),
            ),
          if (_message != null) ...[
            const SizedBox(height: 10),
            Text(
              _message!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: NestFont.body,
                fontSize: 13,
                color: NestColor.redPen,
              ),
            ),
          ],
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => setState(() {
              _forgot = false;
              _message = null;
              _password.clear();
            }),
            child: Text(tr('Back')),
          ),
        ],
      ),
    );
  }
}

/// Setting a PIN: type it, then type it again.
///
/// Pops with true once a PIN has been saved, false or null if the person went
/// back out.
class PinSetupPage extends StatefulWidget {
  const PinSetupPage({super.key});

  @override
  State<PinSetupPage> createState() => _PinSetupPageState();
}

class _PinSetupPageState extends State<PinSetupPage> {
  final _pad = GlobalKey<PinPadState>();
  String? _first;
  String? _message;
  bool _saving = false;

  Future<void> _entered(String pin) async {
    if (_first == null) {
      setState(() {
        _first = pin;
        _message = null;
      });
      _pad.currentState?.clear();
      return;
    }
    if (pin != _first) {
      setState(() {
        _first = null;
        _message = tr('The two PINs were different. Start again.');
      });
      _pad.currentState?.clear(wrong: true);
      return;
    }
    setState(() => _saving = true);
    await AppLock.instance.setPin(pin);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('App lock'))),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _first == null ? tr('Choose a PIN') : tr('Type it again'),
                style: t.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                tr('Four digits. You will be asked for it when you open '
                    'NoteNest and when you come back after a minute away.'),
                textAlign: TextAlign.center,
                style: t.bodyMedium,
              ),
              SizedBox(
                height: 40,
                child: Center(
                  child: Text(
                    _message ?? '',
                    style: TextStyle(
                      fontFamily: NestFont.body,
                      fontSize: 13,
                      color: NestColor.redPen,
                    ),
                  ),
                ),
              ),
              PinPad(key: _pad, enabled: !_saving, onComplete: _entered),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for the current PIN before something that weakens the lock, such as
/// turning it off. Pops with true when it was right.
class PinVerifyPage extends StatefulWidget {
  const PinVerifyPage({super.key});

  @override
  State<PinVerifyPage> createState() => _PinVerifyPageState();
}

class _PinVerifyPageState extends State<PinVerifyPage> {
  final _pad = GlobalKey<PinPadState>();
  String? _message;

  void _entered(String pin) {
    final lock = AppLock.instance;
    if (lock.check(pin)) {
      Navigator.of(context).pop(true);
      return;
    }
    _pad.currentState?.clear(wrong: true);
    setState(() {
      _message = lock.waitSeconds > 0
          ? trp('Too many tries. Wait {0} seconds.', [lock.waitSeconds])
          : tr('That PIN is not right.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('App lock'))),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('Enter your PIN'), style: t.headlineSmall),
              SizedBox(
                height: 48,
                child: Center(
                  child: Text(
                    _message ?? '',
                    style: TextStyle(
                      fontFamily: NestFont.body,
                      fontSize: 13,
                      color: NestColor.redPen,
                    ),
                  ),
                ),
              ),
              PinPad(key: _pad, onComplete: _entered),
            ],
          ),
        ),
      ),
    );
  }
}
