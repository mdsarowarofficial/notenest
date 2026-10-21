import 'package:flutter/material.dart';

/// Shown when the app cannot open its own data at launch. It stands on its own
/// (plain Material, no palette, no saved language) because whatever failed may
/// be exactly what those would have read from.
class StartupFailedApp extends StatefulWidget {
  const StartupFailedApp({super.key, required this.error, required this.retry});

  final Object error;

  /// Tries the whole start again.
  final Future<void> Function() retry;

  @override
  State<StartupFailedApp> createState() => _StartupFailedAppState();
}

class _StartupFailedAppState extends State<StartupFailedApp> {
  bool _trying = false;

  Future<void> _retry() async {
    setState(() => _trying = true);
    await widget.retry();
    if (mounted) setState(() => _trying = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NoteNest',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF5C6BC0)),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    "NoteNest couldn't open your notes",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Nothing has been deleted. Close other apps to free up '
                    'memory and storage, then try again. If it keeps '
                    'happening, update NoteNest from the Play Store.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _trying ? null : _retry,
                    child: Text(_trying ? 'Opening…' : 'Try again'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${widget.error}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
