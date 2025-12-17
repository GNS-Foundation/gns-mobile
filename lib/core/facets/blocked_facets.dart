/// Blocked Facets Registry - Globe Posts Phase 1
///
/// Defines facet IDs that cannot be used by regular users:
/// 1. SYSTEM - Reserved for protocol operations (admin, system, gns, etc.)
/// 2. BRANDS - Trademark protection (google, apple, nike, etc.)
///
/// Brand facets can be LICENSED by verified trademark owners,
/// allowing them to authorize employees to use their namespace.
///
/// Philosophy: HUMANS PREVAIL
/// - Blocked facets protect users from impersonation
/// - Brands AUTHORIZE, they don't OWN employee identities
/// - Licensed brands enable verified corporate communications
///
/// Location: lib/core/facets/blocked_facets.dart

import 'package:flutter/foundation.dart';

/// Category of blocked facet
enum BlockedCategory {
  /// Reserved for GNS protocol operations
  system,

  /// Technology companies
  brandTech,

  /// Financial institutions
  brandFinance,

  /// Consumer brands
  brandConsumer,

  /// Media and entertainment
  brandMedia,

  /// Cryptocurrency and Web3
  brandCrypto,

  /// Government and organizations
  government,

  /// Offensive or inappropriate
  offensive,

  /// Licensed by trademark owner (special status)
  licensed,
}

/// Information about a blocked facet
class BlockedFacetInfo {
  final String id;
  final BlockedCategory category;
  final String reason;
  final bool isLicensable;

  const BlockedFacetInfo({
    required this.id,
    required this.category,
    required this.reason,
    this.isLicensable = false,
  });

  /// Whether this is a brand that can potentially be licensed
  bool get isBrand => category != BlockedCategory.system && 
                       category != BlockedCategory.offensive &&
                       category != BlockedCategory.government;

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category.name,
    'reason': reason,
    'is_licensable': isLicensable,
  };
}

/// Registry of all blocked facet IDs
abstract class BlockedFacets {
  BlockedFacets._();

  // ============================================================
  // SYSTEM RESERVED (Cannot ever be used)
  // ============================================================

  static const Set<String> system = {
    // Core system
    'admin', 'administrator', 'system', 'sys',
    'gns', 'globe', 'globecrumbs', 'crumbs',
    'support', 'help', 'info', 'contact',
    'root', 'sudo', 'superuser',
    
    // Official accounts
    'official', 'verified', 'mod', 'moderator',
    'team', 'staff', 'employee', 'hr',
    
    // Security
    'security', 'auth', 'authentication', 'login', 'signup',
    'password', 'reset', 'verify', 'verification',
    
    // Technical
    'api', 'webhook', 'callback', 'oauth',
    'null', 'undefined', 'void', 'none', 'nil',
    'test', 'testing', 'demo', 'example', 'sample',
    
    // Bots and services
    'bot', 'robot', 'service', 'daemon', 'cron', 'worker',
    'echo', 'ping', 'status', 'health',
    
    // Scope keywords
    'internal', 'private', 'public', 'global', 'local',
    'master', 'main', 'primary', 'secondary',
    'backup', 'temp', 'tmp', 'cache',
    
    // News and alerts
    'news', 'alert', 'alerts', 'notification', 'notifications',
    'announcement', 'announcements', 'update', 'updates',
    
    // Misc reserved
    'anonymous', 'anon', 'unknown', 'guest',
    'everyone', 'all', 'any', 'default',
  };

  // ============================================================
  // TECHNOLOGY COMPANIES
  // ============================================================

  static const Set<String> brandTech = {
    // Big Tech
    'google', 'alphabet', 'apple', 'microsoft', 'amazon', 'aws',
    'meta', 'facebook', 'instagram', 'whatsapp', 'threads', 'messenger',
    'twitter', 'x', 'tiktok', 'bytedance',
    'snapchat', 'snap', 'linkedin', 'pinterest',
    
    // Dev platforms
    'github', 'gitlab', 'bitbucket', 'stackoverflow', 'reddit',
    'discord', 'slack', 'zoom', 'teams', 'skype',
    'telegram', 'signal', 'viber', 'line', 'wechat',
    
    // AI
    'openai', 'chatgpt', 'gpt', 'anthropic', 'claude',
    'deepmind', 'gemini', 'bard', 'copilot', 'midjourney',
    'stablediffusion', 'huggingface', 'replicate',
    
    // Hardware
    'nvidia', 'intel', 'amd', 'qualcomm', 'arm',
    'samsung', 'sony', 'lg', 'huawei', 'xiaomi',
    'oppo', 'vivo', 'oneplus', 'realme',
    'asus', 'acer', 'dell', 'hp', 'lenovo',
    
    // Enterprise
    'ibm', 'oracle', 'salesforce', 'adobe', 'autodesk',
    'vmware', 'cisco', 'juniper', 'netgear', 'ubiquiti',
    'sap', 'workday', 'servicenow', 'atlassian',
    
    // Cloud / Storage
    'dropbox', 'box', 'onedrive', 'icloud', 'gdrive',
    
    // Streaming
    'netflix', 'hulu', 'disney', 'disneyplus', 'hbo', 'hbomax',
    'paramount', 'peacock', 'prime', 'primevideo',
    'spotify', 'pandora', 'soundcloud', 'deezer', 'tidal',
    'youtube', 'vimeo', 'twitch', 'kick',
    
    // Transportation
    'uber', 'lyft', 'grab', 'gojek', 'didi',
    'airbnb', 'vrbo', 'booking', 'expedia', 'tripadvisor',
    
    // Food delivery
    'doordash', 'ubereats', 'grubhub', 'instacart', 'shipt',
    'postmates', 'deliveroo', 'justeat',
    
    // E-commerce
    'shopify', 'wix', 'squarespace', 'wordpress', 'webflow',
    'etsy', 'ebay', 'aliexpress', 'alibaba', 'wish', 'temu', 'shein',
    
    // Space
    'tesla', 'spacex', 'rivian', 'lucid', 'nio', 'byd',
    'neuralink', 'boring', 'starlink',
  };

  // ============================================================
  // FINANCIAL INSTITUTIONS
  // ============================================================

  static const Set<String> brandFinance = {
    // Card networks
    'visa', 'mastercard', 'amex', 'americanexpress',
    'discover', 'dinersclub', 'jcb', 'unionpay',
    
    // Payment processors
    'paypal', 'venmo', 'stripe', 'square', 'adyen',
    'worldpay', 'checkout', 'braintree', 'klarna', 'affirm',
    'cashapp', 'zelle', 'applepay', 'googlepay',
    
    // US Banks
    'jpmorgan', 'chase', 'bankofamerica', 'bofa',
    'wellsfargo', 'citibank', 'citi', 'usbank',
    'pnc', 'capitalone', 'synchrony', 'ally', 'marcus',
    
    // Investment
    'goldmansachs', 'morganstanley', 'merrilllynch',
    'fidelity', 'schwab', 'vanguard', 'blackrock',
    'edwardjones', 'ameriprise', 'raymondjames',
    'robinhood', 'etrade', 'tdameritrade', 'webull',
    
    // Insurance
    'prudential', 'metlife', 'aig', 'allstate',
    'statefarm', 'geico', 'progressive', 'liberty',
    'nationwide', 'usaa', 'travelers',
    
    // International banks
    'hsbc', 'barclays', 'ubs', 'creditsuisse',
    'deutschebank', 'bnpparibas', 'societegenerale',
    'santander', 'bbva', 'ing', 'abn', 'rabobank',
    'commerzbank', 'unicredit', 'intesa',
  };

  // ============================================================
  // CONSUMER BRANDS
  // ============================================================

  static const Set<String> brandConsumer = {
    // Sportswear
    'nike', 'adidas', 'puma', 'reebok', 'newbalance',
    'asics', 'underarmour', 'lululemon', 'fila', 'converse',
    
    // Outdoor
    'northface', 'patagonia', 'columbia', 'arcteryx',
    'canadagoose', 'moncler', 'timberland',
    
    // Luxury
    'burberry', 'gucci', 'prada', 'louisvuitton', 'lv',
    'chanel', 'hermes', 'dior', 'ysl', 'balenciaga',
    'givenchy', 'fendi', 'versace', 'armani', 'valentino',
    'rolex', 'cartier', 'tiffany', 'omega', 'patek',
    
    // Fast fashion
    'zara', 'hm', 'uniqlo', 'gap', 'oldnavy',
    'forever21', 'primark', 'asos',
    
    // Beverages
    'cocacola', 'coke', 'pepsi', 'drpepper', 'sprite',
    'fanta', 'mountaindew', 'gatorade', 'powerade',
    'redbull', 'monster', 'rockstar',
    'budweiser', 'heineken', 'corona', 'guinness',
    
    // Food / QSR
    'starbucks', 'dunkin', 'peets', 'timhortons',
    'mcdonalds', 'burgerking', 'wendys', 'tacobell',
    'chipotle', 'subway', 'dominos', 'pizzahut', 'papajohns',
    'kfc', 'chickfila', 'popeyes', 'fiveguys', 'shakeshack',
    'innout', 'whataburger', 'wawa', 'sheetz', '7eleven',
    
    // Retail
    'walmart', 'target', 'costco', 'samsclub', 'bjs',
    'kroger', 'albertsons', 'safeway', 'publix', 'wegmans',
    'traderjoes', 'wholefoods', 'aldi', 'lidl',
    'ikea', 'homedepot', 'lowes', 'menards', 'acehardware',
    'bestbuy', 'gamestop', 'wayfair', 'overstock',
    'chewy', 'petco', 'petsmart',
    
    // Auto
    'toyota', 'honda', 'ford', 'gm', 'chevrolet', 'chevy',
    'bmw', 'mercedes', 'audi', 'volkswagen', 'vw',
    'porsche', 'ferrari', 'lamborghini', 'maserati',
    'lexus', 'acura', 'infiniti', 'genesis',
    'hyundai', 'kia', 'mazda', 'subaru', 'nissan',
    'jeep', 'dodge', 'ram', 'chrysler',
    'volvo', 'jaguar', 'landrover', 'rollsroyce', 'bentley',
  };

  // ============================================================
  // MEDIA & ENTERTAINMENT
  // ============================================================

  static const Set<String> brandMedia = {
    // News - TV
    'cnn', 'foxnews', 'fox', 'msnbc', 'bbc', 'nbc', 'abc', 'cbs', 'pbs', 'npr',
    
    // News - Print
    'nytimes', 'newyorktimes', 'washingtonpost', 'wapo',
    'wsj', 'wallstreetjournal', 'usatoday', 'latimes',
    'chicagotribune', 'bostonglobe', 'nypost',
    
    // News - Wire
    'reuters', 'ap', 'associatedpress', 'afp', 'bloomberg',
    
    // Business
    'forbes', 'fortune', 'businessinsider', 'cnbc',
    'marketwatch', 'ft', 'financialtimes', 'economist',
    
    // Magazines
    'time', 'newsweek', 'atlantic', 'newyorker',
    'vox', 'vice', 'buzzfeed', 'huffpost', 'dailymail',
    'guardian', 'telegraph', 'mirror', 'sun', 'independent',
    
    // Politics
    'politico', 'axios', 'thehill', 'slate', 'salon',
    
    // Entertainment
    'rollingstone', 'billboard', 'variety', 'deadline',
    'hollywoodreporter', 'tmz', 'eonline', 'people', 'usweekly',
    
    // Lifestyle
    'cosmopolitan', 'vogue', 'elle', 'harpersbazaar',
    'gq', 'esquire', 'menshealth', 'womenshealth',
    
    // Sports
    'espn', 'bleacherreport', 'theathletic', 'si', 'sportsillustrated',
    'nfl', 'nba', 'mlb', 'nhl', 'mls', 'pga',
    'fifa', 'uefa', 'premierleague', 'laliga', 'seriea', 'bundesliga',
    'ufc', 'wwe', 'f1', 'nascar', 'atp', 'wta',
    'olympics', 'paralympics',
    
    // Studios
    'warner', 'warnerbrothers', 'universal', 'paramount',
    'mgm', 'lionsgate', 'dreamworks', 'pixar', 'marvel', 'dc',
    'lucasfilm', 'starwars',
  };

  // ============================================================
  // CRYPTOCURRENCY & WEB3
  // ============================================================

  static const Set<String> brandCrypto = {
    // Major coins
    'bitcoin', 'btc', 'ethereum', 'eth', 'solana', 'sol',
    'cardano', 'ada', 'polkadot', 'dot', 'avalanche', 'avax',
    'polygon', 'matic', 'chainlink', 'link',
    'litecoin', 'ltc', 'dogecoin', 'doge',
    'ripple', 'xrp', 'stellar', 'xlm',
    
    // DeFi
    'uniswap', 'uni', 'aave', 'compound', 'maker', 'mkr',
    'curve', 'sushi', 'pancakeswap',
    
    // Stablecoins
    'usdt', 'tether', 'usdc', 'circle', 'busd', 'paxos', 'dai',
    
    // Meme coins
    'shiba', 'shibainu', 'pepe', 'bonk', 'floki', 'safemoon',
    
    // Failed/controversial
    'luna', 'terra', 'ust', 'ftx', 'alameda',
    
    // Exchanges
    'binance', 'bnb', 'coinbase', 'kraken', 'gemini',
    'bitstamp', 'bitfinex', 'okx', 'kucoin', 'bybit',
    'bitget', 'gateio', 'mexc', 'huobi',
    
    // NFT
    'opensea', 'blur', 'looksrare', 'rarible',
    'foundation', 'superrare', 'niftygateway',
    
    // Wallets
    'metamask', 'phantom', 'trustwallet', 'ledger', 'trezor',
    
    // Identity competitors
    'worldcoin', 'world', 'orb', 'ens', 'unstoppable', 'handshake',
    'lens', 'farcaster', 'bluesky',
  };

  // ============================================================
  // GOVERNMENT & ORGANIZATIONS
  // ============================================================

  static const Set<String> government = {
    // US agencies
    'fbi', 'cia', 'nsa', 'dhs', 'doj', 'dod', 'pentagon',
    'whitehouse', 'congress', 'senate', 'house',
    'scotus', 'supremecourt',
    'irs', 'sec', 'ftc', 'fcc', 'fda', 'cdc', 'nih',
    'fema', 'epa', 'dot', 'hud', 'usda', 'doi', 'doe',
    'treasury', 'state', 'defense', 'justice', 'homeland',
    'commerce', 'labor', 'hhs', 'education', 'va', 'sba',
    
    // US agencies - other
    'nasa', 'noaa', 'usps', 'tsa', 'atf', 'dea', 'ice', 'cbp',
    
    // Military
    'army', 'navy', 'airforce', 'marines', 'coastguard',
    'spaceforce', 'nationalguard', 'military',
    
    // Law enforcement
    'police', 'sheriff', 'fire', 'ems', 'swat',
    
    // International agencies
    'interpol', 'europol', 'mi5', 'mi6', 'gchq',
    'mossad', 'fsb', 'kgb', 'bnd', 'dgse', 'asis', 'csis',
    
    // International orgs
    'un', 'unitednations', 'unesco', 'unicef', 'who', 'wto',
    'imf', 'worldbank', 'nato', 'eu', 'european',
    'asean', 'opec', 'oecd', 'g7', 'g20', 'brics',
    
    // NGOs
    'redcross', 'amnesty', 'greenpeace', 'wwf',
    'oxfam', 'savethechildren', 'doctorswithoutborders', 'msf',
    'habitat', 'unitedway', 'aclu', 'eff',
    
    // Political
    'democrats', 'republicans', 'gop', 'dnc', 'rnc',
    'libertarian', 'green', 'independent',
  };

  // ============================================================
  // OFFENSIVE / INAPPROPRIATE
  // ============================================================

  static const Set<String> offensive = {
    // We keep this minimal and non-explicit
    // Actual list would be more comprehensive
    'hate', 'nazi', 'isis', 'terrorist',
    'porn', 'xxx', 'nsfw', 'adult',
    'drugs', 'cocaine', 'heroin', 'meth',
    'kill', 'murder', 'death', 'suicide',
    'scam', 'fraud', 'fake', 'phishing',
  };

  // ============================================================
  // COMBINED SETS FOR QUICK LOOKUP
  // ============================================================

  /// All brand facets (excluding system and offensive)
  static final Set<String> allBrands = {
    ...brandTech,
    ...brandFinance,
    ...brandConsumer,
    ...brandMedia,
    ...brandCrypto,
  };

  /// All blocked facets
  static final Set<String> all = {
    ...system,
    ...brandTech,
    ...brandFinance,
    ...brandConsumer,
    ...brandMedia,
    ...brandCrypto,
    ...government,
    ...offensive,
  };

  // ============================================================
  // LOOKUP METHODS
  // ============================================================

  /// Check if a facet ID is blocked
  static bool isBlocked(String id) {
    return all.contains(id.toLowerCase().trim());
  }

  /// Check if a facet ID is a system reserved ID
  static bool isSystem(String id) {
    return system.contains(id.toLowerCase().trim());
  }

  /// Check if a facet ID is a protected brand
  static bool isBrand(String id) {
    return allBrands.contains(id.toLowerCase().trim());
  }

  /// Check if a facet ID is a government/org ID
  static bool isGovernment(String id) {
    return government.contains(id.toLowerCase().trim());
  }

  /// Get the category of a blocked facet
  static BlockedCategory? getCategory(String id) {
    final normalized = id.toLowerCase().trim();
    
    if (system.contains(normalized)) return BlockedCategory.system;
    if (brandTech.contains(normalized)) return BlockedCategory.brandTech;
    if (brandFinance.contains(normalized)) return BlockedCategory.brandFinance;
    if (brandConsumer.contains(normalized)) return BlockedCategory.brandConsumer;
    if (brandMedia.contains(normalized)) return BlockedCategory.brandMedia;
    if (brandCrypto.contains(normalized)) return BlockedCategory.brandCrypto;
    if (government.contains(normalized)) return BlockedCategory.government;
    if (offensive.contains(normalized)) return BlockedCategory.offensive;
    
    return null;
  }

  /// Get info about a blocked facet
  static BlockedFacetInfo? getInfo(String id) {
    final category = getCategory(id);
    if (category == null) return null;

    final normalized = id.toLowerCase().trim();
    
    return BlockedFacetInfo(
      id: normalized,
      category: category,
      reason: _getReasonForCategory(category),
      isLicensable: _isLicensable(category),
    );
  }

  static String _getReasonForCategory(BlockedCategory category) {
    switch (category) {
      case BlockedCategory.system:
        return 'Reserved for GNS protocol operations';
      case BlockedCategory.brandTech:
        return 'Trademark protection (technology company)';
      case BlockedCategory.brandFinance:
        return 'Trademark protection (financial institution)';
      case BlockedCategory.brandConsumer:
        return 'Trademark protection (consumer brand)';
      case BlockedCategory.brandMedia:
        return 'Trademark protection (media/entertainment)';
      case BlockedCategory.brandCrypto:
        return 'Trademark protection (cryptocurrency/Web3)';
      case BlockedCategory.government:
        return 'Reserved (government/organization)';
      case BlockedCategory.offensive:
        return 'Prohibited content';
      case BlockedCategory.licensed:
        return 'Licensed to trademark owner';
    }
  }

  static bool _isLicensable(BlockedCategory category) {
    switch (category) {
      case BlockedCategory.brandTech:
      case BlockedCategory.brandFinance:
      case BlockedCategory.brandConsumer:
      case BlockedCategory.brandMedia:
      case BlockedCategory.brandCrypto:
        return true;
      default:
        return false;
    }
  }
}

/// Extension for user-friendly category names
extension BlockedCategoryDisplay on BlockedCategory {
  String get displayName {
    switch (this) {
      case BlockedCategory.system:
        return 'System Reserved';
      case BlockedCategory.brandTech:
        return 'Technology';
      case BlockedCategory.brandFinance:
        return 'Finance';
      case BlockedCategory.brandConsumer:
        return 'Consumer Brands';
      case BlockedCategory.brandMedia:
        return 'Media & Entertainment';
      case BlockedCategory.brandCrypto:
        return 'Cryptocurrency';
      case BlockedCategory.government:
        return 'Government';
      case BlockedCategory.offensive:
        return 'Prohibited';
      case BlockedCategory.licensed:
        return 'Licensed';
    }
  }

  String get icon {
    switch (this) {
      case BlockedCategory.system:
        return '⚙️';
      case BlockedCategory.brandTech:
        return '💻';
      case BlockedCategory.brandFinance:
        return '🏦';
      case BlockedCategory.brandConsumer:
        return '🛍️';
      case BlockedCategory.brandMedia:
        return '📺';
      case BlockedCategory.brandCrypto:
        return '🪙';
      case BlockedCategory.government:
        return '🏛️';
      case BlockedCategory.offensive:
        return '🚫';
      case BlockedCategory.licensed:
        return '✅';
    }
  }
}
