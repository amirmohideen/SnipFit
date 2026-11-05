#!/usr/bin/env bash
# Runs the Flutter unit and widget tests on the host machine (CI or laptop).
#
# face_detection_tflite depends on OpenCV (dartcv4), whose build hook compiles
# OpenCV from source for the *host* platform whenever `flutter test` runs. The
# tests never call into OpenCV, so for test runs only we set dartcv4's
# documented `skip_build` user-define. pubspec.yaml is always restored, so
# iOS and Android builds are unaffected.
set -euo pipefail
cd "$(dirname "$0")/.."

cp pubspec.yaml .pubspec.yaml.testbak
restore() { mv -f .pubspec.yaml.testbak pubspec.yaml; }
trap restore EXIT

perl -0pi -e 's/(\n    dartcv4:\n)/$1      skip_build: true\n/' pubspec.yaml
grep -q "skip_build: true" pubspec.yaml || { echo "could not set skip_build" >&2; exit 1; }

flutter test "$@"
