// ============================================================
// GNS gSITE VIEWER
// ============================================================
// Location: lib/screens/gsite/gsite_viewer.dart
// Purpose: Render gSites visually (PANTHERA browser preview)
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/gsite/gsite_models.dart';
import '../../core/gsite/gsite_service.dart';

// ============================================================
// gSITE VIEWER SCREEN
// ============================================================

class GSiteViewerScreen extends StatefulWidget {
  final String identifier;
  final GSite? preloadedGSite;

  const GSiteViewerScreen({
    super.key,
    required this.identifier,
    this.preloadedGSite,
  });

  @override
  State<GSiteViewerScreen> createState() => _GSiteViewerScreenState();
}

class _GSiteViewerScreenState extends State<GSiteViewerScreen> {
  GSite? _gsite;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.preloadedGSite != null) {
      _gsite = widget.preloadedGSite;
      _loading = false;
    } else {
      _loadGSite();
    }
  }

  Future<void> _loadGSite() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await gsiteService.getGSite(widget.identifier);

    setState(() {
      _loading = false;
      if (result.success && result.data != null) {
        _gsite = result.data;
      } else {
        _error = result.error ?? 'Failed to load gSite';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorView()
              : _gsite != null
                  ? _buildGSiteView()
                  : _buildNotFoundView(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Error loading gSite',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadGSite,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotFoundView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'gSite not found',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(widget.identifier),
        ],
      ),
    );
  }

  Widget _buildGSiteView() {
    // Route to appropriate viewer based on type
    switch (_gsite!.type) {
      case GSiteType.person:
        return PersonGSiteView(gsite: _gsite as PersonGSite);
      case GSiteType.business:
        return BusinessGSiteView(gsite: _gsite as BusinessGSite);
      case GSiteType.store:
        return StoreGSiteView(gsite: _gsite as StoreGSite);
      default:
        return GenericGSiteView(gsite: _gsite!);
    }
  }
}

// ============================================================
// TRUST BADGE WIDGET
// ============================================================

class TrustBadge extends StatelessWidget {
  final TrustInfo trust;
  final bool compact;

  const TrustBadge({
    super.key,
    required this.trust,
    this.compact = false,
  });

  Color get _color {
    if (trust.score >= 76) return Colors.blue;
    if (trust.score >= 51) return Colors.green;
    if (trust.score >= 26) return Colors.amber;
    return Colors.grey;
  }

  IconData get _icon {
    if (trust.score >= 76) return Icons.verified;
    if (trust.score >= 51) return Icons.check_circle;
    if (trust.score >= 26) return Icons.shield;
    return Icons.shield_outlined;
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, size: 14, color: _color),
            const SizedBox(width: 4),
            Text(
              '${trust.score.toInt()}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: _color,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon, color: _color),
              const SizedBox(width: 8),
              Text(
                'Trust Score',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: _color,
                ),
              ),
              const Spacer(),
              Text(
                '${trust.score.toInt()}/100',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: trust.score / 100,
              backgroundColor: _color.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation(_color),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                '${trust.breadcrumbs} breadcrumbs',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              if (trust.since != null) ...[
                const SizedBox(width: 12),
                Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  'Since ${_formatDate(trust.since!)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ],
          ),
          if (trust.verifications.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: trust.verifications.map((v) => Chip(
                avatar: Icon(_getVerificationIcon(v.type), size: 16),
                label: Text(v.value, style: const TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.year}';
  }

  IconData _getVerificationIcon(String type) {
    switch (type) {
      case 'domain': return Icons.language;
      case 'phone': return Icons.phone;
      case 'email': return Icons.email;
      case 'government': return Icons.account_balance;
      case 'business': return Icons.business;
      default: return Icons.verified;
    }
  }
}

// ============================================================
// ACTION BAR WIDGET
// ============================================================

class GSiteActionBar extends StatelessWidget {
  final GSite gsite;
  final VoidCallback? onMessage;
  final VoidCallback? onPay;
  final VoidCallback? onShare;
  final VoidCallback? onFollow;

  const GSiteActionBar({
    super.key,
    required this.gsite,
    this.onMessage,
    this.onPay,
    this.onShare,
    this.onFollow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (gsite.actions.message)
            _ActionButton(
              icon: Icons.message,
              label: 'Message',
              onTap: onMessage,
              primary: true,
            ),
          if (gsite.actions.payment)
            _ActionButton(
              icon: Icons.payment,
              label: 'Pay',
              onTap: onPay,
            ),
          if (gsite.actions.follow)
            _ActionButton(
              icon: Icons.person_add,
              label: 'Follow',
              onTap: onFollow,
            ),
          if (gsite.actions.share)
            _ActionButton(
              icon: Icons.share,
              label: 'Share',
              onTap: onShare,
            ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = primary ? Theme.of(context).primaryColor : Colors.grey[700];
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// PERSON gSITE VIEW
// ============================================================

class PersonGSiteView extends StatelessWidget {
  final PersonGSite gsite;

  const PersonGSiteView({super.key, required this.gsite});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // Cover & Avatar Header
        SliverAppBar(
          expandedHeight: 200,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [
                // Cover image
                if (gsite.cover != null)
                  Image.network(
                    gsite.cover!.url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Theme.of(context).primaryColor.withOpacity(0.3),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).primaryColor,
                          Theme.of(context).primaryColor.withOpacity(0.7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                // Gradient overlay
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.5),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () {},
            ),
          ],
        ),

        // Profile Content
        SliverToBoxAdapter(
          child: Transform.translate(
            offset: const Offset(0, -50),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar & Name Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Avatar
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.white,
                        child: CircleAvatar(
                          radius: 46,
                          backgroundImage: gsite.avatar != null
                              ? NetworkImage(gsite.avatar!.url)
                              : null,
                          child: gsite.avatar == null
                              ? Text(
                                  gsite.name[0].toUpperCase(),
                                  style: const TextStyle(fontSize: 32),
                                )
                              : null,
                        ),
                      ),
                      const Spacer(),
                      // Trust Badge
                      if (gsite.trust != null)
                        TrustBadge(trust: gsite.trust!, compact: true),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Name & Handle
                  Text(
                    gsite.name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    gsite.handle,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),

                  // Tagline
                  if (gsite.tagline != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      gsite.tagline!,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],

                  // Status
                  if (gsite.statusText != null || gsite.statusEmoji != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (gsite.statusEmoji != null)
                            Text(gsite.statusEmoji!, style: const TextStyle(fontSize: 18)),
                          if (gsite.statusText != null) ...[
                            const SizedBox(width: 8),
                            Text(gsite.statusText!),
                          ],
                          if (gsite.available != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: gsite.available! ? Colors.green : Colors.grey,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Action Bar
                  GSiteActionBar(gsite: gsite),

                  const Divider(),

                  // Bio
                  if (gsite.bio != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      'About',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(gsite.bio!),
                  ],

                  // Trust Details
                  if (gsite.trust != null) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Trust',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TrustBadge(trust: gsite.trust!),
                  ],

                  // Facets
                  if (gsite.facets.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Facets',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: gsite.facets.map((f) => Chip(
                        label: Text(f.name),
                        avatar: Icon(
                          f.public ? Icons.public : Icons.lock,
                          size: 16,
                        ),
                      )).toList(),
                    ),
                  ],

                  // Skills
                  if (gsite.skills.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Skills',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: gsite.skills.map((s) => Chip(label: Text(s))).toList(),
                    ),
                  ],

                  // Links
                  if (gsite.links.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Links',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...gsite.links.map((link) => ListTile(
                      leading: Icon(_getLinkIcon(link.type)),
                      title: Text(link.type),
                      subtitle: Text(link.handle ?? link.url ?? ''),
                      contentPadding: EdgeInsets.zero,
                      onTap: () {
                        // Open link
                      },
                    )),
                  ],

                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  IconData _getLinkIcon(String type) {
    switch (type) {
      case 'website': return Icons.language;
      case 'github': return Icons.code;
      case 'twitter': return Icons.alternate_email;
      case 'linkedin': return Icons.business;
      case 'instagram': return Icons.camera_alt;
      case 'email': return Icons.email;
      case 'phone': return Icons.phone;
      default: return Icons.link;
    }
  }
}

// ============================================================
// BUSINESS gSITE VIEW
// ============================================================

class BusinessGSiteView extends StatelessWidget {
  final BusinessGSite gsite;

  const BusinessGSiteView({super.key, required this.gsite});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // Cover Header
        SliverAppBar(
          expandedHeight: 200,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            title: Text(
              gsite.name,
              style: const TextStyle(
                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
            background: Stack(
              fit: StackFit.expand,
              children: [
                if (gsite.cover != null)
                  Image.network(gsite.cover!.url, fit: BoxFit.cover)
                else
                  Container(color: Theme.of(context).primaryColor.withOpacity(0.3)),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Content
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category & Price Level
                Row(
                  children: [
                    Chip(
                      label: Text(gsite.category),
                      avatar: const Icon(Icons.category, size: 16),
                    ),
                    const SizedBox(width: 8),
                    if (gsite.priceLevel != null)
                      Text(
                        gsite.priceLevelDisplay,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    const Spacer(),
                    if (gsite.trust != null)
                      TrustBadge(trust: gsite.trust!, compact: true),
                  ],
                ),

                // Rating
                if (gsite.rating != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ...List.generate(5, (i) => Icon(
                        i < gsite.rating!.floor() ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 20,
                      )),
                      const SizedBox(width: 8),
                      Text(
                        gsite.rating!.toStringAsFixed(1),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (gsite.reviewCount != null)
                        Text(' (${gsite.reviewCount} reviews)'),
                    ],
                  ),
                ],

                // Tagline
                if (gsite.tagline != null) ...[
                  const SizedBox(height: 12),
                  Text(gsite.tagline!, style: const TextStyle(fontSize: 16)),
                ],

                const SizedBox(height: 16),

                // Action Bar
                GSiteActionBar(gsite: gsite),

                const Divider(),

                // Hours
                if (gsite.hours != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        'Hours',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: gsite.hours!.isOpenNow ? Colors.green : Colors.red,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          gsite.hours!.isOpenNow ? 'Open Now' : 'Closed',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildHoursTable(gsite.hours!),
                ],

                // Location
                if (gsite.location != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Location',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(Icons.location_on),
                    title: Text(gsite.location!.displayAddress),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],

                // Menu
                if (gsite.menu.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Menu',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...gsite.menu.map((item) => _buildMenuItem(item)),
                ],

                // Features
                if (gsite.features.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Features',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: gsite.features.map((f) => Chip(
                      label: Text(f),
                      avatar: const Icon(Icons.check, size: 16),
                    )).toList(),
                  ),
                ],

                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHoursTable(Hours hours) {
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final dayHours = [hours.monday, hours.tuesday, hours.wednesday, hours.thursday, hours.friday, hours.saturday, hours.sunday];

    return Column(
      children: List.generate(7, (i) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 100,
              child: Text(days[i], style: TextStyle(color: Colors.grey[600])),
            ),
            Text(dayHours[i]?.formatted ?? 'Closed'),
          ],
        ),
      )),
    );
  }

  Widget _buildMenuItem(MenuItem item) {
    return ListTile(
      leading: item.image != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(item.image!.url, width: 50, height: 50, fit: BoxFit.cover),
            )
          : null,
      title: Text(item.name),
      subtitle: item.description != null ? Text(item.description!, maxLines: 2) : null,
      trailing: Text(
        item.price.formatted,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      contentPadding: EdgeInsets.zero,
    );
  }
}

// ============================================================
// STORE gSITE VIEW (Simplified)
// ============================================================

class StoreGSiteView extends StatelessWidget {
  final StoreGSite gsite;

  const StoreGSiteView({super.key, required this.gsite});

  @override
  Widget build(BuildContext context) {
    return GenericGSiteView(gsite: gsite);
  }
}

// ============================================================
// GENERIC gSITE VIEW (Fallback)
// ============================================================

class GenericGSiteView extends StatelessWidget {
  final GSite gsite;

  const GenericGSiteView({super.key, required this.gsite});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(gsite.name),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Avatar
          Center(
            child: CircleAvatar(
              radius: 50,
              backgroundImage: gsite.avatar != null ? NetworkImage(gsite.avatar!.url) : null,
              child: gsite.avatar == null
                  ? Text(gsite.name[0].toUpperCase(), style: const TextStyle(fontSize: 32))
                  : null,
            ),
          ),
          const SizedBox(height: 16),

          // Name & Type
          Center(
            child: Column(
              children: [
                Text(
                  gsite.name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(gsite.handle, style: TextStyle(color: Colors.grey[600])),
                const SizedBox(height: 8),
                Chip(label: Text(gsite.type.value)),
              ],
            ),
          ),

          // Tagline
          if (gsite.tagline != null) ...[
            const SizedBox(height: 16),
            Text(gsite.tagline!, textAlign: TextAlign.center),
          ],

          // Trust
          if (gsite.trust != null) ...[
            const SizedBox(height: 24),
            TrustBadge(trust: gsite.trust!),
          ],

          // Actions
          const SizedBox(height: 16),
          GSiteActionBar(gsite: gsite),

          // Bio
          if (gsite.bio != null) ...[
            const SizedBox(height: 24),
            Text('About', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(gsite.bio!),
          ],

          // Location
          if (gsite.location != null) ...[
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.location_on),
              title: Text(gsite.location!.displayAddress),
              contentPadding: EdgeInsets.zero,
            ),
          ],

          const SizedBox(height: 100),
        ],
      ),
    );
  }
}
