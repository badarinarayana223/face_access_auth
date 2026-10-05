import 'dart:async';

import 'package:face_access_auth/face_access_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart'
    show LocationServiceDisabledException, PermissionDeniedException;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBackend backend;
  late FaceAccess access;

  setUp(() {
    backend = FakeBackend();
    access = FaceAccess(backend: backend);
  });

  TypeMatcher<FaceAccessException> errorCode(FaceAccessErrorCode code) =>
      isA<FaceAccessException>().having((error) => error.code, 'code', code);

  test('default configuration never accesses location', () async {
    final result = await access.authenticate();
    expect(result.authenticated, isTrue);
    expect(result.location, isNull);
    expect(result.locationError, isNull);
    expect(backend.calls, ['hardware', 'enrollment', 'authenticate']);
    expect(backend.config?.sensitiveTransaction, isTrue);
    expect(backend.config?.persistAcrossBackgrounding, isFalse);
  });

  test('rejected biometrics do not access required location', () async {
    backend.authenticated = false;
    final result = await access.authenticate(
      config: const FaceAccessConfig(
        locationMode: LocationCaptureMode.required,
      ),
    );
    expect(result.authenticated, isFalse);
    expect(backend.calls, ['hardware', 'enrollment', 'authenticate']);
  });

  test(
    'capabilities are immutable and distinguish face from strength',
    () async {
      backend.biometrics = [BiometricType.strong];
      final capabilities = await access.getCapabilities();
      expect(capabilities.canAuthenticate, isTrue);
      expect(capabilities.reportsFace, isFalse);
      backend.biometrics.clear();
      expect(capabilities.enrolledBiometrics, [BiometricType.strong]);
      expect(
        () => capabilities.enrolledBiometrics.add(BiometricType.face),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'face capability is reported without claiming the method used',
    () async {
      expect((await access.getCapabilities()).reportsFace, isTrue);
    },
  );

  test('missing hardware fails before enrollment or authentication', () async {
    backend.hardware = false;
    await expectLater(
      access.authenticate(),
      throwsA(errorCode(FaceAccessErrorCode.biometricsUnavailable)),
    );
    expect(backend.calls, ['hardware']);
  });

  test('missing enrollment fails before authentication', () async {
    backend.biometrics = [];
    await expectLater(
      access.authenticate(),
      throwsA(errorCode(FaceAccessErrorCode.biometricsNotEnrolled)),
    );
    expect(backend.calls, ['hardware', 'enrollment']);
  });

  for (final mode in [
    LocationCaptureMode.optional,
    LocationCaptureMode.required,
  ]) {
    test('$mode captures a fresh position after biometrics', () async {
      const timeout = Duration(seconds: 9);
      final result = await access.authenticate(
        config: FaceAccessConfig(
          locationMode: mode,
          locationAccuracy: LocationAccuracy.medium,
          locationTimeout: timeout,
          localizedReason: 'Verify attendance',
          persistAcrossBackgrounding: true,
          sensitiveTransaction: false,
        ),
      );
      expect(result.authenticated, isTrue);
      expect(result.location, same(backend.position));
      expect(result.location?.timestamp, DateTime.utc(2026, 1, 1));
      expect(result.locationError, isNull);
      expect(backend.calls, [
        'hardware',
        'enrollment',
        'authenticate',
        'services',
        'permission',
        'fix',
      ]);
      expect(backend.config?.localizedReason, 'Verify attendance');
      expect(backend.config?.locationAccuracy, LocationAccuracy.medium);
      expect(backend.config?.locationTimeout, timeout);
      expect(backend.config?.persistAcrossBackgrounding, isTrue);
      expect(backend.config?.sensitiveTransaction, isFalse);
    });
  }

  test('requests denied permission once and then captures', () async {
    backend.permission = LocationPermission.denied;
    final result = await access.authenticate(
      config: const FaceAccessConfig(
        locationMode: LocationCaptureMode.required,
      ),
    );
    expect(result.location, isNotNull);
    expect(backend.calls, contains('request'));
  });

  final permissionCases = {
    LocationPermission.denied: FaceAccessErrorCode.locationPermissionDenied,
    LocationPermission.deniedForever:
        FaceAccessErrorCode.locationPermissionDeniedForever,
    LocationPermission.unableToDetermine:
        FaceAccessErrorCode.locationPermissionDenied,
  };
  for (final entry in permissionCases.entries) {
    test('${entry.key} is explicit and does not acquire a fix', () async {
      backend.permission = entry.key;
      final result = await access.authenticate(
        config: const FaceAccessConfig(
          locationMode: LocationCaptureMode.optional,
          requestLocationPermission: false,
        ),
      );
      expect(result.authenticated, isTrue);
      expect(result.locationError?.code, entry.value);
      expect(result.locationError?.biometricAuthenticated, isTrue);
      expect(backend.calls, isNot(contains('request')));
      expect(backend.calls, isNot(contains('fix')));
    });
  }

  test('permission remaining denied after request is a failure', () async {
    backend.permission = LocationPermission.denied;
    backend.requestedPermission = LocationPermission.denied;
    await expectLater(
      access.authenticate(
        config: const FaceAccessConfig(
          locationMode: LocationCaptureMode.required,
        ),
      ),
      throwsA(errorCode(FaceAccessErrorCode.locationPermissionDenied)),
    );
    expect(backend.calls.where((call) => call == 'request'), hasLength(1));
    expect(backend.calls, isNot(contains('fix')));
  });

  test('permanent denial is never requested again', () async {
    backend.permission = LocationPermission.deniedForever;
    await expectLater(
      access.authenticate(
        config: const FaceAccessConfig(
          locationMode: LocationCaptureMode.required,
        ),
      ),
      throwsA(errorCode(FaceAccessErrorCode.locationPermissionDeniedForever)),
    );
    expect(backend.calls, isNot(contains('request')));
  });

  test('optional disabled location services are reported', () async {
    backend.services = false;
    final result = await access.authenticate(
      config: const FaceAccessConfig(
        locationMode: LocationCaptureMode.optional,
      ),
    );
    expect(result.authenticated, isTrue);
    expect(
      result.locationError?.code,
      FaceAccessErrorCode.locationServicesDisabled,
    );
    expect(backend.calls, isNot(contains('permission')));
  });

  test(
    'required disabled services deny access after biometric success',
    () async {
      backend.services = false;
      await expectLater(
        access.authenticate(
          config: const FaceAccessConfig(
            locationMode: LocationCaptureMode.required,
          ),
        ),
        throwsA(
          errorCode(FaceAccessErrorCode.locationServicesDisabled).having(
            (error) => error.biometricAuthenticated,
            'biometricAuthenticated',
            isTrue,
          ),
        ),
      );
    },
  );

  final nativeErrors = <Object, FaceAccessErrorCode>{
    TimeoutException('No fix'): FaceAccessErrorCode.locationTimedOut,
    const LocationServiceDisabledException():
        FaceAccessErrorCode.locationServicesDisabled,
    const PermissionDeniedException('Denied'):
        FaceAccessErrorCode.locationPermissionDenied,
    PlatformException(code: 'LOCATION_FAILED'):
        FaceAccessErrorCode.locationPlatformError,
  };
  for (final entry in nativeErrors.entries) {
    test('optional ${entry.key.runtimeType} retains its cause', () async {
      backend.locationError = entry.key;
      final result = await access.authenticate(
        config: const FaceAccessConfig(
          locationMode: LocationCaptureMode.optional,
        ),
      );
      expect(result.locationError?.code, entry.value);
      expect(result.locationError?.cause, same(entry.key));
      expect(result.location, isNull);
    });
  }

  test('unknown location errors propagate even in optional mode', () async {
    final error = StateError('Unexpected backend error');
    backend.locationError = error;
    await expectLater(
      access.authenticate(
        config: const FaceAccessConfig(
          locationMode: LocationCaptureMode.optional,
        ),
      ),
      throwsA(same(error)),
    );
  });

  test('service bounds a backend that does not enforce the timeout', () async {
    backend.pendingPosition = Completer<Position>();
    final result = await access.authenticate(
      config: const FaceAccessConfig(
        locationMode: LocationCaptureMode.optional,
        locationTimeout: Duration(milliseconds: 1),
      ),
    );
    expect(result.locationError?.code, FaceAccessErrorCode.locationTimedOut);
    backend.pendingPosition!.complete(backend.position);
  });

  test(
    'native cancellation propagates and the service can be reused',
    () async {
      const error = LocalAuthException(
        code: LocalAuthExceptionCode.userCanceled,
      );
      backend.authError = error;
      await expectLater(access.authenticate(), throwsA(same(error)));
      backend.authError = null;
      expect((await access.authenticate()).authenticated, isTrue);
    },
  );

  test('concurrent authentication fails explicitly', () async {
    backend.pendingAuth = Completer<bool>();
    final first = access.authenticate();
    await expectLater(
      access.authenticate(),
      throwsA(errorCode(FaceAccessErrorCode.authenticationInProgress)),
    );
    backend.pendingAuth!.complete(true);
    expect((await first).authenticated, isTrue);
  });

  test('stop delegates to the native backend', () async {
    expect(await access.stopAuthentication(), isTrue);
    expect(backend.calls, ['stop']);
  });

  test('configuration is validated before invoking native APIs', () async {
    for (final config in [
      const FaceAccessConfig(localizedReason: '  '),
      const FaceAccessConfig(locationTimeout: Duration.zero),
      const FaceAccessConfig(locationTimeout: Duration(seconds: -1)),
    ]) {
      await expectLater(
        access.authenticate(config: config),
        throwsArgumentError,
      );
    }
    expect(backend.calls, isEmpty);
  });

  test('default backend explicitly rejects unsupported platforms', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await expectLater(
      FaceAccess().getCapabilities(),
      throwsA(errorCode(FaceAccessErrorCode.unsupportedPlatform)),
    );
  });

  test('default backend forces biometric-only native authentication', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('plugins.flutter.io/local_auth');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodCall? authenticationCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getAvailableBiometrics':
          return ['face'];
        case 'authenticate':
          authenticationCall = call;
          return true;
        default:
          throw StateError('Unexpected method: ${call.method}');
      }
    });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    });

    final result = await FaceAccess().authenticate(
      config: const FaceAccessConfig(
        localizedReason: 'Verify access',
        persistAcrossBackgrounding: true,
        sensitiveTransaction: false,
      ),
    );
    expect(result.authenticated, isTrue);
    expect(authenticationCall?.arguments, containsPair('biometricOnly', true));
    expect(authenticationCall?.arguments, containsPair('stickyAuth', true));
    expect(
      authenticationCall?.arguments,
      containsPair('sensitiveTransaction', false),
    );
    expect(
      authenticationCall?.arguments,
      containsPair('localizedReason', 'Verify access'),
    );
  });
}

class FakeBackend implements FaceAccessBackend {
  final calls = <String>[];
  bool hardware = true;
  List<BiometricType> biometrics = [BiometricType.face];
  bool authenticated = true;
  bool services = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission requestedPermission = LocationPermission.whileInUse;
  Object? authError;
  Object? locationError;
  Completer<bool>? pendingAuth;
  Completer<Position>? pendingPosition;
  FaceAccessConfig? config;
  final position = Position(
    latitude: 17.4,
    longitude: 78.5,
    timestamp: DateTime.utc(2026, 1, 1),
    accuracy: 5,
    altitude: 500,
    altitudeAccuracy: 10,
    heading: 0,
    headingAccuracy: 1,
    speed: 0,
    speedAccuracy: 1,
  );

  @override
  Future<bool> canCheckBiometrics() async {
    calls.add('hardware');
    return hardware;
  }

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async {
    calls.add('enrollment');
    return biometrics;
  }

  @override
  Future<bool> authenticate(FaceAccessConfig config) async {
    calls.add('authenticate');
    this.config = config;
    if (authError case final error?) throw error;
    return pendingAuth?.future ?? Future.value(authenticated);
  }

  @override
  Future<bool> stopAuthentication() async {
    calls.add('stop');
    return true;
  }

  @override
  Future<bool> isLocationServiceEnabled() async {
    calls.add('services');
    return services;
  }

  @override
  Future<LocationPermission> checkLocationPermission() async {
    calls.add('permission');
    return permission;
  }

  @override
  Future<LocationPermission> requestLocationPermission() async {
    calls.add('request');
    return requestedPermission;
  }

  @override
  Future<Position> getCurrentPosition(FaceAccessConfig config) async {
    calls.add('fix');
    this.config = config;
    if (locationError case final error?) throw error;
    return pendingPosition?.future ?? Future.value(position);
  }
}
