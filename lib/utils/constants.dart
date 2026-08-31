/// Application-wide constants.
library;

/// Default Dhikr entries pre-seeded in the database.
const List<Map<String, String>> kDefaultDhikr = [
  {'name': 'SubhanAllah', 'arabic': 'سُبْحَانَ اللَّهِ'},
  {'name': 'Alhamdulillah', 'arabic': 'الْحَمْدُ لِلَّهِ'},
  {'name': 'Allahu Akbar', 'arabic': 'اللَّهُ أَكْبَرُ'},
  {'name': 'Astaghfirullah', 'arabic': 'أَسْتَغْفِرُ اللَّهَ'},
  {'name': 'La ilaha illallah', 'arabic': 'لَا إِلَهَ إِلَّا اللَّهُ'},
];

/// Default target count per session.
const int kDefaultTarget = 33;

/// Minimum touch target size in logical pixels.
const double kMinTouchTarget = 48.0;

/// Counter button radius.
const double kCounterButtonRadius = 100.0;

/// Animation durations.
const Duration kTapAnimDuration = Duration(milliseconds: 100);
const Duration kPageTransDuration = Duration(milliseconds: 300);

/// Settings keys.
const String kPrefVibration = 'vibration';
const String kPrefSound = 'sound';
const String kPrefTheme = 'theme';
const String kPrefDefaultTarget = 'default_target';
