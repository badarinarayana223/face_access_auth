import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:local_auth/local_auth.dart';

import 'models.dart';

/// Injectable boundary for platform operations, useful for testing.
abstract interface class FaceAccessBackend {
  /// Returns whether biometric hardware is available.
  Future<bool> canCheckBiometrics();

  /// Returns usable enrolled biometric modalities or strength classes.
  Future<List<BiometricType>> getAvailableBiometrics();

  /// Performs biometric-only authentication. Never permit credential fallback.
  Future<bool> authenticate(FaceAccessConfig config);

  /// Stops a pending biometric prompt, not an ongoing location acquisition.
  Future<bool> stopAuthentication();

  /// Returns whether location services are enabled.
  Future<bool> isLocationServiceEnabled();

  /// Checks foreground location permission.
  Future<LocationPermission> checkLocationPermission();

  /// Requests foreground location permission.
  Future<LocationPermission> requestLocationPermission();

  /// Obtains a fresh fix with the configured accuracy and timeout.
  Future<Position> getCurrentPosition(FaceAccessConfig config);
}

/// Default Android/iOS backend.
class DeviceFaceAccessBackend implements FaceAccessBackend {
  final LocalAuthentication _auth = LocalAuthentication();

  void _ensureSupported() {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      throw const FaceAccessException(
        FaceAccessErrorCode.unsupportedPlatform,
        'Device biometric access is supported only on Android and iOS.',
      );
    }
  }

  @override
  Future<bool> canCheckBiometrics() {
    _ensureSupported();
    return _auth.canCheckBiometrics;
  }

  @override
  Future<List<BiometricType>> getAvailableBiometrics() {
    _ensureSupported();
    return _auth.getAvailableBiometrics();
  }

  @override
  Future<bool> authenticate(FaceAccessConfig config) {
    _ensureSupported();
    return _auth.authenticate(
      localizedReason: config.localizedReason,
      biometricOnly: true,
      sensitiveTransaction: config.sensitiveTransaction,
      persistAcrossBackgrounding: config.persistAcrossBackgrounding,
    );
  }

  @override
  Future<bool> stopAuthentication() {
    _ensureSupported();
    return _auth.stopAuthentication();
  }

  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkLocationPermission() =>
      Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestLocationPermission() =>
      Geolocator.requestPermission();

  @override
  Future<Position> getCurrentPosition(FaceAccessConfig config) =>
      Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: config.locationAccuracy,
          timeLimit: config.locationTimeout,
        ),
      );
}
