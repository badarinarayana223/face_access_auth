# face_access_auth

Device biometric authentication for Flutter with configurable, one-time
foreground location capture. Supports Android and iOS using `local_auth` and
`geolocator`. Requires Flutter 3.38+ and Dart 3.10+.

## What "face access" means

- On compatible Apple devices, the system can authenticate with Face ID, which
  uses Apple's depth-sensing hardware. This package does not access that data.
- Android can authenticate using the biometrics allowed by its system prompt,
  including fingerprints or compatible face recognition.
- **This package cannot enforce face-only authentication, determine which
  biometric actually authenticated, or guarantee 3D face recognition.**
  A reported `BiometricType.strong` is not proof of a 3D face sensor.
- Authentication is biometric-only: PIN, pattern, and passcode fallback are
  disabled. Devices without usable enrolled biometrics fail explicitly.
- There is no camera enrollment, face-image capture, matching database, depth
  map, or independent liveness verification.
- It authenticates a device-enrolled user, not a specific application account.
  Do not treat a returned boolean as server-verifiable identity evidence.

For genuine 3D face enrollment/matching, use supported depth hardware and an
appropriate face/liveness SDK instead.

## Features

- Immutable capability snapshots and typed authentication results.
- Location disabled by default; no location API calls when disabled.
- Optional location: authenticate and report any expected capture failure.
- Required location: reject access if capture fails after biometric success.
- Coordinates, timestamp, accuracy, altitude, heading, speed, and mock-location
  indicators through the exported `Position` type.
- Configurable accuracy, acquisition timeout, permission requests, biometric
  confirmation, and retry after backgrounding.
- Inject a `FaceAccessBackend` for tests or a custom implementation.

## Installation

After publication:

```yaml
dependencies:
  face_access_auth: ^0.1.0
```

Before publication, use a local path dependency to this package.

## Usage

Initialize Flutter bindings before invoking the service outside a running app:

```dart
import 'package:face_access_auth/face_access_auth.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final access = FaceAccess();

  try {
    final result = await access.authenticate(
      config: const FaceAccessConfig(
        localizedReason: 'Authenticate to record attendance',
        locationMode: LocationCaptureMode.required,
        locationAccuracy: LocationAccuracy.high,
        locationTimeout: Duration(seconds: 15),
      ),
    );

    if (!result.authenticated) {
      // Deny access.
      return;
    }
    final position = result.location;
    // Apply your application's authorization and attendance policy.
    // With required location, a successful result includes a position.
    debugPrint('Accuracy: ${position?.accuracy} metres');
  } on FaceAccessException catch (error) {
    // Deny access. A required-location failure throws even when
    // error.biometricAuthenticated is true.
    debugPrint('Access failed: ${error.code.name}');
  } on LocalAuthException catch (error) {
    // Includes native cancellation, lockout, and other biometric failures.
    debugPrint('Biometrics failed: ${error.code.name}');
  }
}
```

Use `LocationCaptureMode.optional` when location must not block authentication.
Always check `result.locationError` and surface that failure to the user.
Set `requestLocationPermission: false` to avoid a permission prompt and report
denial if permission has not already been granted.

```dart
final access = FaceAccess();
final capabilities = await access.getCapabilities();
// capabilities.reportsFace indicates OS-reported availability only.
// Android may report strength classes instead of specific modalities.
final result = await access.authenticate(); // Location disabled.
```

Use one long-lived service per authentication flow. Overlapping operations on
the same instance throw `authenticationInProgress`. `stopAuthentication()`
delegates cancellation of a biometric prompt to the native plugin; it does
not cancel location acquisition or guarantee cancellation succeeds.

### Error contract

| Condition | Outcome |
| --- | --- |
| Biometric prompt returns false | `authenticated == false`, no location calls |
| Native biometric failure or cancellation | Original `LocalAuthException` propagates |
| No biometric hardware or enrollment | `FaceAccessException` |
| Location disabled | Successful result without location or location error |
| Optional location fails | Successful result with `locationError`, no location |
| Required location fails | `FaceAccessException`, access must be denied |
| Unexpected plugin/backend error | Propagates, never silently converted to success |
| Unsupported platform | `unsupportedPlatform` from the default backend |

Known location timeouts, disabled services, permission denial, and native
`PlatformException`s are classified; their original causes are preserved.
The acquisition timeout excludes time spent in permission dialogs.

## Android setup

Minimum Android SDK: **24**. Use the compile SDK required by the resolved Flutter
and plugin versions (at least 35), Java 17, and AndroidX.

In `android/app/build.gradle.kts`:

```kotlin
android {
    compileSdk = flutter.compileSdkVersion
    defaultConfig {
        minSdk = 24
    }
}
```

In `android/app/src/main/AndroidManifest.xml`, as children of `<manifest>`:

```xml
<uses-permission android:name="android.permission.USE_BIOMETRIC" />
<!-- Only needed when your application enables location capture. -->
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

Use `FlutterFragmentActivity`, not `FlutterActivity`, in your `MainActivity`:

```kotlin
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

Use an AppCompat theme for `LaunchTheme` and `NormalTheme` in both
`res/values/styles.xml` and `res/values-night/styles.xml`, for example
`parent="Theme.AppCompat.DayNight.NoActionBar"`.

Do not add background-location permission for this package's single foreground
fix. Android users can grant approximate location even when precise location
is requested; requested accuracy is not a guarantee.

## iOS setup

Minimum deployment target: **iOS 13**. In `ios/Runner/Info.plist`:

```xml
<key>NSFaceIDUsageDescription</key>
<string>Authenticate with Face ID to access your account.</string>
<!-- Only needed when your application enables location capture. -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>Record your location after you authenticate.</string>
```

Customize these explanations for your application and localize them as needed.
No camera permission is needed.

For foreground-only location, set `BYPASS_PERMISSION_LOCATION_ALWAYS=1` on the
`geolocator_apple` target. For CocoaPods, add this inside the existing
`post_install` target loop, preserving `flutter_additional_ios_build_settings`:

```ruby
if target.name == 'geolocator_apple'
  target.build_configurations.each do |config|
    config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['$(inherited)']
    config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] << 'BYPASS_PERMISSION_LOCATION_ALWAYS=1'
  end
end
```

The example includes this CocoaPods setup. If your Flutter installation enables
Swift Package Manager, use CocoaPods integration for this example (disable
Swift Package Manager in your development configuration before building it).
For Swift Package Manager applications, the equivalent compiler definition must
be applied to the geolocator Apple dependency, not only the Runner target;
follow the resolved geolocator version's setup documentation.
Do not enable background location modes just to obtain a foreground fix.

## Privacy and authorization

This package does not store, upload, or log biometric information or coordinates.
The example displays coordinates on-screen only. Obtain informed consent,
explain your usage, and apply your own retention and data-protection policies.
Permission prompts still remain under OS control.

GPS may be approximate or spoofed; `Position.isMocked` is only a platform signal,
not proof of authenticity. Neither biometric success nor a GPS fix alone should
authorize a high-risk action. Account verification, geofencing, freshness,
maximum acceptable accuracy, and server authorization belong to your app.

Web and desktop are deliberately unsupported by the default backend: some
desktop APIs cannot enforce biometric-only authentication.

## Example and validation

The [example](example/) includes Android/iOS configuration and a selectable
location policy. Enroll device biometrics and run on a supported device:

```sh
cd example
flutter run
```

From the package directory:

```sh
flutter analyze
flutter test test/face_access_auth_test.dart
cd example
flutter test test/widget_test.dart
cd ..
dart pub publish --dry-run
```

Unit tests use a fake backend. They do not certify physical Face ID, Android
biometrics, GPS, or iOS integration. Test those on real devices before release.

## Publishing

MIT licensed; see [LICENSE](LICENSE).

Before the first release:

1. Confirm the package name is available and your pub.dev account can publish it.
2. Confirm the repository and issue tracker URLs in `pubspec.yaml` are correct.
3. Confirm copyright attribution in `LICENSE`.
4. Verify Android and iOS behavior on devices, including denied permission,
   lockout, cancellation, approximate location, and services disabled.
5. Run the validation commands above and review the dry-run archive.
6. Run `dart pub publish` and approve publication with your pub.dev account.

Publishing is not performed automatically. A published version cannot be
replaced, so finish these checks before uploading.

Source and bug reports:
[GitHub repository](https://github.com/badarinarayana223/face_access_auth) and
[issue tracker](https://github.com/badarinarayana223/face_access_auth/issues).
