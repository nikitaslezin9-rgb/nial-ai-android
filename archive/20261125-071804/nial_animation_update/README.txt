Nial Diary - animation update

Extract the entire ZIP to C:\dev\nial_animation_update (not into the app project).
Save a new diary ZIP in the running app. Stop flutter run with q.
Run:
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\dev\nial_animation_update\install_animations.ps1"

Then from C:\dev\nial_diary:
& "C:\dev\flutter\bin\flutter.bat" analyze
& "C:\dev\flutter\bin\flutter.bat" test test/nial_motion_test.dart test/nial_profile_test.dart
& "C:\dev\flutter\bin\flutter.bat" run --profile -d RF8XB0GH1KM -t lib/main.dart

Changes: incoming tab fade/slide, animated selected navigation highlight and icon,
question crossfade, bookmark scale transition, add-button press response,
profile avatar crossfade and profile-editor entrance.
No claim of measured performance improvement: these are visual transitions.
System disableAnimations is respected by the new motion widgets.
Only incoming tabs are animated; no duplicate page trees/forms/players.
No per-entry controller is allocated for the diary list.
No database, media service, profile persistence, pubspec or Android changes.
No new dependencies.

Installer checks source hashes and refuses changed files. If an expected original
source is missing, it restores the included uploaded snapshot before updating.
Backups are kept OUTSIDE the project in C:\dev\nial_source_backups\animations_*.
Rollback: copy the two original lib files back from the printed backup folder;
remove lib/services/nial_motion.dart and test/nial_motion_test.dart if desired.

Flutter SDK is unavailable here. Widget tests are included, NOT executed here.
Check tabs, editor keyboard, avatar, bookmark, media playback and backup UI on phone.
Do not delete the app or clear data to test this update.
