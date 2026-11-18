/// The signed-in owner.
class Owner {
  Owner({required this.uid, required this.name, required this.mobile, this.email = ''});

  final String uid;
  final String name;
  final String mobile; // digits only, with country code digits, e.g. 919876543210
  final String email;

  Map<String, dynamic> toJson() => {'uid': uid, 'name': name, 'mobile': mobile, 'email': email};

  factory Owner.fromJson(Map<String, dynamic> j) => Owner(
        uid: j['uid'] as String? ?? '',
        name: j['name'] as String? ?? '',
        mobile: j['mobile'] as String? ?? '',
        email: j['email'] as String? ?? '',
      );
}

/// The shop's one-time setup (Register step 2).
class ShopProfile {
  ShopProfile({
    required this.shopName,
    required this.services,
    required this.branches,
    required this.team,
    required this.country,
    required this.currency,
    this.address = '',
    this.pickupDelivery = true,
    this.gst = false,
    this.referral = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String shopName;
  final List<String> services;
  final String branches; // '1', '2–5', '6+'
  final String team; // '1–3', '4–10', '11–25', '25+'
  final String country;
  final String currency;
  final String address;
  final bool pickupDelivery;
  final bool gst;
  final String referral;
  final DateTime createdAt;

  int trialDaysLeft(int trialDays, [DateTime? now]) {
    final end = createdAt.add(Duration(days: trialDays));
    final left = end.difference(now ?? DateTime.now()).inHours / 24;
    return left <= 0 ? 0 : left.ceil();
  }

  Map<String, dynamic> toJson() => {
        'shopName': shopName,
        'services': services,
        'branches': branches,
        'team': team,
        'country': country,
        'currency': currency,
        'address': address,
        'pickupDelivery': pickupDelivery,
        'gst': gst,
        'referral': referral,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ShopProfile.fromJson(Map<String, dynamic> j) => ShopProfile(
        shopName: j['shopName'] as String? ?? '',
        services: (j['services'] as List?)?.map((e) => '$e').toList() ?? const [],
        branches: j['branches'] as String? ?? '1',
        team: j['team'] as String? ?? '1–3',
        country: j['country'] as String? ?? 'India',
        currency: j['currency'] as String? ?? 'INR',
        address: j['address'] as String? ?? '',
        pickupDelivery: j['pickupDelivery'] as bool? ?? true,
        gst: j['gst'] as bool? ?? false,
        referral: j['referral'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
      );
}
