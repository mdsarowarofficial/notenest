import 'package:flutter/material.dart';

import '../../data/auth_repository.dart';
import '../../data/document_service.dart';
import '../../data/note_repository.dart';
import '../../data/page_renderer.dart';
import '../../models/cover_spec.dart';
import '../../theme/nest_theme.dart';
import 'cover_canvas.dart';
import 'cover_form.dart';
import '../../l10n/strings.dart';

/// The cover page generator.
///
/// The preview is pinned above the form and never scrolls away, for a reason
/// that is not only about looks: exporting photographs the preview, and a
/// widget scrolled off screen has no layer to photograph. Keeping it in view
/// means Export can never fail for a reason the student cannot see.
class CoverPageScreen extends StatefulWidget {
  const CoverPageScreen({super.key});

  @override
  State<CoverPageScreen> createState() => _CoverPageScreenState();
}

class _CoverPageScreenState extends State<CoverPageScreen> {
  final _repo = NoteRepository.instance;
  final _sheetKey = GlobalKey();

  late CoverSpec _spec;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Picks up what was filled in last time: the institution, the department,
    // their name and ID. The title and the number start empty.
    _spec = CoverSpec.decode(_repo.coverDraft);
    if (_spec.studentName.trim().isEmpty && _repo.userName.isNotEmpty) {
      _spec = _spec.copyWith(studentName: _repo.userName);
    }
    // The university typed when the account was made is the institution.
    final school = AuthRepository.instance.currentUser?.institution ?? '';
    if (_spec.institution.trim().isEmpty && school.trim().isNotEmpty) {
      _spec = _spec.copyWith(institution: school.trim());
    }
    if (_spec.session.trim().isEmpty && (_repo.semesterLabel ?? '').isNotEmpty) {
      _spec = _spec.copyWith(session: _repo.semesterLabel);
    }
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // The logo is decoded asynchronously by Image.memory. It is almost
      // certainly on screen already, but capturing a frame it had not finished
      // decoding would silently produce a cover page with a blank corner.
      final mark = _repo.brandLogo;
      if (mark != null && mounted) {
        await precacheImage(MemoryImage(mark), context);
      }
      if (!mounted) return;

      final png = await PageRenderer.capture(_sheetKey);
      final pdf = await DocumentService.pdfFromPageImages([png]);

      // Saved before sharing, so a cancelled share still remembers the
      // details that were typed in.
      await _repo.saveCoverDraft(_spec.asNextDraft.encode());

      final shared =
          await DocumentService.sharePdf(pdf, _spec.suggestedFileName);
      if (!mounted) return;
      setState(() => _busy = false);
      if (shared) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(trp('{0} sent', [_spec.suggestedFileName])),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on DocumentException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr('The page could not be exported. '
              'Scroll so the preview is visible and try again.');
        });
      }
    }
  }

  void _openFullSize() {
    showDialog<void>(
      context: context,
      barrierColor: NestColor.o(NestColor.ink, 0.72),
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(14),
        backgroundColor: Colors.transparent,
        child: InteractiveViewer(
          maxScale: 4,
          child: Material(
            elevation: 6,
            child: CoverCanvas(spec: _spec, logo: _repo.brandLogo),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final missing = _spec.missing;

    return ListenableBuilder(
      listenable: _repo,
      builder: (context, _) => _build(context, missing),
    );
  }

  Widget _build(BuildContext context, List<String> missing) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Cover page')),
        actions: [
          IconButton(
            onPressed: _openFullSize,
            icon: const Icon(Icons.fullscreen_rounded),
            tooltip: tr('See it full size'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // ------------------------------------------------- the live sheet
          Container(
            width: double.infinity,
            color: NestColor.paperDeep,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.42,
                  maxWidth: 360,
                ),
                child: AspectRatio(
                  aspectRatio: PageRenderer.a4Ratio,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: NestColor.o(NestColor.ink, 0.18),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    // The boundary wraps the sheet and nothing else — no
                    // padding, no shadow — so the captured image is exactly
                    // the page and not a page on a grey mount.
                    child: RepaintBoundary(
                      key: _sheetKey,
                      child: CoverCanvas(spec: _spec, logo: _repo.brandLogo),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ----------------------------------------------------- the form
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
              children: [
                if (missing.isNotEmpty) ...[
                  _MissingHint(missing: missing),
                  const SizedBox(height: 16),
                ],
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: NestColor.o(NestColor.redPen, 0.08),
                      borderRadius: BorderRadius.circular(NestRadius.tile),
                    ),
                    child: Text(
                      _error!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: NestColor.redPen),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                CoverForm(
                  spec: _spec,
                  onChanged: (next) => setState(() => _spec = next),
                ),
                const SizedBox(height: 10),
                Text(
                  tr('The PDF holds the page as a 200 DPI image, which is how '
                  'Bengali text survives the trip — the text in it cannot be '
                  'selected or searched.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 14),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _export,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.ios_share_rounded, size: 18),
              label: Text(_busy ? tr('Making the PDF…') : tr('Export as PDF')),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 54),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Names what a teacher would notice was missing, without blocking the export.
class _MissingHint extends StatelessWidget {
  const _MissingHint({required this.missing});

  final List<String> missing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NestColor.o(NestColor.highlight, 0.3),
        borderRadius: BorderRadius.circular(NestRadius.tile),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.edit_note_rounded, size: 18, color: NestColor.ink),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              trp('Still empty: {0}. You can export anyway and write them in by hand.', [missing.join(', ')]),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
