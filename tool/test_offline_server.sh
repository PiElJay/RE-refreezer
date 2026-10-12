#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cache_root="${GRADLE_USER_HOME:-${HOME}/.gradle}/caches/modules-2/files-2.1/org.nanohttpd/nanohttpd/2.3.1"
nanohttpd_jar="$(rg --files "$cache_root" | rg '/nanohttpd-2\.3\.1\.jar$' | head -1)"
classes_dir="$(mktemp -d)"
trap 'rm -rf "$classes_dir"' EXIT
javac -cp "$nanohttpd_jar" -d "$classes_dir" \
  "$repo_root/android/app/src/main/java/r/r/refreezer/ByteRange.java" \
  "$repo_root/android/app/src/main/java/r/r/refreezer/StreamServer.java" \
  "$repo_root/test/native/offline_stubs/Deezer.java" \
  "$repo_root/test/native/offline_stubs/DownloadLog.java" \
  "$repo_root/test/native/offline_stubs/DeezerDecryptor.java" \
  "$repo_root/test/native/OfflineStreamServerTest.java"
java -cp "$classes_dir:$nanohttpd_jar" r.r.refreezer.OfflineStreamServerTest
