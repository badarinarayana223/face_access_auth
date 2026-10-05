import 'package:geolocator/geolocator.dart';
import 'package:local_auth/local_auth.dart';

/// Determines whether location is needed after successful authentication.
enum LocationCaptureMode {
  /// Never access location services or request location permission.
  disabled,

  /// Report expected location failures without rejecting authentication.
  optional,

  /// Throw if location cannot be captured; access must not be granted.
  required,
}

/// Configuration for one biometric authentication attempt.
class FaceAccessConfig {
  /// Creates configuration. Location capture is disabled by default.
  const FaceAccessConfig({
    this.localizedReason = 'Authenticate to continue',
    this.locationMode = LocationCaptureMode.disabled,
    this.locationAccuracy = LocationAccuracy.high,
    this.locationTimeout = const Duration(seconds: 15),
    this.requestLocationPermission = true,
    this.persistAcrossBackgrounding = false,
    this.sensitiveTransaction = true,
  });

  /// Localized explanation displayed in the system biometric prompt.
  final String localizedReason;

  /// Whether location is disabled, optional, or required.
  final LocationCaptureMode locationMode;

  /// Requested accuracy; the OS may only grant approximate location.
  final LocationAccuracy locationAccuracy;

  /// Maximum time spent acquiring a fix, excluding permission dialogs.
  final Duration locationTimeout;

  /// Whether to ask for permission if it has not already been granted.
  ///
  /// Permanently denied permission is never requested again automatically.
  final bool requestLocationPermission;

  /// Whether the system should retry authentication after backgrounding.
  final bool persistAcrossBackgrounding;

  /// Whether platform-specific confirmation precautions are enabled.
  final bool sensitiveTransaction;
}

/// Biometric capabilities reported by the operating system.
class FaceAccessCapabilities {
  /// Creates an immutable snapshot of capabilities.
  FaceAccessCapabilities({
    required this.canCheckBiometrics,
    required List<BiometricType> enrolledBiometrics,
  }) : enrolledBiometrics = List.unmodifiable(enrolledBiometrics);

  /// Whether the device can check biometrics, not necessarily enrollment.
  final bool canCheckBiometrics;

  /// Available modalities or strength classes; not the method actually used.
  final List<BiometricType> enrolledBiometrics;

  /// Whether biometric hardware and at least one enrollment are available.
  bool get canAuthenticate =>
      canCheckBiometrics && enrolledBiometrics.isNotEmpty;

  /// Whether the OS explicitly reports face authentication as available.
  ///
  /// Android may report only strength classes, so false does not prove
  /// that facial recognition is absent.
  bool get reportsFace => enrolledBiometrics.contains(BiometricType.face);
}

/// An authentication result. No biometric images or templates are exposed.
class FaceAccessResult {
  const FaceAccessResult._({
    required this.authenticated,
    this.location,
    this.locationError,
  }) : assert(location == null || locationError == null);

  /// Creates a rejected authentication result without capturing location.
  const FaceAccessResult.rejected() : this._(authenticated: false);

  /// Creates a successful result, optionally with a location or its error.
  const FaceAccessResult.authenticated({
    Position? location,
    FaceAccessException? locationError,
  }) : this._(
         authenticated: true,
         location: location,
         locationError: locationError,
       );

  /// Whether biometric authentication succeeded.
  ///
  /// Required location failures throw instead of returning this result.
  final bool authenticated;

  /// A fresh foreground position, only obtained after authentication.
  ///
  /// Includes coordinates, timestamp, accuracy, altitude, heading, speed,
  /// and mock-location indicators as supplied by the underlying platform.
  final Position? location;

  /// An expected location failure when location was optional.
  final FaceAccessException? locationError;
}

/// Errors owned by this package. Native biometric errors are propagated.
enum FaceAccessErrorCode {
  /// Only Android and iOS are supported by the default backend.
  unsupportedPlatform,

  /// Another operation is already running on this service instance.
  authenticationInProgress,

  /// Biometric hardware is unavailable.
  biometricsUnavailable,

  /// No usable biometrics are enrolled.
  biometricsNotEnrolled,

  /// The location service is switched off.
  locationServicesDisabled,

  /// Location permission is denied or permission requests were disabled.
  locationPermissionDenied,

  /// The user must enable location permission in system settings.
  locationPermissionDeniedForever,

  /// The requested position could not be acquired within the timeout.
  locationTimedOut,

  /// A native platform error prevented location capture.
  locationPlatformError,
}

/// A structured package error with an optional original cause.
class FaceAccessException implements Exception {
  /// Creates a structured error.
  const FaceAccessException(
    this.code,
    this.message, {
    this.cause,
    this.biometricAuthenticated = false,
  });

  /// Stable error classification.
  final FaceAccessErrorCode code;

  /// Human-readable diagnostic; applications should localize their UI.
  final String message;

  /// Original exception, if one was caught.
  final Object? cause;

  /// Whether biometrics succeeded before a location failure.
  ///
  /// This is diagnostic only. A required-location failure must deny access.
  final bool biometricAuthenticated;

  @override
  String toString() => 'FaceAccessException(${code.name}): $message';
}
