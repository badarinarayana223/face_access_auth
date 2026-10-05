# Face access example

Android/iOS demo of device biometrics with disabled, optional, or required
location capture. No coordinates or biometric information are uploaded.

From this directory:

```sh
flutter pub get
flutter run
```

Enroll biometrics in your device settings first. Camera permissions are not
needed. A successful system prompt may use Face ID, fingerprint, or another
supported device biometric; face-only and 3D verification cannot be enforced.

Location is disabled initially. Select a location policy before authenticating.
Required location failures deny access; optional failures are displayed.

Android setup is included (SDK 24+, FragmentActivity, AppCompat, permissions).
The iOS CocoaPods setup requests foreground-only location; build it on macOS
with Xcode and CocoaPods, using CocoaPods integration rather than Swift Package
Manager for this example.

See the [package documentation](../README.md) for setup details and limitations.
