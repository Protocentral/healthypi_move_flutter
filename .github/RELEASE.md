GitHub Actions: Release secrets & setup

This file lists the GitHub secrets and minimal setup required to use the workflows in `.github/workflows/`.

Android (Google Play)
- Required secret: `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`
  - Value: the JSON contents of a Google Play service account (create a service account in Google Play Console and grant `Release` permissions). Store the JSON as a secret.
  - The workflow publishes to the `internal` track by default. Change `.github/workflows/android-deploy.yml` to modify `track` or package name.
- Ensure `packageName` in the workflow matches the app id in `move/android/app/src/main/AndroidManifest.xml` (default: `com.protocentral.healthypi_move`).

iOS (App Store)
- Required secrets:
  - `APP_STORE_CONNECT_API_KEY` — the JSON content of the App Store Connect API key (the key downloaded from Apple; the workflow writes this to a file at runtime).
  - `APP_SPECIFIC_PASSWORD` — an app-specific password for uploading builds (or configure Fastlane App Store Connect auth via environment variables or credentials manager).
  - Optionally: `FASTLANE_SESSION` or other Fastlane-specific secrets if you use fastlane match or other flows.
- The workflow assumes a `fastlane` configuration exists under `move/ios/fastlane` and there's a `release` lane that uploads to App Store Connect. If not present, initialize Fastlane in `move/ios` and add a `release` lane.

Notes & limitations
- These workflows run in CI and will only succeed if the repository has correct signing credentials (Android keystore and iOS signing certs/profiles). For Android, use `android/key.properties` and store sensitive keystore contents in a secure place (or use GitHub Secrets + Fastlane match). For iOS, set up code signing with Fastlane match or provide provisioning profiles and certificates via secrets.
- CI cannot interactively unlock macOS Keychain; for production iOS builds use Fastlane match and App Store Connect API keys for non-interactive uploads.
- This repository's Flutter code is in `move/` — all build commands run from there.
