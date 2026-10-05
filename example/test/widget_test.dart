import 'package:face_access_auth_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the demo with location disabled by default', (
    tester,
  ) async {
    await tester.pumpWidget(const FaceAccessExample());
    expect(find.text('Face access + location'), findsOneWidget);
    expect(find.text('disabled'), findsOneWidget);
    expect(find.text('Authenticate'), findsOneWidget);
    expect(find.textContaining('Face-only and 3D'), findsOneWidget);
  });
}
