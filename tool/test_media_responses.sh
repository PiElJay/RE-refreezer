#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
classes_dir="$(mktemp -d)"
trap 'rm -rf "$classes_dir"' EXIT
javac -d "$classes_dir" "$repo_root/android/app/src/main/java/r/r/refreezer/MediaResponseSummary.java" "$repo_root/test/native/MediaResponseSummaryTest.java"
java -cp "$classes_dir" r.r.refreezer.MediaResponseSummaryTest
