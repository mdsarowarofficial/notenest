import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/nest_theme.dart';
import 'cloud_service.dart';
import 'note_repository.dart';
import '../l10n/strings.dart';

/// Picking, squaring and shrinking a profile photo.
///
/// One small JPEG, used in two places: the device keeps it in the account's
/// settings, and the cloud profile carries the same bytes so classmates and a
/// teacher see the face rather than two letters. It is kept small on purpose.
/// There is no file storage behind the cloud profile — it is a Firestore
/// document that everyone in a class downloads — so the photo travels inside
/// it, and 192 pixels at this quality is roughly ten kilobytes.
class ProfilePhoto {
  ProfilePhoto._();

  /// Edge of the stored square, in pixels. Large enough for the 62px profile
  /// header on a 3x screen, small enough to live in a profile document.
  static const edge = 192;

  /// The ceiling the security rules enforce on the encoded text. The app's own
  /// output is far below it; the rule exists for clients that are not this app.
  static const maxEncodedLength = 40000;

  static final _picker = ImagePicker();

  /// Lets the person choose a photo, crop it square, and returns the result
  /// ready to store. Null if they backed out at any point.
  static Future<Uint8List?> pick(ImageSource source) async {
    final shot = await _picker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 1600,
      maxHeight: 1600,
      preferredCameraDevice: CameraDevice.front,
    );
    if (shot == null) return null;

    var path = shot.path;
    if (!kIsWeb) {
      final cropped = await ImageCropper().cropImage(
        sourcePath: path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressQuality: 90,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: tr('Your photo'),
            toolbarColor: NestColor.pen,
            toolbarWidgetColor: Colors.white,
            backgroundColor: NestColor.ink,
            activeControlsWidgetColor: NestColor.pen,
            cropStyle: CropStyle.circle,
            lockAspectRatio: true,
          ),
          IOSUiSettings(
            title: tr('Your photo'),
            cropStyle: CropStyle.circle,
            aspectRatioLockEnabled: true,
          ),
        ],
      );
      if (cropped == null) return null;
      path = cropped.path;
    }

    final bytes = await XFile(path).readAsBytes();
    // Off the UI thread: decoding a twelve-megapixel camera JPEG takes long
    // enough on a budget phone to freeze the screen it was picked from.
    return compute(shrink, bytes);
  }

  /// Squares and shrinks any image to the stored size. Null if the bytes are
  /// not an image the decoder understands.
  static Uint8List? shrink(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final square = img.copyResizeCropSquare(decoded, size: edge);
    return Uint8List.fromList(img.encodeJpg(square, quality: 78));
  }

  static String encode(Uint8List bytes) => base64Encode(bytes);

  /// Never throws: a damaged value shows initials rather than a crash.
  static Uint8List? decode(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    try {
      return base64Decode(stored);
    } catch (_) {
      return null;
    }
  }
}

/// The photo to show for the signed-in account: the device's copy, or the
/// cloud's when this device has none yet (a new phone, before any change).
Uint8List? myPhoto() =>
    NoteRepository.instance.profilePhoto ??
    ProfilePhoto.decode(CloudService.instance.profile?.photo);

/// Brings the device's photo and the cloud profile's into line.
///
/// Run when the notebook opens. The device copy wins when both exist, because
/// it is the one the person last chose here; the cloud copy is adopted only
/// when the device has none, which is exactly a fresh install.
Future<void> syncProfilePhoto() async {
  final repo = NoteRepository.instance;
  final cloud = CloudService.instance;
  final remote = cloud.profile?.photo ?? '';
  final local = repo.profilePhoto;
  if (!cloud.isSignedIn || cloud.profile == null) return;

  if (local == null) {
    final adopted = ProfilePhoto.decode(remote);
    if (adopted != null) await repo.saveProfilePhoto(adopted);
    return;
  }
  final encoded = ProfilePhoto.encode(local);
  if (encoded == remote || encoded.length > ProfilePhoto.maxEncodedLength) {
    return;
  }
  try {
    await cloud.updateProfile(photo: encoded);
  } catch (_) {
    // Tried again next time the notebook opens.
  }
}

/// The whole "change my photo" action: ask, pick, store here and in the cloud.
///
/// Returns a message for a snackbar, or null when nothing needs saying.
Future<String?> changeMyPhoto(BuildContext context) async {
  final repo = NoteRepository.instance;
  final choice = await askPhotoSource(
    context,
    hasPhoto: myPhoto() != null,
  );
  if (choice == null) return null;

  Uint8List? bytes;
  if (choice != PhotoChoice.remove) {
    try {
      bytes = await ProfilePhoto.pick(
        choice == PhotoChoice.camera ? ImageSource.camera : ImageSource.gallery,
      );
    } catch (e) {
      return trp('Could not open that photo. {0}', [e]);
    }
    if (bytes == null) return null;
  }

  await repo.saveProfilePhoto(bytes);

  final cloud = CloudService.instance;
  if (!cloud.isSignedIn || cloud.profile == null) {
    return bytes == null
        ? tr('Photo removed.')
        : tr('Photo saved on this phone. Connect the cloud account so '
            'classmates see it too.');
  }
  try {
    await cloud.updateProfile(
      photo: bytes == null ? '' : ProfilePhoto.encode(bytes),
    );
    return bytes == null ? tr('Photo removed.') : tr('Photo updated.');
  } on CloudException catch (e) {
    return trp('Saved on this phone, but not in the cloud yet: {0}', [e.message]);
  }
}

/// Asks where the photo should come from, with a way to remove the current one.
///
/// Returns the source, or [PhotoChoice.remove], or null if the sheet was
/// dismissed.
enum PhotoChoice { camera, gallery, remove }

Future<PhotoChoice?> askPhotoSource(
  BuildContext context, {
  required bool hasPhoto,
}) {
  return showModalBottomSheet<PhotoChoice>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 14),
          Text(tr('PROFILE PHOTO'), style: nestEyebrow),
          const SizedBox(height: 6),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(tr('Take a photo')),
            onTap: () => Navigator.pop(sheetContext, PhotoChoice.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(tr('Choose from gallery')),
            onTap: () => Navigator.pop(sheetContext, PhotoChoice.gallery),
          ),
          if (hasPhoto)
            ListTile(
              leading: Icon(Icons.delete_outline_rounded,
                  color: NestColor.redPen),
              title: Text(
                tr('Remove photo'),
                style: TextStyle(color: NestColor.redPen),
              ),
              onTap: () => Navigator.pop(sheetContext, PhotoChoice.remove),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
