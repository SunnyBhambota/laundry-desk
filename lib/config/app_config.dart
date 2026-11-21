/// One place for settings the owner may change.
class AppConfig {
  AppConfig._();

  static const appName = 'LaundryCase';
  static const company = 'BrotriX Technologies';
  static const version = '0.12.0';

  /// Firebase project laundry-desk-4308f (Android app com.brotrix.laundry).
  /// If these are emptied the app runs in DEMO MODE (data only on this phone).
  static const firebaseApiKey = 'AIzaSyBxkZ9Uoa-025gof-DtFOFF4jBWJbCX0ms';
  static const firebaseAppId = '1:356269298314:android:3a9979a0c3eca1578f5373';
  static const firebaseSenderId = '356269298314';
  static const firebaseProjectId = 'laundry-desk-4308f';
  static const firebaseStorageBucket = 'laundry-desk-4308f.firebasestorage.app';

  /// OAuth web client (from google-services.json, client_type 3) for Google sign-in.
  static const googleWebClientId = '356269298314-lou2tv40t4adjv8f8nb5ugpsp3bfgia7.apps.googleusercontent.com';

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

  /// App admin screen (More → tap the version 7 times).
  static const superAdminPin = '0000'; // old demo PIN – app admin is now an account (admins/{uid})
  /// Sales WhatsApp number (digits with country code). Empty = show a message.
  static const salesPhone = '';

  /// Free plan limits (after the trial, without a paid plan).
  static const freeMaxBranches = 1;
  static const freeMaxStaff = 2;
  static const freeOrdersPerMonth = 150;

  /// Modules. Free ones stay on after the trial; the rest need a plan.
  static const freeModules = ['orders', 'customers', 'bills', 'basicReports'];
  static const premiumModules = [
    'whatsapp',
    'staffTracking',
    'delivery',
    'barcode',
    'multiBranch',
    'advancedReports',
    'loyalty',
    'stock',
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
    'Alteration',
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
