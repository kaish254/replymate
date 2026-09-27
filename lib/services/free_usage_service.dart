import 'package:shared_preferences/shared_preferences.dart';

class FreeUsageService {
  static const dailyLimit = 5;
  static const _countKey = 'free_generation_count';
  static const _dateKey = 'free_generation_date';

  Future<int> remainingToday() async {
    final preferences = await SharedPreferences.getInstance();
    if (await isPremiumActive()) return -1;
    final today = _today;
    if (preferences.getString(_dateKey) != today) {
      await preferences.setString(_dateKey, today);
      await preferences.setInt(_countKey, 0);
      return dailyLimit;
    }
    final count = preferences.getInt(_countKey) ?? 0;
    return (dailyLimit - count).clamp(0, dailyLimit);
  }

  Future<bool> consumeGeneration() async {
    if (await isPremiumActive()) return true;
    final remaining = await remainingToday();
    if (remaining == 0) return false;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_countKey, dailyLimit - remaining + 1);
    return true;
  }

  Future<bool> isPremiumActive() async {
    final preferences = await SharedPreferences.getInstance();
    final expiryMilliseconds = preferences.getInt('premium_expires_at');
    return expiryMilliseconds != null &&
        DateTime.fromMillisecondsSinceEpoch(expiryMilliseconds)
            .isAfter(DateTime.now());
  }

  Future<void> activatePremium(DateTime expiresAt) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(
      'premium_expires_at',
      expiresAt.millisecondsSinceEpoch,
    );
  }

  String get _today {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }
}
