import 'bootstrap.dart';
import 'config/app_config.dart';
import 'firebase/firebase_options_dev.dart';

void main() => bootstrap(
  Flavor.dev,
  firebaseOptions: () => DefaultFirebaseOptions.currentPlatform,
);
