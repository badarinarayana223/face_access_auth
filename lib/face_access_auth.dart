/// Device biometric authentication with optional foreground location capture.
library;

export 'package:geolocator/geolocator.dart'
    show LocationAccuracy, LocationPermission, Position;
export 'package:local_auth/local_auth.dart'
    show BiometricType, LocalAuthException, LocalAuthExceptionCode;

export 'src/backend.dart' show FaceAccessBackend;
export 'src/face_access.dart';
export 'src/models.dart';
