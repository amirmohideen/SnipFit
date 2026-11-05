// PLACEHOLDER. Replace by running, from the repo root:
//
//   flutterfire configure --project=<your-prod-firebase-project> \
//     --out=lib/firebase/firebase_options_prod.dart \
//     --ios-bundle-id=com.snipfit.app \
//     --android-package-name=com.snipfit.app
//
// Until then the app runs in local-only mode (see firebase_options_dev.dart).
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform =>
      throw UnsupportedError('Firebase (prod) is not configured yet.');
}
