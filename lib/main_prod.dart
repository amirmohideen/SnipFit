import 'bootstrap.dart';
import 'config/app_config.dart';
import 'firebase/firebase_options_prod.dart';

void main() => bootstrap(
  Flavor.prod,
  firebaseOptions: () => DefaultFirebaseOptions.currentPlatform,
);
