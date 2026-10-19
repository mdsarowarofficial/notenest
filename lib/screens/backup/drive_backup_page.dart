import 'package:flutter/material.dart';

import '../../data/drive_backup.dart';
import '../../data/drive_service.dart';
import '../../data/note_repository.dart';
import '../../theme/nest_theme.dart';
import '../../widgets/nest_mark_tile.dart';

/// Back up the notebook to Google Drive, and bring it back on another phone.
class DriveBackupPage extends StatefulWidget {
  const DriveBackupPage({super.key});

  @override
  State<DriveBackupPage> createState() => _DriveBackupPageState();
}

class _DriveBackupPageState extends State<DriveBackupPage> {
  final _repo = NoteRepository.instance;
  final _drive = DriveService.instance;

  bool? _connected;
  String? _busy;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    if (!_drive.isSupported) {
      setState(() => _connected = false);
      return;
    }
    final ok = await _drive.isConnected();
    if (mounted) setState(() => _connected = ok);
  }

  Future<void> _run(String label, Future<String?> Function() action) async {
    setState(() {
      _busy = label;
      _error = null;
    });
    try {
      final message = await action();
      if (!mounted) return;
      if (message != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } on DriveException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _connect() => _run('Connecting…', () async {
        await _drive.connect();
        if (mounted) setState(() => _connected = true);
        return 'Google Drive connected.';
      });

  Future<void> _backUp() => _run('Backing up…', () async {
        await DriveBackup.backUp();
        if (mounted) setState(() => _connected = true);
        return 'Backed up to Google Drive.';
      });

  Future<void> _restore() => _run('Looking for a backup…', () async {
        final file = await DriveBackup.latest();
        if (!mounted) return null;
        if (file == null) {
          return 'No backup for this account in Google Drive yet.';
        }
        final when = file.modifiedTime;
        final yes = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Restore from Drive?'),
            content: Text(
              'The backup from '
              '${when == null ? 'Drive' : _date(when.toLocal())} is added to '
              'this phone. Nothing here is deleted or replaced — notes that '
              'are already on this phone are left as they are.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Restore'),
              ),
            ],
          ),
        );
        if (yes != true) return null;
        if (mounted) setState(() => _busy = 'Restoring…');
        final report = await DriveBackup.restore(file);
        return report.summary;
      });

  static String _date(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]} ${d.year}, $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Google Drive backup')),
      body: ListenableBuilder(
        listenable: _repo,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: NestColor.card,
                borderRadius: BorderRadius.circular(NestRadius.card),
                boxShadow: NestShadow.resting,
              ),
              child: Row(
                children: [
                  MarkTile.tool(
                    Icons.add_to_drive_rounded,
                    tint: _connected == true
                        ? NestColor.tintMint
                        : NestColor.tintWarm,
                    ink: _connected == true
                        ? NestColor.mintDeep
                        : NestColor.warmDeep,
                    size: 46,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _connected == null
                              ? 'Checking Google Drive…'
                              : _connected!
                                  ? 'Google Drive is connected'
                                  : 'Google Drive is not connected',
                          style: t.titleSmall,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _repo.lastBackupAt == null
                              ? 'No backup made from this phone yet.'
                              : 'Last backup: '
                                  '${_date(_repo.lastBackupAt!)}',
                          style: t.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (!_drive.isSupported)
              Text(
                'Google Drive backup works in the NoteNest app on a phone, '
                'not in a browser.',
                style: t.bodySmall,
              )
            else ...[
              if (_connected == false) ...[
                SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _busy == null ? _connect : null,
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('Connect Google Drive'),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: _busy == null ? _backUp : null,
                  icon: const Icon(Icons.cloud_upload_rounded),
                  label: const Text('Back up now'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _busy == null ? _restore : null,
                  icon: const Icon(Icons.cloud_download_rounded),
                  label: const Text('Restore from Drive'),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _repo.autoBackup,
                onChanged: _busy != null
                    ? null
                    : (on) async {
                        await _repo.saveBackupState(auto: on);
                        if (on && _connected != true) await _connect();
                      },
                title: const Text('Back up every day'),
                subtitle: const Text(
                  'Once a day, when you open NoteNest with a connection.',
                ),
              ),
            ],
            if (_busy != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(_busy!, style: t.bodyMedium),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                style: const TextStyle(color: NestColor.redPen, fontSize: 13.5),
              ),
            ],
            const SizedBox(height: 26),
            Text('What is saved', style: t.titleSmall),
            const SizedBox(height: 6),
            Text(
              'Every subject, note, task, exam date and setting on this '
              'account, and every file attached to a note — PDFs, '
              'photographed pages and recordings. It goes in one file in your '
              'own Google Drive, in the NoteNest → Backups folder, so it is '
              'still there if this phone is lost.\n\n'
              'Files you add to a course are saved to your Drive too, each in '
              'NoteNest → Courses → the course code, and come back with a '
              'restore. It all counts against your own Drive storage: if '
              'Drive is full, NoteNest tells you and waits until you free '
              'some space.\n\n'
              'On a new phone, sign in with the same account and tap Restore '
              'from Drive. NoteNest can only see the files it saved itself — '
              'never the rest of your Drive.',
              style: t.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
