import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// The university logo that goes on a cover page.
///
/// **Why the app does not ship logos.** The obvious design is: pick your
/// university from the list, and its logo appears. The university list can be
/// carried because a name is a fact. A logo is not — it is a trademark owned
/// by that institution, and bundling ten thousand of them into an app would
/// be redistributing ten thousand marks without permission from any of them.
/// Fetching them from a third-party logo service at run time is the same act
/// with an extra step, and it would need a connection besides.
///
/// So the logo is supplied once by the student, from a file they already have.
/// That turns out to be the better design anyway:
///
/// - it works for any institution on earth, including the ones no list has
/// - it is the real logo at full quality, not whatever a scraper found
/// - it works with no connection, like the rest of the app
/// - it is chosen once and then appears on every cover page from then on
///
/// The same image is used for the corner mark and, faded, for the watermark,
/// so there is one thing to set rather than two.
class BrandStore {
  BrandStore._();

  /// Logos are drawn at about 60pt on an A4 page. 512px is far more than that
  /// needs even at 300 DPI, and keeps what is stored small.
  static const maxDimension = 512;

  /// Opens the gallery and returns a normalised PNG, or null if nothing was
  /// picked or the file could not be read as an image.
  static Future<Uint8List?> pickLogo() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Deliberately no `imageQuality`: that re-encodes as JPEG, and a JPEG
      // has no transparency. A logo on a white page would arrive in a grey
      // box.
      maxWidth: maxDimension * 2,
    );
    if (picked == null) return null;

    final raw = await picked.readAsBytes();
    return normalise(raw);
  }

  /// Decodes whatever was picked, fits it inside [maxDimension], and re-encodes
  /// it as PNG so transparency survives.
  ///
  /// Returns null when the bytes are not an image the decoder recognises, which
  /// the caller reports rather than storing something unreadable.
  static Uint8List? normalise(Uint8List raw) {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return null;

    final tooBig =
        decoded.width > maxDimension || decoded.height > maxDimension;
    final fitted = tooBig
        ? img.copyResize(
            decoded,
            // Only the longer side is given, so the other is worked out and
            // the logo is not squashed.
            width: decoded.width >= decoded.height ? maxDimension : null,
            height: decoded.height > decoded.width ? maxDimension : null,
            interpolation: img.Interpolation.average,
          )
        : decoded;

    return img.encodePng(fitted);
  }

  /// The settings store holds strings, so the logo travels as base64.
  ///
  /// A 512px PNG is typically 30–150 KB, which is around 40–200 KB encoded —
  /// small enough for a settings row, and it means the logo is backed up and
  /// restored with the account rather than living in a file that can go
  /// missing.
  static String encode(Uint8List png) => base64Encode(png);

  static Uint8List? decode(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    try {
      return base64Decode(stored);
    } catch (_) {
      return null;
    }
  }
}
