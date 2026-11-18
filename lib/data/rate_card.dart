import 'ops_models.dart';

/// Default garments and prices (INR). Owner edits them in Rate card.
/// Prices for other currencies are scaled in [defaultRates].
class DefaultRates {
  DefaultRates._();

  static final garments = <Garment>[
    Garment(id: 'g_shirt', name: 'Shirt', category: 'Men'),
    Garment(id: 'g_tshirt', name: 'T-shirt', category: 'Men'),
    Garment(id: 'g_trouser', name: 'Trouser / Pant', category: 'Men'),
    Garment(id: 'g_jeans', name: 'Jeans', category: 'Men'),
    Garment(id: 'g_kurta', name: 'Kurta', category: 'Men'),
    Garment(id: 'g_suit2', name: 'Suit (2 pc)', category: 'Men'),
    Garment(id: 'g_suit3', name: 'Suit (3 pc)', category: 'Men'),
    Garment(id: 'g_blazer', name: 'Blazer / Coat', category: 'Men'),
    Garment(id: 'g_sherwani', name: 'Sherwani', category: 'Men'),
    Garment(id: 'g_saree', name: 'Saree', category: 'Women'),
    Garment(id: 'g_silksaree', name: 'Silk saree', category: 'Women'),
    Garment(id: 'g_salwar', name: 'Salwar suit', category: 'Women'),
    Garment(id: 'g_lehenga', name: 'Lehenga', category: 'Women'),
    Garment(id: 'g_dress', name: 'Dress / Gown', category: 'Women'),
    Garment(id: 'g_dupatta', name: 'Dupatta', category: 'Women'),
    Garment(id: 'g_kids', name: 'Kids wear', category: 'Kids'),
    Garment(id: 'g_jacket', name: 'Jacket', category: 'Other'),
    Garment(id: 'g_sweater', name: 'Sweater', category: 'Other'),
    Garment(id: 'g_bedsheet', name: 'Bedsheet', category: 'Household'),
    Garment(id: 'g_blanket', name: 'Blanket', category: 'Household'),
    Garment(id: 'g_quilt', name: 'Quilt / Razai', category: 'Household'),
    Garment(id: 'g_curtain', name: 'Curtain (panel)', category: 'Household'),
    Garment(id: 'g_towel', name: 'Towel', category: 'Household'),
    Garment(id: 'g_carpet', name: 'Carpet', unit: 'sqft', category: 'Household'),
    Garment(id: 'g_shoes', name: 'Shoes (pair)', category: 'Other'),
    Garment(id: 'g_kg', name: 'Mixed clothes', unit: 'kg', category: 'Other'),
  ];

  /// Base dry-clean price per garment.
  static const _dry = <String, double>{
    'g_shirt': 80, 'g_tshirt': 70, 'g_trouser': 90, 'g_jeans': 100, 'g_kurta': 90, 'g_suit2': 299,
    'g_suit3': 399, 'g_blazer': 220, 'g_sherwani': 499, 'g_saree': 180, 'g_silksaree': 299, 'g_salwar': 180,
    'g_lehenga': 699, 'g_dress': 249, 'g_dupatta': 70, 'g_kids': 60, 'g_jacket': 249, 'g_sweater': 150,
    'g_bedsheet': 120, 'g_blanket': 299, 'g_quilt': 399, 'g_curtain': 150, 'g_towel': 50, 'g_carpet': 25,
    'g_shoes': 299, 'g_kg': 99,
  };

  /// Which services make sense for which garment, and the price factor vs dry clean.
  static double? price(String garmentId, String service) {
    final d = _dry[garmentId];
    if (d == null) return null;
    final isKg = garmentId == 'g_kg';
    final house = ['g_bedsheet', 'g_blanket', 'g_quilt', 'g_curtain', 'g_towel'].contains(garmentId);
    switch (service) {
      case 'Wash & fold':
        if (isKg) return 79;
        if (garmentId == 'g_shoes' || garmentId == 'g_carpet') return null;
        return _round(d * .45);
      case 'Wash & iron':
        if (isKg) return 119;
        if (garmentId == 'g_shoes' || garmentId == 'g_carpet') return null;
        return _round(d * .6);
      case 'Dry clean':
        if (isKg || garmentId == 'g_shoes') return null;
        return d;
      case 'Steam iron':
        if (isKg || house || garmentId == 'g_shoes' || garmentId == 'g_carpet') return garmentId == 'g_bedsheet' ? 30 : null;
        return _round(d * .25).clamp(15, 120).toDouble();
      case 'Shoe cleaning':
        return garmentId == 'g_shoes' ? 299 : null;
      case 'Carpet & curtain':
        if (garmentId == 'g_carpet') return 25;
        if (garmentId == 'g_curtain') return 150;
        return null;
      case 'Blanket / bedding':
        return house ? d : null;
      case 'Stain removal':
        if (isKg || garmentId == 'g_carpet') return null;
        return _round(d * .5).clamp(40, 250).toDouble();
    }
    return null;
  }

  static double _round(double v) => (v / 5).round() * 5.0;

  /// key "garmentId|service" → price, for the services this shop offers.
  static Map<String, double> defaultRates(List<String> services, {double currencyFactor = 1}) {
    final m = <String, double>{};
    for (final g in garments) {
      for (final s in services) {
        final p = price(g.id, s);
        if (p != null) m['${g.id}|$s'] = (p * currencyFactor * 100).round() / 100;
      }
    }
    return m;
  }

  /// Rough price scale for non-INR shops (owner should edit).
  static const currencyFactor = <String, double>{
    'INR': 1, 'AED': .045, 'SAR': .046, 'GBP': .01, 'USD': .012, 'CAD': .017, 'AUD': .019, 'SGD': .016, 'NPR': 1.6,
    'BDT': 1.4,
  };
}
