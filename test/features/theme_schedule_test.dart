import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/features/settings/domain/app_settings.dart';

DateTime _at(int h, int m) => DateTime(2026, 11, 25, h, m);

void main() {
  const night = AppSettings(
    themeSchedule: true,
    darkFromMinutes: 19 * 60,
    darkToMinutes: 7 * 60,
  );

  test('window that crosses midnight', () {
    expect(isDarkBySchedule(night, _at(19, 0)), isTrue);
    expect(isDarkBySchedule(night, _at(23, 59)), isTrue);
    expect(isDarkBySchedule(night, _at(0, 0)), isTrue);
    expect(isDarkBySchedule(night, _at(6, 59)), isTrue);
    expect(isDarkBySchedule(night, _at(7, 0)), isFalse);
    expect(isDarkBySchedule(night, _at(12, 30)), isFalse);
    expect(isDarkBySchedule(night, _at(18, 59)), isFalse);
  });

  test('window inside one day', () {
    const s = AppSettings(
      themeSchedule: true,
      darkFromMinutes: 9 * 60,
      darkToMinutes: 17 * 60,
    );
    expect(isDarkBySchedule(s, _at(8, 59)), isFalse);
    expect(isDarkBySchedule(s, _at(9, 0)), isTrue);
    expect(isDarkBySchedule(s, _at(16, 59)), isTrue);
    expect(isDarkBySchedule(s, _at(17, 0)), isFalse);
  });

  test('equal times never turn dark', () {
    const s = AppSettings(
      themeSchedule: true,
      darkFromMinutes: 600,
      darkToMinutes: 600,
    );
    expect(isDarkBySchedule(s, _at(10, 0)), isFalse);
    expect(isDarkBySchedule(s, _at(3, 0)), isFalse);
  });

  test('schedule settings survive a JSON round trip and are clamped', () {
    final back = AppSettings.fromJson(night.toJson());
    expect(back.themeSchedule, isTrue);
    expect(back.darkFromMinutes, 1140);
    expect(back.darkToMinutes, 420);
    final wild = AppSettings.fromJson(<String, dynamic>{
      'darkFromMinutes': 99999,
      'darkToMinutes': -5,
    });
    expect(wild.darkFromMinutes, 1439);
    expect(wild.darkToMinutes, 0);
    expect(const AppSettings().themeSchedule, isFalse);
  });
}
