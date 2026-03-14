#!/usr/bin/env bash
# WeldTrace Flutter — local build setup
# Run this once after cloning, or after any table/DAO change.
#
# Prerequisites: Flutter SDK >= 3.19, Dart SDK >= 3.3
# Usage:  bash flutter_app/scripts/build.sh

set -euo pipefail
cd "$(dirname "$0")/.."

echo ">>> flutter pub get"
flutter pub get

echo ">>> build_runner — regenerating Drift + Riverpod code"
flutter pub run build_runner build --delete-conflicting-outputs

echo ""
echo ">>> flutter analyze"
flutter analyze --no-fatal-infos

echo ""
echo "Done. Generated files:"
find lib -name "*.g.dart" | sort
