import 'dart:async';

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:local_auth/local_auth.dart';

import 'backend.dart';
import 'models.dart';

/// Authenticates with device biometrics, then optionally captures location.
///
/// This verifies a device-enrolled user, not an application account's identity.
/// Neither the exact modality used nor verified 3D support is exposed by the OS.
class FaceAccess {
  /// Uses native plugins by default, or a supplied backend for testing.
  FaceAccess({FaceAccessBackend? backend})
    : _backend = backend ?? DeviceFaceAccessBackend();

  final FaceAccessBackend _backend;
  bool _inProgress = false;

  /// Returns an immutable snapshot without opening an authentication prompt.
  Future<FaceAccessCapabilities> getCapabilities() async {
    final supported = await _backend.canCheckBiometrics();
    return FaceAccessCapabilities(
      canCheckBiometrics: supported,
      enrolledBiometrics: supported
          ? await _backend.getAvailableBiometrics()
          : [],
    );
  }

  /// Performs biometric-only authentication.
  ///
  /// A false native result returns [FaceAccessResult.rejected]; native
  /// [LocalAuthException] errors (including cancellation and lockout) propagate.
  /// Location is never accessed before a successful biometric challenge.
  /// Required-location failures throw [FaceAccessException]; optional-location
  /// failures are visible in [FaceAccessResult.locationError].
  /// Unexpected errors always propagate.
  Future<FaceAccessResult> authenticate({
    FaceAccessConfig config = const FaceAccessConfig(),
  }) async {
    if (config.localizedReason.trim().isEmpty) {
      throw ArgumentError.value(
        config.localizedReason,
        'localizedReason',
        'Must not be empty.',
      );
    }
    if (config.locationTimeout <= Duration.zero) {
      throw ArgumentError.value(
        config.locationTimeout,
        'locationTimeout',
        'Must be positive.',
      );
    }
    if (_inProgress) {
      throw const FaceAccessException(
        FaceAccessErrorCode.authenticationInProgress,
        'An authentication or location capture is already in progress.',
      );
    }
    _inProgress = true;
    try {
      final capabilities = await getCapabilities();
      if (!capabilities.canCheckBiometrics) {
        throw const FaceAccessException(
          FaceAccessErrorCode.biometricsUnavailable,
          'Biometric hardware is unavailable.',
        );
      }
      if (!capabilities.canAuthenticate) {
        throw const FaceAccessException(
          FaceAccessErrorCode.biometricsNotEnrolled,
          'No usable biometrics are enrolled.',
        );
      }
      if (!await _backend.authenticate(config)) {
        return const FaceAccessResult.rejected();
      }
      if (config.locationMode == LocationCaptureMode.disabled) {
        return const FaceAccessResult.authenticated();
      }
      try {
        final position = await _captureLocation(config);
        return FaceAccessResult.authenticated(location: position);
      } on FaceAccessException catch (error) {
        if (config.locationMode == LocationCaptureMode.required) {
          rethrow;
        }
        return FaceAccessResult.authenticated(locationError: error);
      }
    } finally {
      _inProgress = false;
    }
  }

  /// Cancels the native biometric prompt. Does not cancel location capture.
  Future<bool> stopAuthentication() => _backend.stopAuthentication();

  Future<Position> _captureLocation(FaceAccessConfig config) async {
    FaceAccessException failure(
      FaceAccessErrorCode code,
      String message, [
      Object? cause,
    ]) => FaceAccessException(
      code,
      message,
      cause: cause,
      biometricAuthenticated: true,
    );

    try {
      if (!await _backend.isLocationServiceEnabled()) {
        throw failure(
          FaceAccessErrorCode.locationServicesDisabled,
          'Location services are disabled.',
        );
      }
      var permission = await _backend.checkLocationPermission();
      if (permission == LocationPermission.denied &&
          config.requestLocationPermission) {
        permission = await _backend.requestLocationPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw failure(
          FaceAccessErrorCode.locationPermissionDeniedForever,
          'Enable location permission in system settings.',
        );
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        throw failure(
          FaceAccessErrorCode.locationPermissionDenied,
          'Foreground location permission was not granted.',
        );
      }
      // Also bound custom backends that do not enforce the native time limit.
      return await _backend
          .getCurrentPosition(config)
          .timeout(config.locationTimeout);
    } on TimeoutException catch (error) {
      throw failure(
        FaceAccessErrorCode.locationTimedOut,
        'Location capture timed out.',
        error,
      );
    } on LocationServiceDisabledException catch (error) {
      throw failure(
        FaceAccessErrorCode.locationServicesDisabled,
        'Location services were disabled during capture.',
        error,
      );
    } on PermissionDeniedException catch (error) {
      throw failure(
        FaceAccessErrorCode.locationPermissionDenied,
        'Location permission was denied during capture.',
        error,
      );
    } on PlatformException catch (error) {
      throw failure(
        FaceAccessErrorCode.locationPlatformError,
        'The platform could not capture location: ${error.code}.',
        error,
      );
    }
  }
}
