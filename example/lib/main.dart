import 'package:face_access_auth/face_access_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const FaceAccessExample());

class FaceAccessExample extends StatelessWidget {
  const FaceAccessExample({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Face access',
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    home: const AccessPage(),
  );
}

class AccessPage extends StatefulWidget {
  const AccessPage({super.key});

  @override
  State<AccessPage> createState() => _AccessPageState();
}

class _AccessPageState extends State<AccessPage> {
  final _access = FaceAccess();
  LocationCaptureMode _mode = LocationCaptureMode.disabled;
  bool _busy = false;
  String _status = 'Authenticate using the biometrics enrolled on this device.';

  Future<void> _authenticate() async {
    setState(() {
      _busy = true;
      _status = 'Waiting for authentication...';
    });
    try {
      final result = await _access.authenticate(
        config: FaceAccessConfig(
          localizedReason: 'Authenticate to access this demo',
          locationMode: _mode,
        ),
      );
      final position = result.location;
      final message = !result.authenticated
          ? 'Authentication was not completed. Access denied.'
          : result.locationError != null
          ? 'Authenticated. Optional location failed: ${result.locationError}'
          : position == null
          ? 'Authenticated. Location was not requested.'
          : 'Authenticated.\n'
                'Latitude: ${position.latitude}\n'
                'Longitude: ${position.longitude}\n'
                'Accuracy: ${position.accuracy} m\n'
                'Captured: ${position.timestamp.toIso8601String()}\n'
                'Mock location reported: ${position.isMocked}';
      if (mounted) setState(() => _status = message);
    } on FaceAccessException catch (error) {
      if (mounted) setState(() => _status = 'Access denied. $error');
    } on LocalAuthException catch (error) {
      if (mounted) {
        setState(() => _status = 'Access denied. Biometrics: ${error.code.name}');
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _status = 'Platform configuration error: ${error.code}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Face access + location')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Uses Face ID or other enrolled device biometrics. '
            'Face-only and 3D authentication cannot be guaranteed. '
            'No face images are captured.',
          ),
          const SizedBox(height: 24),
          DropdownButtonFormField<LocationCaptureMode>(
            initialValue: _mode,
            decoration: const InputDecoration(labelText: 'Location policy'),
            items: LocationCaptureMode.values
                .map(
                  (mode) => DropdownMenuItem(
                    value: mode,
                    child: Text(mode.name),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (mode) {
                    if (mode != null) setState(() => _mode = mode);
                  },
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _authenticate,
            icon: const Icon(Icons.lock),
            label: Text(_busy ? 'Please wait...' : 'Authenticate'),
          ),
          const SizedBox(height: 24),
          SelectableText(_status),
        ],
      ),
    ),
  );
}
