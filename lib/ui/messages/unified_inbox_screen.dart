/// Unified Inbox Screen — Globe Crumbs
///
/// PageView architecture: 3 horizontal pages
///   Page 0 — 💬 Chats    (default, opens here always)
///   Page 1 — 🌐 DIX      (public feed)
///   Page 2 — ✉️  Email   (email threads)
///
/// Navigation: swipe horizontally OR tap the 3-icon pill indicator.
/// FAB changes per page. Stories bar on Chats page only.
///
/// Location: lib/ui/messages/unified_inbox_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/comm/communication_service.dart';
import '../../core/comm/message_storage.dart';
import '../../core/comm/gns_envelope.dart';
import '../../core/contacts/contact_entry.dart';
import '../../core/contacts/contact_storage.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/theme/theme_service.dart';
import '../../core/dix/dix_post_service.dart';
import 'conversation_screen.dart';
import 'new_conversation_screen.dart';
import 'email_list_screen.dart';
import 'email_compose_screen.dart';
import '../dix/dix_timeline_screen.dart';
import '../dix/dix_compose_screen.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const String _emailGatewayPk =
    '007dd9b2c19308dd0e2dfc044da05a522a1d1adbd6f1c84147cc4e0b7a4bd53d';

const int _pageChats = 0;
const int _pageDix   = 1;
const int _pageEmail = 2;

// ─── Trust tier ───────────────────────────────────────────────────────────────

enum _TrustTier { seedling, explorer, navigator, trailblazer, sovereign }

_TrustTier _tierFromScore(double? score) {
  if (score == null) return _TrustTier.seedling;
  if (score >= 90)   return _TrustTier.sovereign;
  if (score >= 70)   return _TrustTier.trailblazer;
  if (score >= 50)   return _TrustTier.navigator;
  if (score >= 25)   return _TrustTier.explorer;
  return _TrustTier.seedling;
}

Color _tierColor(_TrustTier tier) {
  switch (tier) {
    case _TrustTier.sovereign:   return const Color(0xFFFFD700);
    case _TrustTier.trailblazer: return const Color(0xFF8B5CF6);
    case _TrustTier.navigator:   return const Color(0xFF3B82F6);
    case _TrustTier.explorer:    return const Color(0xFF10B981);
    case _TrustTier.seedling:    return const Color(0xFF6E7681);
  }
}

// ─── Main Screen ──────────────────────────────────────────────────────────────

class UnifiedInboxScreen extends StatefulWidget {
  const UnifiedInboxScreen({super.key});

  @override
  State<UnifiedInboxScreen> createState() => _UnifiedInboxScreenState();
}

class _UnifiedInboxScreenState extends State<UnifiedInboxScreen>
    with TickerProviderStateMixin {

  // ── Services ──────────────────────────────────────────────────────────────
  final _wallet         = IdentityWallet();
  final _contactStorage = ContactStorage();
  CommunicationService? _commService;

  // ── Data ──────────────────────────────────────────────────────────────────
  List<ThreadWithPreview>   _threads  = [];
  List<DixPost>             _dixPosts = [];
  Map<String, ContactEntry> _contacts = {};
  String? _myHandle;
  String? _myPublicKey;
  int     _emailUnread = 0;

  // ── State ─────────────────────────────────────────────────────────────────
  bool                _loading   = true;
  CommConnectionState _connState = CommConnectionState.disconnected;

  // ── PageView ──────────────────────────────────────────────────────────────
  late final PageController _pageController;
  int _currentPage = _pageChats;

  // ── Search ────────────────────────────────────────────────────────────────
  bool   _searchOpen = false;
  final  _searchController = TextEditingController();
  String _searchQuery = '';
  late final AnimationController _searchAnim;

  // ── Subscriptions ─────────────────────────────────────────────────────────
  StreamSubscription? _msgSub;
  StreamSubscription? _connSub;

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _pageChats);
    _searchAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _initialize();
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _connSub?.cancel();
    _pageController.dispose();
    _searchController.dispose();
    _searchAnim.dispose();
    super.dispose();
  }

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> _initialize() async {
    if (!_wallet.isInitialized) await _wallet.initialize();
    _myPublicKey = _wallet.publicKeyHex;
    _myHandle    = await _wallet.getCurrentHandle();

    _commService = CommunicationService.instance(_wallet);
    await _commService!.initialize();

    _msgSub  = _commService!.incomingMessages.listen((_) {
      if (mounted) _loadAll();
    });
    _connSub = _commService!.connectionState.listen((s) {
      if (mounted) setState(() => _connState = s);
    });

    await _loadAll();
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    try {
      final allThreads = await _commService!.getThreads();
      final contacts   = await _contactStorage.getAllContacts();
      final cache      = <String, ContactEntry>{};
      for (final c in contacts) cache[c.publicKey.toLowerCase()] = c;

      // Split email from DM threads
      final dmThreads = allThreads.where((t) => !t.thread.participantKeys
          .any((k) => k.toLowerCase() == _emailGatewayPk.toLowerCase())).toList();

      final emailThread = allThreads.firstWhere(
        (t) => t.thread.participantKeys
            .any((k) => k.toLowerCase() == _emailGatewayPk.toLowerCase()),
        orElse: () => ThreadWithPreview(
          thread: GnsThread(
            id: 'email-placeholder', type: 'direct',
            participantKeys: [_emailGatewayPk],
            createdAt: DateTime.now(),
            lastActivityAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
          lastMessage: null,
        ),
      );

      List<DixPost> dix = [];
      try {
        dix = await DixPostService().getTimeline(limit: 20);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _threads     = dmThreads;
          _contacts    = cache;
          _dixPosts    = dix;
          _emailUnread = emailThread.thread.unreadCount;
          _loading     = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Page navigation ───────────────────────────────────────────────────────

  void _jumpToPage(int page) {
    HapticFeedback.selectionClick();
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // ── Routing ───────────────────────────────────────────────────────────────

  void _openThread(ThreadWithPreview t) {
    if (_commService == null) return;
    Navigator.push(context, _slide(ConversationScreen(
      thread: t.thread,
      commService: _commService!,
    ))).then((_) => _loadAll());
  }

  void _openNewChat() => Navigator.push(
    context,
    _slide(NewConversationScreen(commService: _commService!, wallet: _wallet)),
  ).then((_) => _loadAll());

  void _openNewEmail() => Navigator.push(
    context, _slide(EmailComposeScreen(wallet: _wallet)));

  PageRoute _slide(Widget page) => PageRouteBuilder(
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, anim, __, child) => SlideTransition(
      position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: child,
    ),
    transitionDuration: const Duration(milliseconds: 280),
  );

  // ── Search ────────────────────────────────────────────────────────────────

  void _toggleSearch() {
    setState(() => _searchOpen = !_searchOpen);
    if (_searchOpen) {
      _searchAnim.forward();
    } else {
      _searchAnim.reverse();
      _searchController.clear();
      setState(() => _searchQuery = '');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeService().isDark;
    final surface = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      appBar: _buildAppBar(isDark, surface),
      body: Column(
        children: [
          // Search bar (animated, Chats only)
          SizeTransition(
            sizeFactor: CurvedAnimation(
              parent: _searchAnim, curve: Curves.easeInOut),
            child: _buildSearchBar(isDark, surface),
          ),

          // 3-circle tab bar
          _buildCircleTabs(isDark, surface),

          // The 3 pages
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (i) {
                HapticFeedback.selectionClick();
                setState(() {
                  _currentPage = i;
                  if (i != _pageChats && _searchOpen) _toggleSearch();
                });
              },
              children: [
                _buildChatsPage(isDark),
                const DixTimelineScreen(),
                _buildEmailPage(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFab(),
    );
  }

  // ── App Bar ───────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(bool isDark, Color surface) {
    final muted = isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted;
    return AppBar(
      backgroundColor: surface,
      elevation: 0,
      centerTitle: false,
      titleSpacing: 16,
      title: Row(children: [
        Text(
          _myHandle != null ? '@$_myHandle' : 'Messages',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        const SizedBox(width: 8),
        _connDot(),
      ]),
      actions: [
        if (_currentPage == _pageChats)
          IconButton(
            icon: Icon(
              _searchOpen ? Icons.close_rounded : Icons.search_rounded,
              color: muted),
            onPressed: _toggleSearch,
          ),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded, color: muted),
          color: surface,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'archive', child: Text('Archived')),
            PopupMenuItem(value: 'settings', child: Text('Settings')),
          ],
        ),
      ],
    );
  }

  Widget _connDot() {
    final color = _connState == CommConnectionState.connected
        ? AppTheme.secondary
        : _connState == CommConnectionState.connecting
            ? AppTheme.warning
            : AppTheme.error;
    return Container(
      width: 8, height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  // ── Search bar ────────────────────────────────────────────────────────────

  Widget _buildSearchBar(bool isDark, Color surface) {
    return Container(
      color: surface,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        style: TextStyle(
          fontSize: 16,
          color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary),
        decoration: InputDecoration(
          hintText: 'Search conversations…',
          hintStyle: TextStyle(
            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          filled: true,
          fillColor: isDark ? AppTheme.darkSurfaceLight : AppTheme.lightSurfaceLight,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none),
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  // ── 3-circle tab bar ─────────────────────────────────────────────────────

  Widget _buildCircleTabs(bool isDark, Color surface) {
    final muted = isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted;
    final bg    = isDark ? AppTheme.darkSurfaceLight : const Color(0xFFEEF0F3);

    final tabs = [
      (Icons.chat_bubble_rounded, 'Chat',  _pageChats,
       _threads.fold(0, (s, t) => s + t.thread.unreadCount)),
      (Icons.public_rounded,      'DIX',   _pageDix,   0),
      (Icons.mail_rounded,        'Email', _pageEmail, _emailUnread),
    ];

    return Container(
      color: surface,
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: tabs.map((tab) {
          final (icon, label, page, badge) = tab;
          final active = _currentPage == page;
          final color  = active ? AppTheme.primary : muted;

          return GestureDetector(
            onTap: () => _jumpToPage(page),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(clipBehavior: Clip.none, children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active ? AppTheme.primary.withOpacity(0.12) : bg,
                      border: Border.all(
                        color: active ? AppTheme.primary : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  if (badge > 0)
                    Positioned(
                      right: -2, top: -2,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        height: 18,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: surface, width: 1.5),
                        ),
                        child: Center(child: Text(
                          badge > 99 ? '99+' : '$badge',
                          style: const TextStyle(
                            color: Colors.white, fontSize: 10,
                            fontWeight: FontWeight.bold))),
                      ),
                    ),
                ]),
                const SizedBox(height: 5),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 220),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    color: color,
                  ),
                  child: Text(label),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
  // ── Stories bar ───────────────────────────────────────────────────────────

  Widget _buildStoriesBar(bool isDark, Color surface) {
    final seen    = <String>{};
    final authors = <DixPost>[];
    for (final p in _dixPosts) {
      if (!seen.contains(p.authorPk)) {
        seen.add(p.authorPk);
        authors.add(p);
        if (authors.length >= 7) break;
      }
    }

    return Container(
      height: 88,
      color: surface,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: authors.length + 1,
        itemBuilder: (_, i) =>
            i == 0 ? _myStoryCircle(isDark, surface) : _storyCircle(authors[i - 1], isDark, surface),
      ),
    );
  }

  Widget _myStoryCircle(bool isDark, Color surface) {
    return GestureDetector(
      onTap: () => _jumpToPage(_pageDix),
      child: Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(alignment: Alignment.bottomRight, children: [
            CircleAvatar(
              radius: 26,
              backgroundColor:
                  isDark ? AppTheme.darkSurfaceLight : AppTheme.lightSurfaceLight,
              child: Icon(Icons.person_rounded,
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                size: 26),
            ),
            Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                color: AppTheme.primary, shape: BoxShape.circle,
                border: Border.all(color: surface, width: 2)),
              child: const Icon(Icons.add_rounded, size: 12, color: Colors.white),
            ),
          ]),
          const SizedBox(height: 4),
          Text('My DIX', style: TextStyle(
            fontSize: 10,
            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted)),
        ]),
      ),
    );
  }

  Widget _storyCircle(DixPost post, bool isDark, Color surface) {
    final contact = _contacts[post.authorPk.toLowerCase()];
    final tier    = _tierFromScore(contact?.trustScore);
    final tc      = _tierColor(tier);
    final label   = contact?.handle ?? post.authorPk.substring(0, 6);

    return GestureDetector(
      onTap: () => _jumpToPage(_pageDix),
      child: Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [tc, tc.withOpacity(0.5)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            padding: const EdgeInsets.all(2.5),
            child: Container(
              decoration: BoxDecoration(shape: BoxShape.circle, color: surface),
              padding: const EdgeInsets.all(2),
              child: CircleAvatar(
                backgroundColor:
                    isDark ? AppTheme.darkSurfaceLight : AppTheme.lightSurfaceLight,
                child: Text(label.substring(0, 1).toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16, color: tc)),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text('@$label',
            style: TextStyle(fontSize: 10,
              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
            overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }

  // ── Chats page ────────────────────────────────────────────────────────────

  Widget _buildChatsPage(bool isDark) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final filtered = _searchQuery.isEmpty
        ? _threads
        : _threads.where((t) {
            final q  = _searchQuery.toLowerCase();
            final pk = t.thread.participantKeys.firstWhere(
              (k) => k.toLowerCase() != (_myPublicKey?.toLowerCase() ?? ''),
              orElse: () => '');
            final contact = _contacts[pk.toLowerCase()];
            return (contact?.displayTitle.toLowerCase().contains(q) ?? false) ||
                (t.lastMessage?.previewText.toLowerCase().contains(q) ?? false);
          }).toList();

    if (filtered.isEmpty) {
      return _emptyChats(isDark);
    }

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: filtered.length,
        itemBuilder: (_, i) => _chatRow(filtered[i], isDark),
      ),
    );
  }

  Widget _emptyChats(bool isDark) {
    final c = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.chat_bubble_outline_rounded, size: 56, color: c.withOpacity(0.35)),
      const SizedBox(height: 16),
      Text(
        _searchQuery.isEmpty
            ? 'No conversations yet.\nTap ✏️ to start one.'
            : 'No results for "$_searchQuery"',
        textAlign: TextAlign.center,
        style: TextStyle(color: c, fontSize: 15, height: 1.6)),
    ]));
  }

  // ── Chat row ──────────────────────────────────────────────────────────────

  Widget _chatRow(ThreadWithPreview t, bool isDark) {
    final otherPk = t.thread.participantKeys.firstWhere(
      (k) => k.toLowerCase() != (_myPublicKey?.toLowerCase() ?? ''),
      orElse: () => t.thread.participantKeys.first,
    );
    final contact = _contacts[otherPk.toLowerCase()];
    final tier    = _tierFromScore(contact?.trustScore);
    final tc      = _tierColor(tier);
    final unread  = t.thread.unreadCount;
    final title   = contact?.displayTitle ?? '${otherPk.substring(0, 8)}…';
    final initial = title.replaceAll('@', '').isEmpty
        ? '?'
        : title.replaceAll('@', '').substring(0, 1).toUpperCase();
    final preview = t.lastMessage == null
        ? 'No messages yet'
        : (t.lastMessage!.isOutgoing ? 'You: ' : '') + t.lastMessage!.previewText;
    final time    = t.lastMessage == null ? '' : _fmtTime(t.lastMessage!.timestamp);

    final primary   = isDark ? AppTheme.darkTextPrimary   : AppTheme.lightTextPrimary;
    final secondary = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    final muted     = isDark ? AppTheme.darkTextMuted     : AppTheme.lightTextMuted;
    final border    = isDark ? AppTheme.darkBorder        : AppTheme.lightBorder;

    return Dismissible(
      key: Key(t.thread.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async => false,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: AppTheme.error.withOpacity(0.12),
        child: const Icon(Icons.archive_rounded, color: AppTheme.error),
      ),
      child: InkWell(
        onTap: () => _openThread(t),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: border, width: 0.5))),
          child: Row(children: [
            // Avatar + tier dot
            Stack(children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? AppTheme.darkSurfaceLight : AppTheme.lightSurfaceLight,
                  border: Border.all(
                    color: unread > 0 ? tc : border,
                    width: unread > 0 ? 2.5 : 1.5),
                ),
                child: Center(child: Text(initial,
                  style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700, color: tc))),
              ),
              Positioned(right: 0, bottom: 0,
                child: Container(
                  width: 14, height: 14,
                  decoration: BoxDecoration(
                    color: tc, shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
                      width: 2)),
                ),
              ),
            ]),
            const SizedBox(width: 12),
            // Text
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: TextStyle(
                  fontSize: 15,
                  fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500,
                  color: primary),
                  overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text(preview, style: TextStyle(
                  fontSize: 13,
                  color: unread > 0 ? secondary : muted,
                  fontWeight: unread > 0 ? FontWeight.w500 : FontWeight.w400),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            )),
            const SizedBox(width: 8),
            // Time + badge
            Column(crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(time, style: TextStyle(
                  fontSize: 11,
                  color: unread > 0 ? AppTheme.primary : muted,
                  fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400)),
                const SizedBox(height: 5),
                if (unread > 0)
                  Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(10)),
                    child: Center(child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: const TextStyle(
                        color: Colors.white, fontSize: 11,
                        fontWeight: FontWeight.w700))),
                  )
                else
                  const SizedBox(height: 20),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  // ── Email page ────────────────────────────────────────────────────────────

  Widget _buildEmailPage() {
    if (_commService == null || _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return EmailListScreen(
      commService: _commService!,
      wallet: _wallet,
    );
  }

  // ── FAB ───────────────────────────────────────────────────────────────────

  Widget _buildFab() {
    final (icon, action) = switch (_currentPage) {
      _pageDix   => (Icons.edit_rounded,
                     () => Navigator.push(context, _slide(const DixComposeScreen()))),
      _pageEmail => (Icons.mail_rounded, _openNewEmail),
      _          => (Icons.edit_rounded, _openNewChat),
    };
    return FloatingActionButton(
      onPressed: action,
      backgroundColor: AppTheme.primary,
      child: Icon(icon, color: Colors.white),
    );
  }

  // ── Time ──────────────────────────────────────────────────────────────────

  String _fmtTime(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inSeconds < 60)  return 'now';
    if (d.inMinutes < 60)  return '${d.inMinutes}m';
    if (d.inHours < 24)    return '${d.inHours}h';
    if (d.inDays == 1)     return 'yesterday';
    if (d.inDays < 7)      return '${d.inDays}d';
    return '${dt.day}/${dt.month}';
  }
}
