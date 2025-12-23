// ============================================================
// GNS gSITE MODELS
// ============================================================
// Location: lib/core/gsite/gsite_models.dart
// Purpose: Dart classes for all gSite entity types
// ============================================================

import 'dart:convert';

// ============================================================
// BASE TYPES
// ============================================================

class MediaRef {
  final String url;
  final String? alt;
  final int? width;
  final int? height;
  final String? mimeType;
  final String? blurhash;

  MediaRef({
    required this.url,
    this.alt,
    this.width,
    this.height,
    this.mimeType,
    this.blurhash,
  });

  factory MediaRef.fromJson(Map<String, dynamic> json) => MediaRef(
    url: json['url'] as String,
    alt: json['alt'] as String?,
    width: json['width'] as int?,
    height: json['height'] as int?,
    mimeType: json['mimeType'] as String?,
    blurhash: json['blurhash'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'url': url,
    if (alt != null) 'alt': alt,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (mimeType != null) 'mimeType': mimeType,
    if (blurhash != null) 'blurhash': blurhash,
  };
}

class Price {
  final double amount;
  final String currency;
  final String? display;

  Price({
    required this.amount,
    required this.currency,
    this.display,
  });

  factory Price.fromJson(Map<String, dynamic> json) => Price(
    amount: (json['amount'] as num).toDouble(),
    currency: json['currency'] as String,
    display: json['display'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'amount': amount,
    'currency': currency,
    if (display != null) 'display': display,
  };

  String get formatted => display ?? '$currency ${amount.toStringAsFixed(2)}';
}

class Location {
  final String? h3;
  final String? address;
  final String? city;
  final String? state;
  final String? country;
  final String? postalCode;
  final double? lat;
  final double? lng;

  Location({
    this.h3,
    this.address,
    this.city,
    this.state,
    this.country,
    this.postalCode,
    this.lat,
    this.lng,
  });

  factory Location.fromJson(Map<String, dynamic> json) => Location(
    h3: json['h3'] as String?,
    address: json['address'] as String?,
    city: json['city'] as String?,
    state: json['state'] as String?,
    country: json['country'] as String?,
    postalCode: json['postalCode'] as String?,
    lat: json['coordinates']?['lat'] as double?,
    lng: json['coordinates']?['lng'] as double?,
  );

  Map<String, dynamic> toJson() => {
    if (h3 != null) 'h3': h3,
    if (address != null) 'address': address,
    if (city != null) 'city': city,
    if (state != null) 'state': state,
    if (country != null) 'country': country,
    if (postalCode != null) 'postalCode': postalCode,
    if (lat != null && lng != null) 'coordinates': {'lat': lat, 'lng': lng},
  };

  String get displayAddress {
    final parts = <String>[];
    if (address != null) parts.add(address!);
    if (city != null) parts.add(city!);
    if (state != null) parts.add(state!);
    if (country != null) parts.add(country!);
    return parts.join(', ');
  }
}

class DayHours {
  final String open;
  final String close;

  DayHours({required this.open, required this.close});

  factory DayHours.fromJson(Map<String, dynamic> json) => DayHours(
    open: json['open'] as String,
    close: json['close'] as String,
  );

  Map<String, dynamic> toJson() => {'open': open, 'close': close};

  String get formatted => '$open - $close';
}

class Hours {
  final DayHours? monday;
  final DayHours? tuesday;
  final DayHours? wednesday;
  final DayHours? thursday;
  final DayHours? friday;
  final DayHours? saturday;
  final DayHours? sunday;
  final String? timezone;

  Hours({
    this.monday,
    this.tuesday,
    this.wednesday,
    this.thursday,
    this.friday,
    this.saturday,
    this.sunday,
    this.timezone,
  });

  factory Hours.fromJson(Map<String, dynamic> json) => Hours(
    monday: json['monday'] != null ? DayHours.fromJson(json['monday']) : null,
    tuesday: json['tuesday'] != null ? DayHours.fromJson(json['tuesday']) : null,
    wednesday: json['wednesday'] != null ? DayHours.fromJson(json['wednesday']) : null,
    thursday: json['thursday'] != null ? DayHours.fromJson(json['thursday']) : null,
    friday: json['friday'] != null ? DayHours.fromJson(json['friday']) : null,
    saturday: json['saturday'] != null ? DayHours.fromJson(json['saturday']) : null,
    sunday: json['sunday'] != null ? DayHours.fromJson(json['sunday']) : null,
    timezone: json['timezone'] as String?,
  );

  Map<String, dynamic> toJson() => {
    if (monday != null) 'monday': monday!.toJson(),
    if (tuesday != null) 'tuesday': tuesday!.toJson(),
    if (wednesday != null) 'wednesday': wednesday!.toJson(),
    if (thursday != null) 'thursday': thursday!.toJson(),
    if (friday != null) 'friday': friday!.toJson(),
    if (saturday != null) 'saturday': saturday!.toJson(),
    if (sunday != null) 'sunday': sunday!.toJson(),
    if (timezone != null) 'timezone': timezone,
  };

  DayHours? getDay(int weekday) {
    switch (weekday) {
      case DateTime.monday: return monday;
      case DateTime.tuesday: return tuesday;
      case DateTime.wednesday: return wednesday;
      case DateTime.thursday: return thursday;
      case DateTime.friday: return friday;
      case DateTime.saturday: return saturday;
      case DateTime.sunday: return sunday;
      default: return null;
    }
  }

  bool get isOpenNow {
    final now = DateTime.now();
    final today = getDay(now.weekday);
    if (today == null) return false;
    
    final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return currentTime.compareTo(today.open) >= 0 && currentTime.compareTo(today.close) <= 0;
  }
}

class Link {
  final String type;
  final String? url;
  final String? handle;

  Link({required this.type, this.url, this.handle});

  factory Link.fromJson(Map<String, dynamic> json) => Link(
    type: json['type'] as String,
    url: json['url'] as String?,
    handle: json['handle'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    if (url != null) 'url': url,
    if (handle != null) 'handle': handle,
  };

  String get displayUrl {
    if (url != null) return url!;
    if (handle != null) {
      switch (type) {
        case 'twitter': return 'https://twitter.com/$handle';
        case 'instagram': return 'https://instagram.com/$handle';
        case 'github': return 'https://github.com/$handle';
        case 'linkedin': return 'https://linkedin.com/in/$handle';
        default: return handle!;
      }
    }
    return '';
  }
}

class Verification {
  final String type;
  final String provider;
  final String value;
  final DateTime verified;
  final DateTime? expires;

  Verification({
    required this.type,
    required this.provider,
    required this.value,
    required this.verified,
    this.expires,
  });

  factory Verification.fromJson(Map<String, dynamic> json) => Verification(
    type: json['type'] as String,
    provider: json['provider'] as String,
    value: json['value'] as String,
    verified: DateTime.parse(json['verified'] as String),
    expires: json['expires'] != null ? DateTime.parse(json['expires'] as String) : null,
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'provider': provider,
    'value': value,
    'verified': verified.toIso8601String(),
    if (expires != null) 'expires': expires!.toIso8601String(),
  };

  bool get isValid => expires == null || expires!.isAfter(DateTime.now());
}

class TrustInfo {
  final double score;
  final int breadcrumbs;
  final DateTime? since;
  final List<Verification> verifications;

  TrustInfo({
    required this.score,
    required this.breadcrumbs,
    this.since,
    this.verifications = const [],
  });

  factory TrustInfo.fromJson(Map<String, dynamic> json) => TrustInfo(
    score: (json['score'] as num?)?.toDouble() ?? 0,
    breadcrumbs: json['breadcrumbs'] as int? ?? 0,
    since: json['since'] != null ? DateTime.parse(json['since'] as String) : null,
    verifications: (json['verifications'] as List<dynamic>?)
        ?.map((v) => Verification.fromJson(v as Map<String, dynamic>))
        .toList() ?? [],
  );

  Map<String, dynamic> toJson() => {
    'score': score,
    'breadcrumbs': breadcrumbs,
    if (since != null) 'since': since!.toIso8601String().split('T')[0],
    'verifications': verifications.map((v) => v.toJson()).toList(),
  };

  String get scoreLabel {
    if (score >= 76) return 'Highly Trusted';
    if (score >= 51) return 'Trusted';
    if (score >= 26) return 'Building Trust';
    return 'New';
  }
}

class Actions {
  final bool message;
  final bool payment;
  final bool call;
  final bool share;
  final bool follow;
  final bool directions;

  Actions({
    this.message = true,
    this.payment = false,
    this.call = false,
    this.share = true,
    this.follow = false,
    this.directions = false,
  });

  factory Actions.fromJson(Map<String, dynamic> json) => Actions(
    message: json['message'] == true || json['message'] is Map,
    payment: json['payment'] == true || json['payment'] is Map,
    call: json['call'] == true,
    share: json['share'] != false,
    follow: json['follow'] == true,
    directions: json['directions'] == true,
  );

  Map<String, dynamic> toJson() => {
    'message': message,
    'payment': payment,
    'call': call,
    'share': share,
    'follow': follow,
    'directions': directions,
  };
}

// ============================================================
// BASE gSITE CLASS
// ============================================================

enum GSiteType {
  person,
  business,
  store,
  service,
  publication,
  community,
  organization,
  event,
  product,
  place;

  static GSiteType fromString(String value) {
    switch (value) {
      case 'Person': return GSiteType.person;
      case 'Business': return GSiteType.business;
      case 'Store': return GSiteType.store;
      case 'Service': return GSiteType.service;
      case 'Publication': return GSiteType.publication;
      case 'Community': return GSiteType.community;
      case 'Organization': return GSiteType.organization;
      case 'Event': return GSiteType.event;
      case 'Product': return GSiteType.product;
      case 'Place': return GSiteType.place;
      default: throw ArgumentError('Unknown GSite type: $value');
    }
  }

  String get value {
    switch (this) {
      case GSiteType.person: return 'Person';
      case GSiteType.business: return 'Business';
      case GSiteType.store: return 'Store';
      case GSiteType.service: return 'Service';
      case GSiteType.publication: return 'Publication';
      case GSiteType.community: return 'Community';
      case GSiteType.organization: return 'Organization';
      case GSiteType.event: return 'Event';
      case GSiteType.product: return 'Product';
      case GSiteType.place: return 'Place';
    }
  }
}

abstract class GSite {
  static const String context = 'https://schema.gns.network/v1';

  final GSiteType type;
  final String id;
  final String name;
  final String? tagline;
  final String? bio;
  final MediaRef? avatar;
  final MediaRef? cover;
  final TrustInfo? trust;
  final Location? location;
  final List<Link> links;
  final Actions actions;
  final String? theme;
  final Map<String, dynamic>? themeOverrides;
  final DateTime? created;
  final DateTime? updated;
  final int version;
  final String? language;
  final String signature;

  GSite({
    required this.type,
    required this.id,
    required this.name,
    this.tagline,
    this.bio,
    this.avatar,
    this.cover,
    this.trust,
    this.location,
    this.links = const [],
    Actions? actions,
    this.theme,
    this.themeOverrides,
    this.created,
    this.updated,
    this.version = 1,
    this.language,
    required this.signature,
  }) : actions = actions ?? Actions();

  Map<String, dynamic> toJson();

  static GSite fromJson(Map<String, dynamic> json) {
    final type = GSiteType.fromString(json['@type'] as String);
    
    switch (type) {
      case GSiteType.person:
        return PersonGSite.fromJson(json);
      case GSiteType.business:
        return BusinessGSite.fromJson(json);
      case GSiteType.store:
        return StoreGSite.fromJson(json);
      case GSiteType.service:
        return ServiceGSite.fromJson(json);
      case GSiteType.publication:
        return PublicationGSite.fromJson(json);
      case GSiteType.community:
        return CommunityGSite.fromJson(json);
      case GSiteType.organization:
        return OrganizationGSite.fromJson(json);
      case GSiteType.event:
        return EventGSite.fromJson(json);
      case GSiteType.product:
        return ProductGSite.fromJson(json);
      case GSiteType.place:
        return PlaceGSite.fromJson(json);
    }
  }

  Map<String, dynamic> baseToJson() => {
    '@context': context,
    '@type': type.value,
    '@id': id,
    'name': name,
    if (tagline != null) 'tagline': tagline,
    if (bio != null) 'bio': bio,
    if (avatar != null) 'avatar': avatar!.toJson(),
    if (cover != null) 'cover': cover!.toJson(),
    if (trust != null) 'trust': trust!.toJson(),
    if (location != null) 'location': location!.toJson(),
    if (links.isNotEmpty) 'links': links.map((l) => l.toJson()).toList(),
    'actions': actions.toJson(),
    if (theme != null) 'theme': theme,
    if (themeOverrides != null) 'themeOverrides': themeOverrides,
    if (created != null) 'created': created!.toIso8601String(),
    if (updated != null) 'updated': updated!.toIso8601String(),
    'version': version,
    if (language != null) 'language': language,
    'signature': signature,
  };

  String get handle => id.startsWith('@') ? id : '@$id';
  bool get isNamespace => id.endsWith('@');
}

// ============================================================
// PERSON gSITE
// ============================================================

class Facet {
  final String name;
  final String id;
  final bool public;

  Facet({required this.name, required this.id, this.public = true});

  factory Facet.fromJson(Map<String, dynamic> json) => Facet(
    name: json['name'] as String,
    id: json['id'] as String,
    public: json['public'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {'name': name, 'id': id, 'public': public};
}

class PersonGSite extends GSite {
  final List<Facet> facets;
  final List<String> skills;
  final List<String> interests;
  final String? statusText;
  final String? statusEmoji;
  final bool? available;

  PersonGSite({
    required super.id,
    required super.name,
    super.tagline,
    super.bio,
    super.avatar,
    super.cover,
    super.trust,
    super.location,
    super.links,
    super.actions,
    super.theme,
    super.themeOverrides,
    super.created,
    super.updated,
    super.version,
    super.language,
    required super.signature,
    this.facets = const [],
    this.skills = const [],
    this.interests = const [],
    this.statusText,
    this.statusEmoji,
    this.available,
  }) : super(type: GSiteType.person);

  factory PersonGSite.fromJson(Map<String, dynamic> json) => PersonGSite(
    id: json['@id'] as String,
    name: json['name'] as String,
    tagline: json['tagline'] as String?,
    bio: json['bio'] as String?,
    avatar: json['avatar'] != null ? MediaRef.fromJson(json['avatar']) : null,
    cover: json['cover'] != null ? MediaRef.fromJson(json['cover']) : null,
    trust: json['trust'] != null ? TrustInfo.fromJson(json['trust']) : null,
    location: json['location'] != null ? Location.fromJson(json['location']) : null,
    links: (json['links'] as List<dynamic>?)?.map((l) => Link.fromJson(l)).toList() ?? [],
    actions: json['actions'] != null ? Actions.fromJson(json['actions']) : null,
    theme: json['theme'] as String?,
    themeOverrides: json['themeOverrides'] as Map<String, dynamic>?,
    created: json['created'] != null ? DateTime.parse(json['created']) : null,
    updated: json['updated'] != null ? DateTime.parse(json['updated']) : null,
    version: json['version'] as int? ?? 1,
    language: json['language'] as String?,
    signature: json['signature'] as String,
    facets: (json['facets'] as List<dynamic>?)?.map((f) => Facet.fromJson(f)).toList() ?? [],
    skills: (json['skills'] as List<dynamic>?)?.cast<String>() ?? [],
    interests: (json['interests'] as List<dynamic>?)?.cast<String>() ?? [],
    statusText: json['status']?['text'] as String?,
    statusEmoji: json['status']?['emoji'] as String?,
    available: json['status']?['available'] as bool?,
  );

  @override
  Map<String, dynamic> toJson() => {
    ...baseToJson(),
    if (facets.isNotEmpty) 'facets': facets.map((f) => f.toJson()).toList(),
    if (skills.isNotEmpty) 'skills': skills,
    if (interests.isNotEmpty) 'interests': interests,
    if (statusText != null || statusEmoji != null || available != null)
      'status': {
        if (statusText != null) 'text': statusText,
        if (statusEmoji != null) 'emoji': statusEmoji,
        if (available != null) 'available': available,
      },
  };
}

// ============================================================
// BUSINESS gSITE
// ============================================================

class MenuItem {
  final String? id;
  final String name;
  final String? description;
  final Price price;
  final MediaRef? image;
  final String? category;
  final bool available;

  MenuItem({
    this.id,
    required this.name,
    this.description,
    required this.price,
    this.image,
    this.category,
    this.available = true,
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
    id: json['id'] as String?,
    name: json['name'] as String,
    description: json['description'] as String?,
    price: Price.fromJson(json['price']),
    image: json['image'] != null ? MediaRef.fromJson(json['image']) : null,
    category: json['category'] as String?,
    available: json['available'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'name': name,
    if (description != null) 'description': description,
    'price': price.toJson(),
    if (image != null) 'image': image!.toJson(),
    if (category != null) 'category': category,
    'available': available,
  };
}

class BusinessGSite extends GSite {
  final String category;
  final List<String> subcategories;
  final Hours? hours;
  final String? phone;
  final String? email;
  final List<MenuItem> menu;
  final List<String> features;
  final int? priceLevel;
  final double? rating;
  final int? reviewCount;

  BusinessGSite({
    required super.id,
    required super.name,
    super.tagline,
    super.bio,
    super.avatar,
    super.cover,
    super.trust,
    super.location,
    super.links,
    super.actions,
    super.theme,
    super.themeOverrides,
    super.created,
    super.updated,
    super.version,
    super.language,
    required super.signature,
    required this.category,
    this.subcategories = const [],
    this.hours,
    this.phone,
    this.email,
    this.menu = const [],
    this.features = const [],
    this.priceLevel,
    this.rating,
    this.reviewCount,
  }) : super(type: GSiteType.business);

  factory BusinessGSite.fromJson(Map<String, dynamic> json) => BusinessGSite(
    id: json['@id'] as String,
    name: json['name'] as String,
    tagline: json['tagline'] as String?,
    bio: json['bio'] as String?,
    avatar: json['avatar'] != null ? MediaRef.fromJson(json['avatar']) : null,
    cover: json['cover'] != null ? MediaRef.fromJson(json['cover']) : null,
    trust: json['trust'] != null ? TrustInfo.fromJson(json['trust']) : null,
    location: json['location'] != null ? Location.fromJson(json['location']) : null,
    links: (json['links'] as List<dynamic>?)?.map((l) => Link.fromJson(l)).toList() ?? [],
    actions: json['actions'] != null ? Actions.fromJson(json['actions']) : null,
    theme: json['theme'] as String?,
    themeOverrides: json['themeOverrides'] as Map<String, dynamic>?,
    created: json['created'] != null ? DateTime.parse(json['created']) : null,
    updated: json['updated'] != null ? DateTime.parse(json['updated']) : null,
    version: json['version'] as int? ?? 1,
    language: json['language'] as String?,
    signature: json['signature'] as String,
    category: json['category'] as String,
    subcategories: (json['subcategories'] as List<dynamic>?)?.cast<String>() ?? [],
    hours: json['hours'] != null ? Hours.fromJson(json['hours']) : null,
    phone: json['phone'] as String?,
    email: json['email'] as String?,
    menu: (json['menu'] as List<dynamic>?)?.map((m) => MenuItem.fromJson(m)).toList() ?? [],
    features: (json['features'] as List<dynamic>?)?.cast<String>() ?? [],
    priceLevel: json['priceLevel'] as int?,
    rating: (json['verified']?['rating'] as num?)?.toDouble(),
    reviewCount: json['verified']?['reviews'] as int?,
  );

  @override
  Map<String, dynamic> toJson() => {
    ...baseToJson(),
    'category': category,
    if (subcategories.isNotEmpty) 'subcategories': subcategories,
    if (hours != null) 'hours': hours!.toJson(),
    if (phone != null) 'phone': phone,
    if (email != null) 'email': email,
    if (menu.isNotEmpty) 'menu': menu.map((m) => m.toJson()).toList(),
    if (features.isNotEmpty) 'features': features,
    if (priceLevel != null) 'priceLevel': priceLevel,
    if (rating != null || reviewCount != null) 'verified': {
      if (rating != null) 'rating': rating,
      if (reviewCount != null) 'reviews': reviewCount,
    },
  };

  String get priceLevelDisplay => '\$' * (priceLevel ?? 1);
}

// ============================================================
// PLACEHOLDER CLASSES FOR OTHER TYPES
// (Simplified versions - expand as needed)
// ============================================================

class StoreGSite extends GSite {
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> categories;

  StoreGSite({
    required super.id,
    required super.name,
    super.tagline,
    super.bio,
    super.avatar,
    super.cover,
    super.trust,
    super.location,
    super.links,
    super.actions,
    super.theme,
    super.themeOverrides,
    super.created,
    super.updated,
    super.version,
    super.language,
    required super.signature,
    this.products = const [],
    this.categories = const [],
  }) : super(type: GSiteType.store);

  factory StoreGSite.fromJson(Map<String, dynamic> json) => StoreGSite(
    id: json['@id'] as String,
    name: json['name'] as String,
    tagline: json['tagline'] as String?,
    bio: json['bio'] as String?,
    avatar: json['avatar'] != null ? MediaRef.fromJson(json['avatar']) : null,
    cover: json['cover'] != null ? MediaRef.fromJson(json['cover']) : null,
    trust: json['trust'] != null ? TrustInfo.fromJson(json['trust']) : null,
    location: json['location'] != null ? Location.fromJson(json['location']) : null,
    links: (json['links'] as List<dynamic>?)?.map((l) => Link.fromJson(l)).toList() ?? [],
    actions: json['actions'] != null ? Actions.fromJson(json['actions']) : null,
    signature: json['signature'] as String,
    products: (json['products'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [],
    categories: (json['categories'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [],
  );

  @override
  Map<String, dynamic> toJson() => {
    ...baseToJson(),
    'products': products,
    'categories': categories,
  };
}

class ServiceGSite extends GSite {
  final String profession;
  final List<Map<String, dynamic>> services;

  ServiceGSite({
    required super.id,
    required super.name,
    required this.profession,
    super.tagline,
    super.bio,
    super.avatar,
    super.cover,
    super.trust,
    super.location,
    super.links,
    super.actions,
    super.theme,
    required super.signature,
    this.services = const [],
  }) : super(type: GSiteType.service);

  factory ServiceGSite.fromJson(Map<String, dynamic> json) => ServiceGSite(
    id: json['@id'] as String,
    name: json['name'] as String,
    profession: json['profession'] as String,
    tagline: json['tagline'] as String?,
    bio: json['bio'] as String?,
    avatar: json['avatar'] != null ? MediaRef.fromJson(json['avatar']) : null,
    cover: json['cover'] != null ? MediaRef.fromJson(json['cover']) : null,
    trust: json['trust'] != null ? TrustInfo.fromJson(json['trust']) : null,
    location: json['location'] != null ? Location.fromJson(json['location']) : null,
    signature: json['signature'] as String,
    services: (json['services'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [],
  );

  @override
  Map<String, dynamic> toJson() => {...baseToJson(), 'profession': profession, 'services': services};
}

class PublicationGSite extends GSite {
  final String publicationType;
  final List<Map<String, dynamic>> articles;
  final int? subscribers;

  PublicationGSite({
    required super.id,
    required super.name,
    required this.publicationType,
    super.tagline,
    super.bio,
    super.avatar,
    super.cover,
    super.trust,
    super.links,
    required super.signature,
    this.articles = const [],
    this.subscribers,
  }) : super(type: GSiteType.publication);

  factory PublicationGSite.fromJson(Map<String, dynamic> json) => PublicationGSite(
    id: json['@id'] as String,
    name: json['name'] as String,
    publicationType: json['publicationType'] as String,
    tagline: json['tagline'] as String?,
    bio: json['bio'] as String?,
    avatar: json['avatar'] != null ? MediaRef.fromJson(json['avatar']) : null,
    cover: json['cover'] != null ? MediaRef.fromJson(json['cover']) : null,
    trust: json['trust'] != null ? TrustInfo.fromJson(json['trust']) : null,
    signature: json['signature'] as String,
    articles: (json['articles'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [],
    subscribers: json['subscribers'] as int?,
  );

  @override
  Map<String, dynamic> toJson() => {...baseToJson(), 'publicationType': publicationType, 'articles': articles};
}

class CommunityGSite extends GSite {
  final String communityType;
  final int? memberCount;

  CommunityGSite({
    required super.id,
    required super.name,
    required this.communityType,
    super.tagline,
    super.bio,
    super.avatar,
    super.cover,
    super.trust,
    required super.signature,
    this.memberCount,
  }) : super(type: GSiteType.community);

  factory CommunityGSite.fromJson(Map<String, dynamic> json) => CommunityGSite(
    id: json['@id'] as String,
    name: json['name'] as String,
    communityType: json['communityType'] as String,
    tagline: json['tagline'] as String?,
    signature: json['signature'] as String,
    memberCount: json['memberCount'] as int?,
  );

  @override
  Map<String, dynamic> toJson() => {...baseToJson(), 'communityType': communityType};
}

class OrganizationGSite extends GSite {
  final String orgType;
  final String? industry;

  OrganizationGSite({
    required super.id,
    required super.name,
    required this.orgType,
    super.tagline,
    super.bio,
    super.avatar,
    super.cover,
    super.trust,
    super.location,
    required super.signature,
    this.industry,
  }) : super(type: GSiteType.organization);

  factory OrganizationGSite.fromJson(Map<String, dynamic> json) => OrganizationGSite(
    id: json['@id'] as String,
    name: json['name'] as String,
    orgType: json['orgType'] as String,
    tagline: json['tagline'] as String?,
    bio: json['bio'] as String?,
    avatar: json['avatar'] != null ? MediaRef.fromJson(json['avatar']) : null,
    signature: json['signature'] as String,
    industry: json['industry'] as String?,
  );

  @override
  Map<String, dynamic> toJson() => {...baseToJson(), 'orgType': orgType, if (industry != null) 'industry': industry};
}

class EventGSite extends GSite {
  final String eventType;
  final DateTime startDate;
  final DateTime? endDate;
  final String timezone;
  final String organizer;

  EventGSite({
    required super.id,
    required super.name,
    required this.eventType,
    required this.startDate,
    this.endDate,
    required this.timezone,
    required this.organizer,
    super.tagline,
    super.bio,
    super.avatar,
    super.cover,
    super.trust,
    super.location,
    required super.signature,
  }) : super(type: GSiteType.event);

  factory EventGSite.fromJson(Map<String, dynamic> json) => EventGSite(
    id: json['@id'] as String,
    name: json['name'] as String,
    eventType: json['eventType'] as String,
    startDate: DateTime.parse(json['startDate'] as String),
    endDate: json['endDate'] != null ? DateTime.parse(json['endDate'] as String) : null,
    timezone: json['timezone'] as String,
    organizer: json['organizer'] as String,
    tagline: json['tagline'] as String?,
    signature: json['signature'] as String,
  );

  @override
  Map<String, dynamic> toJson() => {
    ...baseToJson(),
    'eventType': eventType,
    'startDate': startDate.toIso8601String(),
    if (endDate != null) 'endDate': endDate!.toIso8601String(),
    'timezone': timezone,
    'organizer': organizer,
  };
}

class ProductGSite extends GSite {
  final String productName;
  final String description;
  final List<MediaRef> images;
  final String category;
  final Price? price;

  ProductGSite({
    required super.id,
    required super.name,
    required this.productName,
    required this.description,
    required this.images,
    required this.category,
    this.price,
    super.tagline,
    super.avatar,
    super.trust,
    required super.signature,
  }) : super(type: GSiteType.product);

  factory ProductGSite.fromJson(Map<String, dynamic> json) => ProductGSite(
    id: json['@id'] as String,
    name: json['name'] as String,
    productName: json['productName'] as String,
    description: json['description'] as String,
    images: (json['images'] as List<dynamic>).map((i) => MediaRef.fromJson(i)).toList(),
    category: json['category'] as String,
    price: json['price'] != null ? Price.fromJson(json['price']) : null,
    signature: json['signature'] as String,
  );

  @override
  Map<String, dynamic> toJson() => {
    ...baseToJson(),
    'productName': productName,
    'description': description,
    'images': images.map((i) => i.toJson()).toList(),
    'category': category,
    if (price != null) 'price': price!.toJson(),
  };
}

class PlaceGSite extends GSite {
  final String placeType;

  PlaceGSite({
    required super.id,
    required super.name,
    required this.placeType,
    super.tagline,
    super.bio,
    super.avatar,
    super.cover,
    super.trust,
    super.location,
    required super.signature,
  }) : super(type: GSiteType.place);

  factory PlaceGSite.fromJson(Map<String, dynamic> json) => PlaceGSite(
    id: json['@id'] as String,
    name: json['name'] as String,
    placeType: json['placeType'] as String,
    tagline: json['tagline'] as String?,
    location: json['location'] != null ? Location.fromJson(json['location']) : null,
    signature: json['signature'] as String,
  );

  @override
  Map<String, dynamic> toJson() => {...baseToJson(), 'placeType': placeType};
}
