/// One place for settings the owner may change.
class AppConfig {
  AppConfig._();

  static const appName = 'Laundry Desk';
  static const company = 'BrotriX Technologies';
  static const version = '0.1.0';

  /// Firebase (one-time setup, see README "Firebase chalu karna").
  /// While these are empty the app runs in DEMO MODE: accounts and the
  /// shop profile are kept only on this phone.
  static const firebaseApiKey = '';
  static const firebaseAppId = '';
  static const firebaseSenderId = '';
  static const firebaseProjectId = '';
  static const firebaseStorageBucket = '';

  static bool get firebaseReady =>
      firebaseApiKey.isNotEmpty && firebaseAppId.isNotEmpty && firebaseProjectId.isNotEmpty;

  /// New shops start with a Premium trial.
  static const trialDays = 14;

  /// Testing: everything open. Set true before Play Store launch.
  static const enforcePremium = false;

  /// Suggested prices in ₹: Monthly, 6 months, 1 year (owner to approve).
  /// For comparison, Indian laundry software lists ₹1,499–₹2,499 per month.
  static const planPrices = <String, List<int>>{
    'pro': [499, 2499, 4499],
    'business': [999, 4999, 8999],
  };

  /// BrotriX admin screen (More → tap the version 7 times). Change before launch.
  static const superAdminPin = '2468';

  /// Modules. Free ones stay on after the trial; the rest need a plan.
  static const freeModules = ['orders', 'customers', 'bills', 'basicReports'];
  static const premiumModules = [
    'whatsapp',
    'staffTracking',
    'delivery',
    'barcode',
    'multiBranch',
    'advancedReports',
  ];

  static const services = [
    'Wash & fold',
    'Wash & iron',
    'Dry clean',
    'Steam iron',
    'Shoe cleaning',
    'Carpet & curtain',
    'Blanket / bedding',
    'Stain removal',
  ];

  static const countries = <String, String>{
    'India': 'INR',
    'United Arab Emirates': 'AED',
    'Saudi Arabia': 'SAR',
    'United Kingdom': 'GBP',
    'United States': 'USD',
    'Canada': 'CAD',
    'Australia': 'AUD',
    'Singapore': 'SGD',
    'Nepal': 'NPR',
    'Bangladesh': 'BDT',
  };

  static const currencySymbols = <String, String>{
    'INR': '₹',
    'AED': 'AED ',
    'SAR': 'SAR ',
    'GBP': '£',
    'USD': '\$',
    'CAD': 'C\$',
    'AUD': 'A\$',
    'SGD': 'S\$',
    'NPR': 'Rs ',
    'BDT': '৳',
  };

  static const dialCodes = <String, String>{
    'India': '+91',
    'United Arab Emirates': '+971',
    'Saudi Arabia': '+966',
    'United Kingdom': '+44',
    'United States': '+1',
    'Canada': '+1',
    'Australia': '+61',
    'Singapore': '+65',
    'Nepal': '+977',
    'Bangladesh': '+880',
  };
}
