#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/.."
git submodule update --init --recursive
if [ ! -f lib/.env ]; then cp lib/.env.example lib/.env; fi
python3 tool/configure_deezer_env.py
flutter pub get
dart run build_runner build --delete-conflicting-outputs
# The inherited Last.fm submodule targets Dart 3.0. Generate compatible code
# without altering its source or committing changes to the upstream repository.
(
  cd scrobblenaut
  if [ -f pubspec_overrides.yaml ]; then
    echo 'Existing scrobblenaut/pubspec_overrides.yaml: preserve it and run code generation manually.' >&2
    exit 1
  fi
  trap 'rm -f pubspec_overrides.yaml' EXIT HUP INT TERM
  cat > pubspec_overrides.yaml <<'YAML'
dependency_overrides:
  build_runner: 2.4.15
  json_serializable: 6.9.5
YAML
  dart pub get
  dart run build_runner build --delete-conflicting-outputs
)
flutter pub get
