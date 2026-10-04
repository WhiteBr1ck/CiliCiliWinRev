# Isolated updater verification

Build and package 0.7.0 first. Run `prepare.ps1` with Inno Setup 7 and Visual Studio CMake paths, then `run_helper_tests.ps1 -Mode success`. Other modes are `cancel`, `no-commit`, `bad-hash`, `wrong-version`, and `install-failure`. The last mode displays an error dialog; dismiss it to let the fixture assert restart and retention of the failed installer.

These tests use a separate QA AppId and Start menu group. They refuse to replace an existing QA registration and never launch the real client, read account sessions, or modify the everyday installation. The parent and restarted application are native fixtures named CiliCiliWinRev.exe. Results are written below `.research/helper-test-*`.

The success test installs an earlier QA package, runs the production helper against a QA installer, checks install location, version, every packaged file hash, restart, downloaded-installer deletion, and unchanged external fixture data, then uninstalls. If the original 0.6.1 QA package is unavailable, preparation generates a fixture baseline with a 0.6.1 uninstall registration. That fallback proves handoff behavior, not compatibility with the original app. Verify real-version install/upgrade/uninstall separately before publishing.

`flutter test integration_test/update_smoke_test.dart -d windows` checks the actual MD3 dialog, no download before confirmation, cancellation and retry, and Dart verification of the locally built signed setup. Run `generate_update_manifest.ps1` before it. Native preparation and shutdown are deliberately injected so this test never installs anything or exits the daily client. It also checks that native automatic installation rejects a development checkout.
