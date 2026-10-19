import '../models/cloud_profile.dart';
import 'cloud_service.dart';
import 'drive_backup.dart';
import 'note_repository.dart';
import 'profile_photo.dart';

/// Keeps the few things that live in two places in step.
///
/// The role, the photo and the backup each have a device copy (the notebook
/// must work offline) and a cloud or Drive copy (other people, or another
/// phone, need them). These run when the notebook opens, never throw, and
/// never ask the person anything.

/// Pushes the device's role to the cloud profile when the two differ.
///
/// The device is the source here because the role is chosen on the device —
/// at setup, or in Settings — and on a fresh install it was copied *from* the
/// cloud at sign-in, so by then the two already agree.
Future<void> syncCloudRole() async {
  final cloud = CloudService.instance;
  final profile = cloud.profile;
  if (!cloud.isSignedIn || profile == null) return;
  final wanted =
      NoteRepository.instance.isTeacher ? CloudRole.teacher : CloudRole.student;
  if (profile.role == wanted) return;
  try {
    await cloud.updateProfile(role: wanted);
  } catch (_) {
    // Tried again the next time the notebook opens.
  }
}

/// Everything above, run once as the notebook opens.
Future<void> syncAccountOnOpen() async {
  await syncCloudRole();
  await syncProfilePhoto();
  await DriveBackup.runDailyIfDue();
  await NoteRepository.instance.uploadPendingCourseFiles();
}
