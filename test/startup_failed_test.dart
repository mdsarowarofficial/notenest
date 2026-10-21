import 'package:flutter_test/flutter_test.dart';
import 'package:notenest/screens/startup_failed.dart';

void main() {
  testWidgets('a failed start says nothing was deleted and can try again',
      (tester) async {
    var tries = 0;
    await tester.pumpWidget(StartupFailedApp(
      error: StateError('disk full'),
      retry: () async => tries++,
    ));

    expect(find.textContaining("couldn't open your notes"), findsOneWidget);
    expect(find.textContaining('Nothing has been deleted'), findsOneWidget);
    expect(find.textContaining('disk full'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(tries, 1);
    // Back to a usable button once the attempt returns.
    expect(find.text('Try again'), findsOneWidget);
  });
}
