// PLACEHOLDER. Replace by running, from the repo root:
//
//   flutterfire configure --project=<your-dev-firebase-project> \
//     --out=lib/firebase/firebase_options_dev.dart \
//     --ios-bundle-id=com.snipfit.app.dev \
//     --android-package-name=com.snipfit.app.dev
//
// Until then the app runs in local-only mode: the free cutout, live window,
// compare, save and share all work; accounts, credits and AI try-on are off.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform =>
      throw UnsupportedError('Firebase (dev) is not configured yet.');
}
