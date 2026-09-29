# Blanarch

A generic Android client for FortiGate SSL-VPN (tunnel mode, FortiOS 7.6.2 and older). Users
add their own connections: address, certificate check, password with code or push, or single
sign-on, and optionally reading emailed codes from their inbox. Flutter draws the UI; a Kotlin
engine does the VPN work, built clean-room from `../docs/protocol/fortigate-sslvpn.md`.

## Layout

```
lib/                                Flutter (MVVM, per the official architecture guide)
  main.dart, config/dependencies.dart   composition root (provider)
  domain/models/                    immutable models (VpnStatus, Profile, ProbeResult…)
  data/services/vpn_platform.dart   interface to the engine + Pigeon implementation
  data/repositories/                VpnRepository, ProfileRepository, SettingsRepository
  ui/<feature>/                     *_screen.dart (view) + *_view_model.dart (state, Commands)
  ui/core/                          theme, shared widgets, l10n helpers
  utils/                            Result and Command
  l10n/app_en.arb, app_es.arb       all UI text (no dashes in copy)
pigeons/vpn_api.dart                the typed Dart↔Kotlin contract

android/app/src/main/kotlin/com/blanarch/app/
  BlanarchApplication.kt          AppGraph composition root
  vpn/ConnectionOrchestrator.kt     retries, failover, cookie reuse, status updates
  vpn/VpnTunnelService.kt            thin Android service (foreground + lifecycle)
  sslvpn/                           clean-room protocol engine (pure parts unit-tested)
  profile/  mail/  otp/  sso/       connections, email codes, SSO loopback callback
  bridge/VpnBridge.kt               implements the Pigeon host API
android/app/src/main/res/raw/vpn_config.json   generic engine defaults only
```

Commands go down (view → view-model → repository → Pigeon → orchestrator);
status comes back up as an immutable `VpnStatus` through a `StateFlow` and Pigeon events.
Disconnecting cancels the orchestrator's coroutine, which closes its sockets.

## Everyday commands

```bash
flutter analyze                                   # Dart lints (strict)
flutter test                                      # view-model tests + golden screenshots
(cd android && ./gradlew ktlintCheck testDebugUnitTest)   # Kotlin lint + unit tests
dart run pigeon --input pigeons/vpn_api.dart      # after changing the bridge contract
flutter gen-l10n                                  # after editing the .arb files
flutter build apk --release --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Golden screenshots in `test/goldens/` are the visual regression guard. Only refresh them
for an intended UI change: `flutter test --update-goldens test/screens_golden_test.dart`.

## Connections

Users create them in the app (first-run setup or Settings, Add connection). The engine
stores profiles (`profile/`), passwords (Keystore, per profile) and trusted certificate
digests (per host). `res/raw/vpn_config.json` only holds generic engine defaults.

## Release signing

Release builds are signed with `~/.android-keys/blandfortivpn.jks` via the git-ignored
`android/key.properties`. The keystore password is also in the macOS Keychain
(`security find-generic-password -s blandfortivpn-keystore -w`). Back up the keystore:
without it, future builds can't be installed over the current app.
