# PiElJay player refresh

This fork keeps Deezer as its music provider and preserves upstream licensing.

## Behavior changes

- Clicked track occurrences are resolved again after unavailable audio sources are removed. Duplicate Deezer IDs remain separate queue entries.
- The public queue uses source order. Shuffle order is a permutation over that order; clicks, removal and current-item reporting use source indices.
- Playlist pagination uses a provider cursor independent of filtered playable sources and retains duplicate occurrences.
- Queue replacements run in order and ignore stale selections. A failed queue extension cannot replace a newer selection.
- Playback checkpoints are serialized and atomically replaced every 15 seconds while playing, on queue selection and on stop. Older playback files keep the same format.
- Finishing playback preserves the last item and position instead of seeking to the first song.
- Playback failures allow one online metadata refresh, then scan the remaining playback order. Offline recovery only selects downloaded files and never wraps indefinitely.
- A live connection monitor handles airplane mode, captive/unusable connections and app resume. Downloads paused by a connection loss resume automatically; manually paused downloads remain paused.
- The local audio server checks completed local files on every request, including queues created before downloads completed.
- Download commands share the same private offline storage. The Download hub links downloaded tracks and transfer states.
- Query history persists separately from opened search-result history, with deduplication, deletion and a 30-query limit.
- Deezer lyrics support a bounded pipe-to-legacy fallback, persistent positive cache and following the current song without closing the lyric screen.
- New adaptive dashboard and player, consistent component styling and PiElJay attribution.
- Credential-bearing diagnostic values are redacted before writing logs.

## Build

Clone with submodules. Use Flutter 3.47.7 and Java 17, Android SDK 36 (target 35, minimum Android 7.0) and NDK 27.0.12077973 for the app (Flutter plugins also install 28.2.13676358). Gradle 8.14.4, AGP 8.11.1 and Kotlin 2.2.20 are pinned.

Copy `lib/.env.example` to `lib/.env`. Blank values permit compilation and ARL sign-in; email/password Deezer sign-in and Last.fm require your own corresponding application credentials.

```sh
./tool/bootstrap.sh
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub
flutter build apk --debug
```

Debug builds use the existing `.debug` application ID suffix and install separately from a release build. They do not share the release app's downloads or session. A release update requires the existing signing key; do not uninstall an existing app to resolve a signature mismatch without backing up its data.

The navigator dependency has a small local compatibility copy in `packages/custom_navigator`; it inherits new Flutter observer defaults and retains the upstream MIT license. The bootstrap script generates Dart 3.0-compatible serializers for the inherited Last.fm submodule without modifying its tracked source.

## Automated validation

The regression suite covers 896 filtered-queue selections, duplicate identities, unavailable selections, bounded recovery in shuffle order, legacy cache compatibility, concurrent query persistence and log redaction. Widget checks render dashboard, player and search at 320×720, 844×390 and 1024×768 with 150% text scaling and verify search disposal. Static analysis has no compilation errors or warnings; informational lint/deprecation findings remain in inherited components.

## Device acceptance checks

These checks require an authenticated Deezer session and have to be performed on an Android device.

1. In album, sorted playlist, search, history and offline lists, select a middle item with unavailable predecessors. Confirm displayed and played IDs agree.
2. Add the same track twice to a playlist; select each occurrence. Test shuffle, removal and reordering.
3. Tap three different tracks quickly, then press Next. Only the latest selection should win.
4. Play a mixed local/online queue, enable airplane mode during playback and advance. Downloaded tracks remain playable; missing tracks fail cleanly.
5. Download a track after constructing its queue, then disconnect and play it.
6. Test airplane mode with Wi-Fi still enabled, Wi-Fi without Internet, network return and a manual download pause.
7. Finish the final playable track. The app must not seek to the first track.
8. Load lyrics, disconnect, reopen them and seek. Change songs with lyrics open; old requests must not overwrite the current song.
9. Repeat and delete searches; restart and confirm query persistence.
10. Check 320-pixel phone width, landscape, tablet width and large text. Check the mini-player, queue and download hub.

Deezer catalog availability and lyric coverage depend on the account and provider. Automated invariant tests do not substitute for the authenticated device checks above.
