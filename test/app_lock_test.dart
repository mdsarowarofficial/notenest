import 'package:flutter_test/flutter_test.dart';
import 'package:notenest/data/app_lock.dart';

void main() {
  test('the same PIN and salt always give the same hash', () {
    expect(hashPin('abc', '1234'), hashPin('abc', '1234'));
  });

  test('a different salt gives a different hash for the same PIN', () {
    expect(hashPin('abc', '1234'), isNot(hashPin('abd', '1234')));
  });

  test('a different PIN gives a different hash', () {
    expect(hashPin('abc', '1234'), isNot(hashPin('abc', '1235')));
  });

  test('the stored value is not the PIN', () {
    expect(hashPin('abc', '1234').contains('1234'), isFalse);
    expect(hashPin('abc', '1234').length, 64);
  });
}
