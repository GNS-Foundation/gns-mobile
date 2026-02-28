// ============================================================
// GNS gSITE COMPOSABLE BLOCKS
// ============================================================
// Location: lib/core/gsite/gsite_blocks.dart
// Purpose: Block types, models, and HTML renderers
//
// Architecture:
//   gSite JSON includes a "sections" array of blocks:
//   { "sections": [
//       { "type": "hero", "title": "...", ... },
//       { "type": "portfolio", "items": [...] },
//       { "type": "pricing", "tiers": [...] },
//       { "type": "dix-feed", "count": 5 },
//       { "type": "payment-button", "amount": 50 },
//   ]}
//
//   Renderer iterates sections[] → calls block renderer
//   → each block emits self-contained HTML
//
// Blocks are like WordPress Gutenberg blocks or Squarespace
// sections, but with native GNS capabilities (payments,
// trust, verified identity, messaging).
// ============================================================

// ============================================================
// BLOCK TYPE REGISTRY
// ============================================================

enum GSiteBlockType {
  hero,
  about,
  skills,
  portfolio,
  testimonials,
  pricing,
  stats,
  gallery,
  cta,
  dixFeed,
  paymentButton,
  contact,
  embed,
  richText,
  faq,
  timeline,
  team,
}

class GSiteBlockRegistry {
  static const Map<String, GSiteBlockType> typeMap = {
    'hero': GSiteBlockType.hero,
    'about': GSiteBlockType.about,
    'skills': GSiteBlockType.skills,
    'portfolio': GSiteBlockType.portfolio,
    'testimonials': GSiteBlockType.testimonials,
    'pricing': GSiteBlockType.pricing,
    'stats': GSiteBlockType.stats,
    'gallery': GSiteBlockType.gallery,
    'cta': GSiteBlockType.cta,
    'dix-feed': GSiteBlockType.dixFeed,
    'payment-button': GSiteBlockType.paymentButton,
    'contact': GSiteBlockType.contact,
    'embed': GSiteBlockType.embed,
    'rich-text': GSiteBlockType.richText,
    'faq': GSiteBlockType.faq,
    'timeline': GSiteBlockType.timeline,
    'team': GSiteBlockType.team,
  };

  static const Map<GSiteBlockType, BlockMeta> metadata = {
    GSiteBlockType.hero: BlockMeta(
      name: 'Hero Banner',
      icon: '🎯',
      description: 'Full-width headline with optional background',
      category: 'layout',
    ),
    GSiteBlockType.about: BlockMeta(
      name: 'About',
      icon: '📝',
      description: 'Bio/about section with rich text',
      category: 'content',
    ),
    GSiteBlockType.skills: BlockMeta(
      name: 'Skills',
      icon: '💡',
      description: 'Skills or tags display',
      category: 'content',
    ),
    GSiteBlockType.portfolio: BlockMeta(
      name: 'Portfolio',
      icon: '🖼',
      description: 'Project showcase with images and links',
      category: 'showcase',
    ),
    GSiteBlockType.testimonials: BlockMeta(
      name: 'Testimonials',
      icon: '💬',
      description: 'Verified reviews from GNS identities',
      category: 'social-proof',
    ),
    GSiteBlockType.pricing: BlockMeta(
      name: 'Pricing',
      icon: '💰',
      description: 'Pricing tiers with GNS payment integration',
      category: 'commerce',
    ),
    GSiteBlockType.stats: BlockMeta(
      name: 'Stats',
      icon: '📊',
      description: 'Key metrics and numbers',
      category: 'content',
    ),
    GSiteBlockType.gallery: BlockMeta(
      name: 'Gallery',
      icon: '📸',
      description: 'Photo/image gallery grid',
      category: 'media',
    ),
    GSiteBlockType.cta: BlockMeta(
      name: 'Call to Action',
      icon: '🚀',
      description: 'Prominent action block with button',
      category: 'conversion',
    ),
    GSiteBlockType.dixFeed: BlockMeta(
      name: 'DiX Feed',
      icon: '📰',
      description: 'Latest DiX posts from your feed',
      category: 'content',
    ),
    GSiteBlockType.paymentButton: BlockMeta(
      name: 'Payment Button',
      icon: '💳',
      description: 'Accept payments via GNS/Stellar',
      category: 'commerce',
    ),
    GSiteBlockType.contact: BlockMeta(
      name: 'Contact',
      icon: '✉',
      description: 'Contact info with GNS messaging',
      category: 'contact',
    ),
    GSiteBlockType.embed: BlockMeta(
      name: 'Embed',
      icon: '🔗',
      description: 'Embed external content',
      category: 'media',
    ),
    GSiteBlockType.richText: BlockMeta(
      name: 'Rich Text',
      icon: '📄',
      description: 'Free-form text with markdown',
      category: 'content',
    ),
    GSiteBlockType.faq: BlockMeta(
      name: 'FAQ',
      icon: '❓',
      description: 'Frequently asked questions',
      category: 'content',
    ),
    GSiteBlockType.timeline: BlockMeta(
      name: 'Timeline',
      icon: '📅',
      description: 'Chronological timeline of events',
      category: 'content',
    ),
    GSiteBlockType.team: BlockMeta(
      name: 'Team',
      icon: '👥',
      description: 'Team members with GNS identity links',
      category: 'social-proof',
    ),
  };
}

class BlockMeta {
  final String name;
  final String icon;
  final String description;
  final String category;

  const BlockMeta({
    required this.name,
    required this.icon,
    required this.description,
    required this.category,
  });
}

// ============================================================
// BLOCK HTML RENDERER
// ============================================================

class GSiteBlockRenderer {
  /// Render all sections from a gSite's sections array
  static String renderSections(List<Map<String, dynamic>> sections) {
    return sections
        .map((block) => renderBlock(block))
        .where((html) => html.isNotEmpty)
        .join('\n');
  }

  /// Render a single block from its JSON definition
  static String renderBlock(Map<String, dynamic> block) {
    final type = block['type'] as String? ?? '';
    final blockType = GSiteBlockRegistry.typeMap[type];

    if (blockType == null) return '';

    switch (blockType) {
      case GSiteBlockType.hero:
        return _renderHero(block);
      case GSiteBlockType.about:
        return _renderAbout(block);
      case GSiteBlockType.skills:
        return _renderSkills(block);
      case GSiteBlockType.portfolio:
        return _renderPortfolio(block);
      case GSiteBlockType.testimonials:
        return _renderTestimonials(block);
      case GSiteBlockType.pricing:
        return _renderPricing(block);
      case GSiteBlockType.stats:
        return _renderStats(block);
      case GSiteBlockType.gallery:
        return _renderGallery(block);
      case GSiteBlockType.cta:
        return _renderCTA(block);
      case GSiteBlockType.dixFeed:
        return _renderDiXFeed(block);
      case GSiteBlockType.paymentButton:
        return _renderPaymentButton(block);
      case GSiteBlockType.contact:
        return _renderContact(block);
      case GSiteBlockType.richText:
        return _renderRichText(block);
      case GSiteBlockType.faq:
        return _renderFAQ(block);
      case GSiteBlockType.timeline:
        return _renderTimeline(block);
      case GSiteBlockType.team:
        return _renderTeam(block);
      default:
        return '';
    }
  }

  // ============================================================
  // INDIVIDUAL BLOCK RENDERERS
  // ============================================================

  /// Hero banner — full-width headline with optional background
  static String _renderHero(Map<String, dynamic> block) {
    final title = _esc(block['title'] as String? ?? '');
    final subtitle = _esc(block['subtitle'] as String? ?? '');
    final bgImage = block['backgroundImage'] as String?;
    final bgColor = block['backgroundColor'] as String?;
    final alignment = block['alignment'] as String? ?? 'center';

    final bgStyle = bgImage != null
        ? "background-image: linear-gradient(rgba(0,0,0,0.4), rgba(0,0,0,0.5)), url('${_esc(bgImage)}'); background-size: cover; background-position: center; color: white;"
        : bgColor != null
            ? "background: $bgColor; color: white;"
            : "background: var(--color-accent); color: var(--color-surface);";

    return '''
<section class="block-hero" style="$bgStyle text-align: $alignment; padding: 4rem 2rem; border-radius: var(--card-radius, 12px); margin-bottom: var(--section-margin, 2.25rem);">
  <h1 style="font-family: var(--font-display); font-size: 2.5rem; font-weight: 800; margin-bottom: 0.5rem; line-height: 1.2;">$title</h1>
  ${subtitle.isNotEmpty ? '<p style="font-size: 1.15rem; opacity: 0.9; max-width: 600px; margin: 0 auto; line-height: 1.6;">$subtitle</p>' : ''}
  ${block['buttonText'] != null ? '''
    <a href="${_esc(block['buttonUrl'] as String? ?? '#')}" class="action-btn action-primary" style="margin-top: 1.5rem; display: inline-flex; font-size: 1rem; padding: 0.7rem 1.5rem;">
      ${_esc(block['buttonText'] as String)}
    </a>
  ''' : ''}
</section>''';
  }

  /// About — Rich text bio section
  static String _renderAbout(Map<String, dynamic> block) {
    final title = _esc(block['title'] as String? ?? 'About');
    final content = block['content'] as String? ?? '';

    return '''
<section class="section">
  <h2 class="section-title">$title</h2>
  <div class="section-content">${_formatBio(content)}</div>
</section>''';
  }

  /// Skills — Tag cloud / chip display
  static String _renderSkills(Map<String, dynamic> block) {
    final title = _esc(block['title'] as String? ?? 'Skills');
    final items = (block['items'] as List<dynamic>?)?.cast<String>() ?? [];
    if (items.isEmpty) return '';

    return '''
<section class="section">
  <h2 class="section-title">$title</h2>
  <div class="tag-list">
    ${items.map((s) => '<span class="tag">${_esc(s)}</span>').join('')}
  </div>
</section>''';
  }

  /// Portfolio — Project showcase grid
  static String _renderPortfolio(Map<String, dynamic> block) {
    final title = _esc(block['title'] as String? ?? 'Portfolio');
    final items = (block['items'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    if (items.isEmpty) return '';

    return '''
<section class="section">
  <h2 class="section-title">$title</h2>
  <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 1.25rem; margin-top: 0.75rem;">
    ${items.map((item) {
      final name = _esc(item['name'] as String? ?? '');
      final desc = _esc(item['description'] as String? ?? '');
      final image = item['image'] as String?;
      final url = item['url'] as String?;
      final tags = (item['tags'] as List<dynamic>?)?.cast<String>() ?? [];
      return '''
    <div style="border: 1px solid var(--color-border); border-radius: var(--card-radius, 12px); overflow: hidden; transition: box-shadow 0.2s, transform 0.15s; background: var(--color-surface);">
      ${image != null ? '<div style="height: 180px; background-image: url(\'${_esc(image)}\'); background-size: cover; background-position: center;"></div>' : ''}
      <div style="padding: 1rem;">
        <h3 style="font-size: 1rem; font-weight: 600; margin-bottom: 0.3rem;">
          ${url != null ? '<a href="${_esc(url)}" target="_blank" style="color: var(--color-text);">$name</a>' : name}
        </h3>
        ${desc.isNotEmpty ? '<p style="font-size: 0.85rem; color: var(--color-text-muted); line-height: 1.5; margin-bottom: 0.5rem;">$desc</p>' : ''}
        ${tags.isNotEmpty ? '<div style="display: flex; gap: 0.3rem; flex-wrap: wrap;">${tags.map((t) => '<span style="font-size: 0.7rem; padding: 0.15rem 0.45rem; background: var(--color-accent-light); color: var(--color-accent); border-radius: var(--radius-full, 9999px);">${_esc(t)}</span>').join('')}</div>' : ''}
      </div>
    </div>''';
    }).join('\n')}
  </div>
</section>''';
  }

  /// Testimonials — Verified reviews from GNS identities
  static String _renderTestimonials(Map<String, dynamic> block) {
    final title = _esc(block['title'] as String? ?? 'What People Say');
    final items = (block['items'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    if (items.isEmpty) return '';

    return '''
<section class="section">
  <h2 class="section-title">$title</h2>
  <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 1rem; margin-top: 0.75rem;">
    ${items.map((item) {
      final quote = _esc(item['quote'] as String? ?? '');
      final name = _esc(item['name'] as String? ?? '');
      final handle = item['handle'] as String?;
      final role = _esc(item['role'] as String? ?? '');
      final trustScore = item['trustScore'] as num?;
      return '''
    <div style="padding: 1.25rem; border: 1px solid var(--color-border); border-radius: var(--card-radius, 12px); background: var(--color-surface);">
      <div style="font-size: 1.5rem; color: var(--color-accent); margin-bottom: 0.5rem; font-family: var(--font-display);">"</div>
      <p style="font-size: 0.9rem; color: var(--color-text-secondary); line-height: 1.65; margin-bottom: 1rem; font-style: italic;">$quote</p>
      <div style="display: flex; align-items: center; gap: 0.75rem;">
        <div style="width: 36px; height: 36px; border-radius: 50%; background: var(--color-accent-light); display: flex; align-items: center; justify-content: center; font-weight: 700; color: var(--color-accent); font-size: 0.85rem;">
          ${name.isNotEmpty ? _esc(name[0].toUpperCase()) : '?'}
        </div>
        <div>
          <div style="font-weight: 600; font-size: 0.85rem;">$name</div>
          <div style="font-size: 0.72rem; color: var(--color-text-muted);">
            ${handle != null ? '<span style="font-family: var(--font-mono);">@${_esc(handle)}</span>' : ''}
            ${role.isNotEmpty ? ' · $role' : ''}
            ${trustScore != null ? ' · <span style="color: var(--color-accent);">⬡ ${trustScore.round()}</span>' : ''}
          </div>
        </div>
      </div>
    </div>''';
    }).join('\n')}
  </div>
</section>''';
  }

  /// Pricing — Tier cards with GNS payment integration
  static String _renderPricing(Map<String, dynamic> block) {
    final title = _esc(block['title'] as String? ?? 'Pricing');
    final tiers = (block['tiers'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    if (tiers.isEmpty) return '';

    return '''
<section class="section">
  <h2 class="section-title">$title</h2>
  <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 1rem; margin-top: 0.75rem;">
    ${tiers.map((tier) {
      final name = _esc(tier['name'] as String? ?? '');
      final price = tier['price'] as num?;
      final currency = _esc(tier['currency'] as String? ?? 'GNS');
      final period = _esc(tier['period'] as String? ?? '');
      final features = (tier['features'] as List<dynamic>?)?.cast<String>() ?? [];
      final highlighted = tier['highlighted'] == true;
      final borderStyle = highlighted 
          ? 'border: 2px solid var(--color-accent); box-shadow: var(--shadow-md);'
          : 'border: 1px solid var(--color-border);';
      return '''
    <div style="$borderStyle border-radius: var(--card-radius, 12px); padding: 1.5rem; text-align: center; background: var(--color-surface); position: relative;">
      ${highlighted ? '<div style="position: absolute; top: -10px; left: 50%; transform: translateX(-50%); background: var(--color-accent); color: white; font-size: 0.68rem; font-weight: 600; padding: 0.2rem 0.7rem; border-radius: var(--radius-full, 9999px); text-transform: uppercase; letter-spacing: 0.05em;">Popular</div>' : ''}
      <div style="font-weight: 600; font-size: 1rem; margin-bottom: 0.5rem;">$name</div>
      <div style="font-family: var(--font-mono); font-size: 2rem; font-weight: 700; color: var(--color-accent); margin-bottom: 0.25rem;">
        ${price != null ? '$currency ${price.toStringAsFixed(price == price.roundToDouble() ? 0 : 2)}' : 'Free'}
      </div>
      ${period.isNotEmpty ? '<div style="font-size: 0.78rem; color: var(--color-text-muted); margin-bottom: 1rem;">$period</div>' : '<div style="margin-bottom: 1rem;"></div>'}
      <div style="text-align: left; margin-bottom: 1.25rem;">
        ${features.map((f) => '<div style="display: flex; align-items: center; gap: 0.4rem; padding: 0.3rem 0; font-size: 0.85rem; color: var(--color-text-secondary);"><span style="color: var(--color-success); font-weight: 700;">✓</span> ${_esc(f)}</div>').join('')}
      </div>
      <a href="#" class="action-btn ${highlighted ? 'action-primary' : 'action-secondary'}" style="width: 100%; justify-content: center;">
        💳 Pay with GNS
      </a>
    </div>''';
    }).join('\n')}
  </div>
</section>''';
  }

  /// Stats — Key metrics display
  static String _renderStats(Map<String, dynamic> block) {
    final items = (block['items'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    if (items.isEmpty) return '';

    return '''
<section class="section">
  <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 1rem; text-align: center;">
    ${items.map((item) {
      final value = _esc(item['value']?.toString() ?? '0');
      final label = _esc(item['label'] as String? ?? '');
      final icon = item['icon'] as String?;
      return '''
    <div style="padding: 1.25rem 0.75rem;">
      ${icon != null ? '<div style="font-size: 1.5rem; margin-bottom: 0.5rem;">${_esc(icon)}</div>' : ''}
      <div style="font-family: var(--font-mono); font-size: 2rem; font-weight: 700; color: var(--color-accent); line-height: 1;">$value</div>
      <div style="font-size: 0.78rem; color: var(--color-text-muted); margin-top: 0.35rem; text-transform: uppercase; letter-spacing: 0.06em;">$label</div>
    </div>''';
    }).join('\n')}
  </div>
</section>''';
  }

  /// Gallery — Image grid
  static String _renderGallery(Map<String, dynamic> block) {
    final title = block['title'] as String?;
    final images = (block['images'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    if (images.isEmpty) return '';
    final columns = block['columns'] as int? ?? 3;

    return '''
<section class="section">
  ${title != null ? '<h2 class="section-title">${_esc(title)}</h2>' : ''}
  <div style="display: grid; grid-template-columns: repeat($columns, 1fr); gap: 0.5rem; margin-top: 0.5rem;">
    ${images.map((img) {
      final url = _esc(img['url'] as String? ?? '');
      final alt = _esc(img['alt'] as String? ?? '');
      final caption = img['caption'] as String?;
      return '''
    <div style="border-radius: var(--card-radius, 8px); overflow: hidden; position: relative; aspect-ratio: 1;">
      <img src="$url" alt="$alt" style="width: 100%; height: 100%; object-fit: cover;">
      ${caption != null ? '<div style="position: absolute; bottom: 0; left: 0; right: 0; padding: 0.5rem; background: linear-gradient(transparent, rgba(0,0,0,0.6)); color: white; font-size: 0.75rem;">${_esc(caption)}</div>' : ''}
    </div>''';
    }).join('\n')}
  </div>
</section>''';
  }

  /// CTA — Call to Action block
  static String _renderCTA(Map<String, dynamic> block) {
    final title = _esc(block['title'] as String? ?? '');
    final subtitle = _esc(block['subtitle'] as String? ?? '');
    final buttonText = _esc(block['buttonText'] as String? ?? 'Get Started');
    final buttonUrl = _esc(block['buttonUrl'] as String? ?? '#');
    final style = block['style'] as String? ?? 'accent'; // accent, outline, subtle

    final bgStyle = style == 'accent'
        ? 'background: var(--color-accent); color: white;'
        : style == 'outline'
            ? 'background: var(--color-surface); border: 2px solid var(--color-accent); color: var(--color-text);'
            : 'background: var(--color-accent-light); color: var(--color-text);';

    final btnStyle = style == 'accent'
        ? 'background: white; color: var(--color-accent);'
        : 'background: var(--color-accent); color: white;';

    return '''
<section style="$bgStyle padding: 2.5rem 2rem; border-radius: var(--card-radius, 12px); text-align: center; margin-bottom: var(--section-margin, 2.25rem);">
  <h2 style="font-family: var(--font-display); font-size: 1.5rem; font-weight: 700; margin-bottom: 0.5rem;">$title</h2>
  ${subtitle.isNotEmpty ? '<p style="font-size: 0.95rem; opacity: 0.85; margin-bottom: 1.25rem; max-width: 500px; margin-left: auto; margin-right: auto;">$subtitle</p>' : ''}
  <a href="$buttonUrl" style="$btnStyle display: inline-flex; align-items: center; gap: 0.4rem; padding: 0.6rem 1.5rem; border-radius: var(--btn-radius, 8px); font-weight: 600; font-size: 0.9rem; text-decoration: none; font-family: var(--font-body);">$buttonText</a>
</section>''';
  }

  /// DiX Feed — Latest posts from identity's DiX
  static String _renderDiXFeed(Map<String, dynamic> block) {
    final title = _esc(block['title'] as String? ?? 'Latest Posts');
    final count = block['count'] as int? ?? 3;
    // Posts would be fetched dynamically server-side; placeholder for preview
    final posts = (block['posts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    if (posts.isEmpty) {
      return '''
<section class="section">
  <h2 class="section-title">$title</h2>
  <div style="padding: 2rem; text-align: center; border: 1px dashed var(--color-border); border-radius: var(--card-radius, 12px); color: var(--color-text-muted); font-size: 0.9rem;">
    📰 Your latest $count DiX posts will appear here
  </div>
</section>''';
    }

    return '''
<section class="section">
  <h2 class="section-title">$title</h2>
  <div style="display: flex; flex-direction: column; gap: 0.75rem; margin-top: 0.5rem;">
    ${posts.take(count).map((post) {
      final content = _esc(post['content'] as String? ?? '');
      final date = _esc(post['date'] as String? ?? '');
      return '''
    <article style="padding: 1rem 1.25rem; border: 1px solid var(--color-border); border-radius: var(--card-radius, 8px); background: var(--color-surface);">
      <p style="font-size: 0.9rem; color: var(--color-text-secondary); line-height: 1.6; margin-bottom: 0.5rem;">$content</p>
      <div style="font-size: 0.72rem; color: var(--color-text-muted);">$date</div>
    </article>''';
    }).join('\n')}
  </div>
</section>''';
  }

  /// Payment Button — Accept payments via GNS
  static String _renderPaymentButton(Map<String, dynamic> block) {
    final title = _esc(block['title'] as String? ?? 'Support');
    final description = _esc(block['description'] as String? ?? '');
    final amount = block['amount'] as num?;
    final currency = _esc(block['currency'] as String? ?? 'GNS');
    final buttonText = _esc(block['buttonText'] as String? ?? 'Pay with GNS');
    final presets = (block['presets'] as List<dynamic>?)?.cast<num>() ?? [];

    return '''
<section class="section">
  <div style="padding: 1.5rem; border: 2px solid var(--color-accent); border-radius: var(--card-radius, 12px); text-align: center; background: var(--color-surface);">
    <div style="font-size: 1.5rem; margin-bottom: 0.5rem;">💳</div>
    <h3 style="font-family: var(--font-display); font-size: 1.15rem; margin-bottom: 0.35rem;">$title</h3>
    ${description.isNotEmpty ? '<p style="font-size: 0.85rem; color: var(--color-text-muted); margin-bottom: 1rem;">$description</p>' : ''}
    ${presets.isNotEmpty ? '''
      <div style="display: flex; gap: 0.5rem; justify-content: center; margin-bottom: 1rem; flex-wrap: wrap;">
        ${presets.map((p) => '<button style="padding: 0.4rem 1rem; border: 1px solid var(--color-border); border-radius: var(--btn-radius, 8px); background: var(--color-surface); cursor: pointer; font-family: var(--font-mono); font-size: 0.85rem; color: var(--color-text);">$currency ${p.toStringAsFixed(p == p.roundToDouble() ? 0 : 2)}</button>').join('')}
      </div>
    ''' : ''}
    ${amount != null ? '<div style="font-family: var(--font-mono); font-size: 1.5rem; font-weight: 700; color: var(--color-accent); margin-bottom: 0.75rem;">$currency ${amount.toStringAsFixed(amount == amount.roundToDouble() ? 0 : 2)}</div>' : ''}
    <a href="#" class="action-btn action-primary" style="display: inline-flex; font-size: 0.95rem; padding: 0.6rem 1.5rem;">$buttonText</a>
    <div style="font-size: 0.68rem; color: var(--color-text-muted); margin-top: 0.75rem;">Powered by GNS Protocol · Stellar Network</div>
  </div>
</section>''';
  }

  /// Contact — Contact info with GNS messaging
  static String _renderContact(Map<String, dynamic> block) {
    final title = _esc(block['title'] as String? ?? 'Contact');
    final email = block['email'] as String?;
    final phone = block['phone'] as String?;
    final address = block['address'] as String?;
    final handle = block['handle'] as String?;

    return '''
<section class="section">
  <h2 class="section-title">$title</h2>
  <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-top: 0.75rem;">
    ${handle != null ? '''
    <div style="display: flex; align-items: center; gap: 0.75rem; padding: 1rem; border: 1px solid var(--color-border); border-radius: var(--card-radius, 8px); background: var(--color-surface);">
      <span style="font-size: 1.25rem;">💬</span>
      <div>
        <div style="font-size: 0.72rem; color: var(--color-text-muted); text-transform: uppercase; letter-spacing: 0.06em; font-weight: 600;">GNS Message</div>
        <div style="font-family: var(--font-mono); font-size: 0.85rem; color: var(--color-accent);">@${_esc(handle)}</div>
      </div>
    </div>''' : ''}
    ${email != null ? '''
    <div style="display: flex; align-items: center; gap: 0.75rem; padding: 1rem; border: 1px solid var(--color-border); border-radius: var(--card-radius, 8px); background: var(--color-surface);">
      <span style="font-size: 1.25rem;">✉</span>
      <div>
        <div style="font-size: 0.72rem; color: var(--color-text-muted); text-transform: uppercase; letter-spacing: 0.06em; font-weight: 600;">Email</div>
        <a href="mailto:${_esc(email)}" style="font-size: 0.85rem;">${_esc(email)}</a>
      </div>
    </div>''' : ''}
    ${phone != null ? '''
    <div style="display: flex; align-items: center; gap: 0.75rem; padding: 1rem; border: 1px solid var(--color-border); border-radius: var(--card-radius, 8px); background: var(--color-surface);">
      <span style="font-size: 1.25rem;">📞</span>
      <div>
        <div style="font-size: 0.72rem; color: var(--color-text-muted); text-transform: uppercase; letter-spacing: 0.06em; font-weight: 600;">Phone</div>
        <a href="tel:${_esc(phone)}" style="font-size: 0.85rem;">${_esc(phone)}</a>
      </div>
    </div>''' : ''}
    ${address != null ? '''
    <div style="display: flex; align-items: center; gap: 0.75rem; padding: 1rem; border: 1px solid var(--color-border); border-radius: var(--card-radius, 8px); background: var(--color-surface);">
      <span style="font-size: 1.25rem;">📍</span>
      <div>
        <div style="font-size: 0.72rem; color: var(--color-text-muted); text-transform: uppercase; letter-spacing: 0.06em; font-weight: 600;">Location</div>
        <div style="font-size: 0.85rem; color: var(--color-text-secondary);">${_esc(address)}</div>
      </div>
    </div>''' : ''}
  </div>
</section>''';
  }

  /// Rich Text — Free-form content
  static String _renderRichText(Map<String, dynamic> block) {
    final title = block['title'] as String?;
    final content = block['content'] as String? ?? '';

    return '''
<section class="section">
  ${title != null ? '<h2 class="section-title">${_esc(title)}</h2>' : ''}
  <div class="section-content">${_formatBio(content)}</div>
</section>''';
  }

  /// FAQ — Expandable questions
  static String _renderFAQ(Map<String, dynamic> block) {
    final title = _esc(block['title'] as String? ?? 'FAQ');
    final items = (block['items'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    if (items.isEmpty) return '';

    return '''
<section class="section">
  <h2 class="section-title">$title</h2>
  <div style="margin-top: 0.5rem;">
    ${items.asMap().entries.map((entry) {
      final q = _esc(entry.value['question'] as String? ?? '');
      final a = _esc(entry.value['answer'] as String? ?? '');
      return '''
    <details style="border: 1px solid var(--color-border); border-radius: var(--card-radius, 8px); margin-bottom: 0.5rem; background: var(--color-surface);">
      <summary style="padding: 0.85rem 1rem; cursor: pointer; font-weight: 600; font-size: 0.9rem; list-style: none; display: flex; justify-content: space-between; align-items: center;">
        $q
        <span style="color: var(--color-text-muted); font-size: 0.8rem;">▸</span>
      </summary>
      <div style="padding: 0 1rem 0.85rem; font-size: 0.88rem; color: var(--color-text-secondary); line-height: 1.65;">$a</div>
    </details>''';
    }).join('\n')}
  </div>
</section>''';
  }

  /// Timeline — Chronological events
  static String _renderTimeline(Map<String, dynamic> block) {
    final title = _esc(block['title'] as String? ?? 'Experience');
    final items = (block['items'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    if (items.isEmpty) return '';

    return '''
<section class="section">
  <h2 class="section-title">$title</h2>
  <div style="position: relative; margin-top: 1rem; padding-left: 2rem;">
    <div style="position: absolute; left: 7px; top: 4px; bottom: 4px; width: 2px; background: var(--color-border);"></div>
    ${items.map((item) {
      final date = _esc(item['date'] as String? ?? '');
      final heading = _esc(item['title'] as String? ?? '');
      final subtitle = _esc(item['subtitle'] as String? ?? '');
      final desc = item['description'] as String?;
      return '''
    <div style="position: relative; margin-bottom: 1.5rem;">
      <div style="position: absolute; left: -2rem; top: 4px; width: 16px; height: 16px; border-radius: 50%; background: var(--color-accent); border: 3px solid var(--color-bg);"></div>
      <div style="font-size: 0.72rem; color: var(--color-text-muted); font-family: var(--font-mono); margin-bottom: 0.25rem;">$date</div>
      <div style="font-weight: 600; font-size: 0.95rem;">$heading</div>
      ${subtitle.isNotEmpty ? '<div style="font-size: 0.82rem; color: var(--color-accent);">$subtitle</div>' : ''}
      ${desc != null ? '<p style="font-size: 0.85rem; color: var(--color-text-secondary); line-height: 1.6; margin-top: 0.35rem;">${_esc(desc)}</p>' : ''}
    </div>''';
    }).join('\n')}
  </div>
</section>''';
  }

  /// Team — Team members with GNS links
  static String _renderTeam(Map<String, dynamic> block) {
    final title = _esc(block['title'] as String? ?? 'Team');
    final members = (block['members'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    if (members.isEmpty) return '';

    return '''
<section class="section">
  <h2 class="section-title">$title</h2>
  <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: 1rem; margin-top: 0.75rem;">
    ${members.map((m) {
      final name = _esc(m['name'] as String? ?? '');
      final role = _esc(m['role'] as String? ?? '');
      final handle = m['handle'] as String?;
      final avatar = m['avatar'] as String?;
      final trustScore = m['trustScore'] as num?;
      return '''
    <div style="text-align: center; padding: 1.25rem; border: 1px solid var(--color-border); border-radius: var(--card-radius, 12px); background: var(--color-surface);">
      <div style="width: 64px; height: 64px; border-radius: var(--avatar-radius, 50%); margin: 0 auto 0.75rem; overflow: hidden; background: var(--color-accent-light); display: flex; align-items: center; justify-content: center;">
        ${avatar != null ? '<img src="${_esc(avatar)}" style="width:100%;height:100%;object-fit:cover;">' : '<span style="font-family:var(--font-display);font-size:1.5rem;color:var(--color-accent);font-weight:700;">${name.isNotEmpty ? _esc(name[0].toUpperCase()) : '?'}</span>'}
      </div>
      <div style="font-weight: 600; font-size: 0.88rem;">$name</div>
      <div style="font-size: 0.78rem; color: var(--color-text-muted);">$role</div>
      ${handle != null ? '<div style="font-family:var(--font-mono);font-size:0.72rem;color:var(--color-accent);margin-top:0.25rem;">@${_esc(handle)}</div>' : ''}
      ${trustScore != null ? '<div style="font-size:0.68rem;color:var(--color-text-muted);margin-top:0.2rem;">⬡ ${trustScore.round()}</div>' : ''}
    </div>''';
    }).join('\n')}
  </div>
</section>''';
  }

  // ============================================================
  // HELPERS
  // ============================================================

  static String _esc(String? s) {
    if (s == null) return '';
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  static String _formatBio(String bio) {
    return bio
        .split(RegExp(r'\n\n+'))
        .map((p) => '<p>${_esc(p.trim()).replaceAll('\n', '<br>')}</p>')
        .join('');
  }
}

// ============================================================
// BLOCK TEMPLATES (starter configurations)
// ============================================================

class BlockTemplates {
  /// Get a starter block JSON for a given type
  static Map<String, dynamic> starter(String type) {
    switch (type) {
      case 'hero':
        return {
          'type': 'hero',
          'title': 'Hello, I\'m [Your Name]',
          'subtitle': 'A brief introduction about what you do',
          'buttonText': 'Get in Touch',
          'buttonUrl': '#contact',
        };
      case 'portfolio':
        return {
          'type': 'portfolio',
          'title': 'Portfolio',
          'items': [
            {
              'name': 'Project Name',
              'description': 'Brief description of the project',
              'tags': ['Tag 1', 'Tag 2'],
            },
          ],
        };
      case 'testimonials':
        return {
          'type': 'testimonials',
          'title': 'What People Say',
          'items': [
            {
              'quote': 'A great experience working together!',
              'name': 'Jane Doe',
              'handle': 'janedoe',
              'role': 'CEO, Company',
              'trustScore': 78,
            },
          ],
        };
      case 'pricing':
        return {
          'type': 'pricing',
          'title': 'Pricing',
          'tiers': [
            {
              'name': 'Starter',
              'price': 0,
              'currency': 'GNS',
              'features': ['Feature 1', 'Feature 2'],
            },
            {
              'name': 'Pro',
              'price': 50,
              'currency': 'GNS',
              'period': 'per month',
              'features': ['Everything in Starter', 'Feature 3', 'Feature 4'],
              'highlighted': true,
            },
          ],
        };
      case 'stats':
        return {
          'type': 'stats',
          'items': [
            {'value': '1.2K', 'label': 'Breadcrumbs', 'icon': '🗺'},
            {'value': '85', 'label': 'Trust Score', 'icon': '⬡'},
            {'value': '12', 'label': 'Facets', 'icon': '🔷'},
          ],
        };
      case 'cta':
        return {
          'type': 'cta',
          'title': 'Ready to get started?',
          'subtitle': 'Claim your GNS handle and join the decentralized web.',
          'buttonText': 'Claim Handle →',
          'buttonUrl': 'https://gnamesystem.netlify.app',
          'style': 'accent',
        };
      case 'dix-feed':
        return {
          'type': 'dix-feed',
          'title': 'Latest Posts',
          'count': 3,
          'posts': [],
        };
      case 'payment-button':
        return {
          'type': 'payment-button',
          'title': 'Support My Work',
          'description': 'Pay via GNS Protocol on Stellar Network',
          'currency': 'GNS',
          'presets': [10, 25, 50, 100],
          'buttonText': 'Pay with GNS',
        };
      case 'contact':
        return {
          'type': 'contact',
          'title': 'Get in Touch',
          'handle': 'yourhandle',
        };
      case 'faq':
        return {
          'type': 'faq',
          'title': 'FAQ',
          'items': [
            {
              'question': 'What is GNS?',
              'answer': 'The Geospatial Naming System — a decentralized identity protocol.',
            },
          ],
        };
      case 'timeline':
        return {
          'type': 'timeline',
          'title': 'Experience',
          'items': [
            {
              'date': '2024 – Present',
              'title': 'Position Title',
              'subtitle': 'Company Name',
              'description': 'What you did here...',
            },
          ],
        };
      case 'team':
        return {
          'type': 'team',
          'title': 'Team',
          'members': [
            {
              'name': 'Team Member',
              'role': 'Role',
              'handle': 'handle',
              'trustScore': 75,
            },
          ],
        };
      case 'gallery':
        return {
          'type': 'gallery',
          'title': 'Gallery',
          'columns': 3,
          'images': [],
        };
      case 'rich-text':
        return {
          'type': 'rich-text',
          'title': 'Section Title',
          'content': 'Your content here...',
        };
      default:
        return {'type': type};
    }
  }
}
