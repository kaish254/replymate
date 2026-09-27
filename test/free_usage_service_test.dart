import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crushreply/services/free_usage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('free usage allows five generations and blocks the sixth', () async {
    SharedPreferences.setMockInitialValues({});
    final service = FreeUsageService();

    expect(await service.remainingToday(), 5);
    for (var use = 0; use < FreeUsageService.dailyLimit; use++) {
      expect(await service.consumeGeneration(), isTrue);
    }
    expect(await service.remainingToday(), 0);
    expect(await service.consumeGeneration(), isFalse);
  });

  test('active Premium bypasses the free usage limit', () async {
    SharedPreferences.setMockInitialValues({});
    final service = FreeUsageService();
    await service.activatePremium(DateTime.now().add(const Duration(days: 30)));

    expect(await service.isPremiumActive(), isTrue);
    expect(await service.remainingToday(), -1);
    expect(await service.consumeGeneration(), isTrue);
  });
}
