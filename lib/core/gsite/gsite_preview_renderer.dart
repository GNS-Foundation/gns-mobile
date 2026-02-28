// ============================================================
// GNS gSITE PREVIEW RENDERER v2
// ============================================================
// Location: lib/core/gsite/gsite_preview_renderer.dart
// UPDATED: Theme support + Composable Blocks
//
// Changes from v1:
//   - renderFromJsonWithTheme() accepts theme CSS overrides
//   - renderFromJsonWithBlocks() renders composable sections
//   - Theme CSS replaces hardcoded :root variables
//   - Block sections inserted into content area
// ============================================================

import 'gsite_models.dart';
import 'gsite_theme_engine.dart';
import 'gsite_blocks.dart';

class GSitePreviewRenderer {

  // ============================================================
  // PUBLIC API
  // ============================================================

  /// Standard render (default Academic theme)
  static String renderFromJson(Map<String, dynamic> json) {
    return _renderPage(json, null);
  }

  /// Render with custom theme CSS
  static String renderFromJsonWithTheme(
      Map<String, dynamic> json, String themeCSS) {
    return _renderPage(json, themeCSS);
  }

  /// Render with theme object
  static String renderFromJsonWithThemeObj(
      Map<String, dynamic> json, GSiteTheme theme) {
    return _renderPage(json, ThemeEngine.generateCSS(theme));
  }

  // ============================================================
  // CORE RENDER ENGINE
  // ============================================================

  static String _renderPage(Map<String, dynamic> data, String? themeCSS) {
    final type = data['@type'] as String? ?? 'Person';
    final handle = (data['@id'] as String? ?? '@preview').replaceFirst('@', '');

    if (type == 'Person') {
      return _renderPersonPage(data, handle, themeCSS);
    }
    return _renderBusinessPage(data, handle, themeCSS);
  }

  // ============================================================
  // PERSON PAGE (with theme + blocks support)
  // ============================================================

  static String _renderPersonPage(
      Map<String, dynamic> data, String handle, String? themeCSS) {
    final name = _esc(data['name'] as String? ?? handle);
    final tagline = data['tagline'] as String?;
    final bio = data['bio'] as String?;
    final avatarUrl = data['avatar']?['url'] as String?;
    final skills = (data['skills'] as List<dynamic>?)?.cast<String>() ?? [];
    final interests = (data['interests'] as List<dynamic>?)?.cast<String>() ?? [];
    final links = (data['links'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final facets = (data['facets'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final trust = data['trust'] as Map<String, dynamic>?;
    final location = data['location'] as Map<String, dynamic>?;
    final status = data['status'] as Map<String, dynamic>?;
    final verified = data['verified'] as bool? ?? false;
    final publicKey = data['publicKey'] as String?;

    // Composable blocks
    final sections = (data['sections'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final hasBlocks = sections.isNotEmpty;

    final trustScore = (trust?['score'] as num?)?.toDouble() ?? 0;
    final trustClass = _trustClass(trustScore);
    final breadcrumbs = trust?['breadcrumbs'] as int? ?? 0;
    final since = trust?['since'] as String?;
    final locationStr = _formatLocation(location);
    final verifications = (trust?['verifications'] as List<dynamic>?)
        ?.cast<Map<String, dynamic>>() ?? [];

    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta property="og:title" content="$name (@$handle)">
  <meta property="og:description" content="${_esc(tagline ?? bio ?? 'GNS Identity')}">
  <meta property="og:type" content="profile">
  <meta property="og:url" content="https://ulissy.app/@$handle">
  <meta name="gns:handle" content="@$handle">
  <meta name="gns:protocol" content="gns/1.0">
  <title>$name — @$handle</title>
  ${themeCSS ?? _defaultThemeCSS()}
  ${_baseCSSRules()}
</head>
<body>
  <div class="page-wrapper">

    <!-- SIDEBAR -->
    <aside class="sidebar">
      <div class="avatar-container">
        ${avatarUrl != null && avatarUrl.isNotEmpty
          ? '<img src="${_esc(avatarUrl)}" alt="$name">'
          : '<span class="avatar-initial">${name.isNotEmpty ? _esc(name[0].toUpperCase()) : "?"}</span>'}
      </div>

      <div class="sidebar-name">$name</div>
      <div class="sidebar-handle">@${_esc(handle)}</div>

      ${verified ? '<span class="verified-badge">✓ Verified Identity</span>' : ''}

      ${tagline != null ? '<div class="sidebar-tagline">${_esc(tagline)}</div>' : ''}

      ${status != null && status['text'] != null ? '''
        <div class="sidebar-status ${status['available'] != false ? 'status-available' : 'status-busy'}">
          ${status['emoji'] != null ? '<span>${_esc(status['emoji'] as String)}</span>' : ''}
          <span>${_esc(status['text'] as String)}</span>
        </div>
      ''' : ''}

      <div class="sidebar-divider"></div>

      <div class="sidebar-meta">
        ${locationStr != null ? '<div class="sidebar-meta-item"><span class="meta-icon">📍</span><span>${_esc(locationStr)}</span></div>' : ''}
      </div>

      ${links.isNotEmpty ? '''
        <div class="sidebar-divider"></div>
        <div class="sidebar-links">
          <div class="sidebar-links-title">Links</div>
          ${links.map((l) => '<a class="sidebar-link" href="${_esc(_linkUrl(l))}" target="_blank"><span class="meta-icon">${_linkIcon(l['type'] as String? ?? '')}</span><span>${_esc(_linkLabel(l))}</span></a>').join('')}
        </div>
      ''' : ''}

      ${trust != null ? '''
        <div class="trust-badge $trustClass">
          <div class="trust-score-label">Trust Score</div>
          <div class="trust-score-value">${trustScore.round()}</div>
          <div class="trust-bar"><div class="trust-bar-fill" style="width: ${trustScore.clamp(0, 100)}%"></div></div>
          <div class="trust-meta">${breadcrumbs} breadcrumbs${since != null ? ' · since ${_esc(since)}' : ''}</div>
        </div>
      ''' : ''}
    </aside>

    <!-- MAIN CONTENT -->
    <main class="content-area">

      ${hasBlocks ? '''
        <!-- COMPOSABLE BLOCKS -->
        ${GSiteBlockRenderer.renderSections(sections)}
      ''' : '''
        <!-- STANDARD SECTIONS -->
        ${bio != null && bio.isNotEmpty ? '''
          <section class="section">
            <h1 class="section-title">About</h1>
            <div class="section-content">${_formatBio(bio)}</div>
          </section>
        ''' : '<section class="section"><h1 class="section-title" style="border-bottom:none;">$name</h1></section>'}

        ${skills.isNotEmpty ? '''
          <section class="section">
            <h2 class="section-title">Skills</h2>
            <div class="tag-list">${skills.map((s) => '<span class="tag">${_esc(s)}</span>').join('')}</div>
          </section>
        ''' : ''}

        ${interests.isNotEmpty ? '''
          <section class="section">
            <h2 class="section-title">Interests</h2>
            <div class="tag-list">${interests.map((i) => '<span class="tag">${_esc(i)}</span>').join('')}</div>
          </section>
        ''' : ''}

        ${verifications.isNotEmpty ? '''
          <section class="section">
            <h2 class="section-title">Verifications</h2>
            <div class="verifications-list">
              ${verifications.map((v) => '''
                <div class="verification-item">
                  <div class="verification-check">✓</div>
                  <div class="verification-detail">
                    <div class="verification-type">${_esc(v['type'] as String? ?? '')}</div>
                    <div class="verification-provider">${_esc(v['value'] as String? ?? '')} · ${_esc(v['provider'] as String? ?? '')}</div>
                  </div>
                </div>
              ''').join('')}
            </div>
          </section>
        ''' : ''}

        ${facets.where((f) => f['public'] != false).isNotEmpty ? '''
          <section class="section">
            <h2 class="section-title">Facets</h2>
            <div class="facets-grid">
              ${facets.where((f) => f['public'] != false).map((f) => '''
                <div class="facet-card">
                  <span class="facet-icon">${_facetIcon(f['id'] as String? ?? '')}</span>
                  <div>
                    <div class="facet-name">${_esc(f['name'] as String? ?? '')}</div>
                    <div class="facet-id">${_esc(f['id'] as String? ?? '')}</div>
                  </div>
                </div>
              ''').join('')}
            </div>
          </section>
        ''' : ''}

        ${_renderActions(data)}
      '''}

      ${publicKey != null ? '''
        <div class="pk-section">
          <span class="pk-label">Ed25519 Public Key</span>
          ${_esc(publicKey)}
        </div>
      ''' : ''}

      <footer class="page-footer">
        <span class="gns-wordmark">GNS</span> · Identity rendered from the
        <a href="https://gnamesystem.netlify.app" target="_blank">Geospatial Naming System</a><br>
        <span style="font-size:0.72rem;">HUMANS PREVAIL · Identity = Public Key</span>
      </footer>

    </main>
  </div>
</body>
</html>''';
  }

  // ============================================================
  // BUSINESS PAGE (with theme + blocks support)
  // ============================================================

  static String _renderBusinessPage(
      Map<String, dynamic> data, String handle, String? themeCSS) {
    final name = _esc(data['name'] as String? ?? handle);
    final tagline = data['tagline'] as String?;
    final bio = data['bio'] as String?;
    final avatarUrl = data['avatar']?['url'] as String?;
    final coverUrl = data['cover']?['url'] as String?;
    final category = data['category'] as String? ?? data['orgType'] as String? ?? '';
    final rating = data['rating'] as num?;
    final reviewCount = data['reviewCount'] as int?;
    final priceLevel = data['priceLevel'] as int?;
    final features = (data['features'] as List<dynamic>?)?.cast<String>() ?? [];
    final trust = data['trust'] as Map<String, dynamic>?;
    final location = data['location'] as Map<String, dynamic>?;
    final links = (data['links'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final verified = data['verified'] as bool? ?? false;
    final phone = data['phone'] as String?;
    final email = data['email'] as String?;
    final locationStr = _formatLocation(location);
    final trustScore = (trust?['score'] as num?)?.toDouble() ?? 0;
    final trustClass = _trustClass(trustScore);

    // Composable blocks
    final sections = (data['sections'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final hasBlocks = sections.isNotEmpty;

    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$name — @$handle</title>
  ${themeCSS ?? _defaultThemeCSS()}
  ${_baseCSSRules()}
</head>
<body>
  <div class="page-full">

    ${coverUrl != null ? '''
      <div class="cover-banner" style="background-image: url('${_esc(coverUrl)}')">
        <div class="cover-overlay"><div style="font-size:0.8rem; opacity:0.85;">${_esc(category)}</div></div>
      </div>
    ''' : ''}

    <div style="text-align:center; padding:2rem 0 1.5rem;">
      <div class="avatar-container" style="margin:${coverUrl != null ? '-60px' : '0'} auto 1rem; border:4px solid var(--color-surface); box-shadow:var(--shadow-md); position:relative; z-index:1;">
        ${avatarUrl != null && avatarUrl.isNotEmpty
          ? '<img src="${_esc(avatarUrl)}" alt="$name">'
          : '<span class="avatar-initial">${name.isNotEmpty ? _esc(name[0].toUpperCase()) : "?"}</span>'}
      </div>
      <h1 style="font-family:var(--font-display); font-size:1.8rem; margin-bottom:0.25rem;">
        $name ${verified ? '<span class="verified-badge">✓ Verified</span>' : ''}
      </h1>
      <div style="font-family:var(--font-mono); color:var(--color-accent); font-size:0.9rem;">@${_esc(handle)}</div>
      ${tagline != null ? '<p style="color:var(--color-text-secondary); margin-top:0.5rem;">${_esc(tagline)}</p>' : ''}
      ${rating != null ? '<div class="rating" style="justify-content:center; margin-top:0.75rem;"><span class="stars">${'★' * rating.floor()}${'☆' * (5 - rating.floor())}</span><span class="rating-value">${rating.toStringAsFixed(1)}</span>${reviewCount != null ? '<span class="rating-count">($reviewCount)</span>' : ''}</div>' : ''}
      ${priceLevel != null ? '<div style="color:var(--color-text-muted); margin-top:0.25rem;">${'\$' * priceLevel}</div>' : ''}
      <div class="actions-bar" style="justify-content:center; margin-top:1rem;">${_renderActionsRaw(data)}</div>
    </div>

    ${hasBlocks ? '''
      <div style="max-width: 780px; margin: 0 auto;">
        ${GSiteBlockRenderer.renderSections(sections)}
      </div>
    ''' : '''
      <div class="content-grid">
        <div class="content-main">
          ${bio != null ? '<section class="section"><h2 class="section-title">About</h2><div class="section-content">${_formatBio(bio)}</div></section>' : ''}
          ${features.isNotEmpty ? '<section class="section"><h2 class="section-title">Features</h2><div class="features-list">${features.map((f) => '<span class="feature-chip">${_esc(f)}</span>').join('')}</div></section>' : ''}
        </div>
        <aside class="content-sidebar-right">
          <div class="info-card">
            <div class="info-card-title">Contact</div>
            ${locationStr != null ? '<div class="info-card-row"><span class="meta-icon">📍</span><span>${_esc(locationStr)}</span></div>' : ''}
            ${phone != null ? '<div class="info-card-row"><span class="meta-icon">📞</span><span>${_esc(phone)}</span></div>' : ''}
            ${email != null ? '<div class="info-card-row"><span class="meta-icon">✉</span><span>${_esc(email)}</span></div>' : ''}
            ${links.map((l) => '<div class="info-card-row"><span class="meta-icon">${_linkIcon(l['type'] as String? ?? '')}</span><span>${_esc(_linkLabel(l))}</span></div>').join('')}
          </div>
          ${trust != null ? '<div class="info-card"><div class="trust-badge $trustClass" style="margin:0;"><div class="trust-score-label">Trust Score</div><div class="trust-score-value">${trustScore.round()}</div><div class="trust-bar"><div class="trust-bar-fill" style="width:${trustScore.clamp(0, 100)}%"></div></div><div class="trust-meta">${trust['breadcrumbs'] ?? 0} breadcrumbs</div></div></div>' : ''}
        </aside>
      </div>
    '''}

    <footer class="page-footer">
      <span class="gns-wordmark">GNS</span> · Rendered from the <a href="https://gnamesystem.netlify.app" target="_blank">Geospatial Naming System</a>
    </footer>
  </div>
</body>
</html>''';
  }

  // ============================================================
  // DEFAULT THEME CSS (Academic preset)
  // ============================================================

  static String _defaultThemeCSS() {
    return ThemeEngine.generateCSS(PresetThemes.academic);
  }

  // ============================================================
  // BASE CSS RULES (structural, not theme-dependent)
  // ============================================================

  static String _baseCSSRules() {
    return '''<style>
  *,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
  html{font-size:16px;scroll-behavior:smooth}
  body{font-family:var(--font-body);color:var(--color-text);background:var(--color-bg);line-height:1.68;-webkit-font-smoothing:antialiased}
  a{color:var(--color-accent);text-decoration:none;transition:color 0.2s}
  a:hover{color:var(--color-accent-hover);text-decoration:underline}
  img{max-width:100%;height:auto;display:block}

  .page-wrapper{display:flex;min-height:100vh}
  .sidebar{width:var(--sidebar-width);flex-shrink:0;background:var(--color-surface);border-right:1px solid var(--color-border);padding:2.5rem 1.75rem;position:sticky;top:0;height:100vh;overflow-y:auto;display:flex;flex-direction:column;align-items:center;text-align:center}
  .content-area{flex:1;max-width:var(--content-max);padding:3rem 3rem 4rem;margin:0 auto}

  .avatar-container{width:155px;height:155px;border-radius:var(--avatar-radius, 50%);overflow:hidden;border:3px solid var(--color-border-light);margin-bottom:1.25rem;background:var(--color-accent-light);display:flex;align-items:center;justify-content:center;box-shadow:var(--shadow-sm)}
  .avatar-container img{width:100%;height:100%;object-fit:cover}
  .avatar-initial{font-family:var(--font-display);font-size:3.8rem;color:var(--color-accent);font-weight:700}

  .sidebar-name{font-family:var(--font-display);font-size:1.45rem;font-weight:700;color:var(--color-text);margin-bottom:0.2rem;line-height:1.3}
  .sidebar-handle{font-family:var(--font-mono);font-size:0.82rem;color:var(--color-accent);margin-bottom:0.6rem}
  .sidebar-tagline{font-size:0.88rem;color:var(--color-text-secondary);margin-bottom:1rem;line-height:1.55;font-style:italic}
  .sidebar-status{display:inline-flex;align-items:center;gap:0.35rem;font-size:0.78rem;padding:0.3rem 0.75rem;border-radius:var(--radius-full);margin-bottom:1rem;font-weight:500}
  .status-available{background:color-mix(in srgb, var(--color-success) 12%, transparent);color:var(--color-success);border:1px solid color-mix(in srgb, var(--color-success) 25%, transparent)}
  .status-busy{background:color-mix(in srgb, var(--color-warning) 12%, transparent);color:var(--color-warning);border:1px solid color-mix(in srgb, var(--color-warning) 25%, transparent)}
  .sidebar-divider{width:100%;height:1px;background:var(--color-border-light);margin:0.75rem 0}
  .verified-badge{display:inline-flex;align-items:center;gap:0.25rem;font-size:0.72rem;font-weight:600;color:var(--color-accent);background:var(--color-accent-light);padding:0.2rem 0.55rem;border-radius:var(--radius-full);margin-bottom:0.5rem}

  .sidebar-meta{width:100%;text-align:left;font-size:0.84rem;color:var(--color-text-secondary)}
  .sidebar-meta-item{display:flex;align-items:flex-start;gap:0.55rem;padding:0.35rem 0;line-height:1.45}
  .meta-icon{flex-shrink:0;width:16px;text-align:center;color:var(--color-text-muted);font-size:0.85rem}

  .sidebar-links{width:100%;text-align:left;font-size:0.84rem}
  .sidebar-links-title{font-size:0.68rem;text-transform:uppercase;letter-spacing:0.1em;color:var(--color-text-muted);font-weight:600;margin-bottom:0.4rem}
  .sidebar-link{display:flex;align-items:center;gap:0.5rem;padding:0.32rem 0;color:var(--color-text-secondary);transition:color 0.2s}
  .sidebar-link:hover{color:var(--color-accent);text-decoration:none}

  .trust-badge{width:100%;padding:0.85rem;border-radius:var(--card-radius, 8px);margin-top:0.75rem;text-align:center}
  .trust-score-label{font-size:0.68rem;text-transform:uppercase;letter-spacing:0.1em;font-weight:600;margin-bottom:0.2rem}
  .trust-score-value{font-family:var(--font-mono);font-size:1.6rem;font-weight:700;line-height:1.2}
  .trust-bar{width:100%;height:4px;border-radius:2px;background:rgba(0,0,0,0.08);margin:0.5rem 0;overflow:hidden}
  .trust-bar-fill{height:100%;border-radius:2px;transition:width 0.8s cubic-bezier(0.22,1,0.36,1)}
  .trust-meta{font-size:0.73rem;opacity:0.75}
  .trust-high{background:color-mix(in srgb, var(--color-trust-high) 10%, var(--color-surface));color:var(--color-trust-high)}.trust-high .trust-bar-fill{background:var(--color-trust-high)}
  .trust-med{background:color-mix(in srgb, var(--color-trust-med) 10%, var(--color-surface));color:var(--color-trust-med)}.trust-med .trust-bar-fill{background:var(--color-trust-med)}
  .trust-low{background:color-mix(in srgb, var(--color-trust-low) 10%, var(--color-surface));color:var(--color-trust-low)}.trust-low .trust-bar-fill{background:var(--color-trust-low)}
  .trust-new{background:color-mix(in srgb, var(--color-trust-new) 10%, var(--color-surface));color:var(--color-trust-new)}.trust-new .trust-bar-fill{background:var(--color-trust-new)}

  .section{margin-bottom:var(--section-margin, 2.25rem)}
  .section-title{font-family:var(--font-display);font-size:1.5rem;font-weight:700;color:var(--color-text);margin-bottom:0.65rem;padding-bottom:0.45rem;border-bottom:var(--section-border, 2px solid var(--color-accent-light))}
  .section-content{font-size:0.95rem;line-height:1.78;color:var(--color-text-secondary)}
  .section-content p{margin-bottom:0.85rem}.section-content p:last-child{margin-bottom:0}

  .tag-list{display:flex;flex-wrap:wrap;gap:0.45rem;margin-top:0.35rem}
  .tag{display:inline-block;padding:0.22rem 0.65rem;background:var(--color-accent-light);color:var(--color-accent);border-radius:var(--radius-full);font-size:0.8rem;font-weight:500}

  .facets-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(210px,1fr));gap:0.7rem;margin-top:0.5rem}
  .facet-card{padding:0.75rem 1rem;background:var(--color-surface);border:1px solid var(--color-border);border-radius:var(--card-radius, 8px);display:flex;align-items:center;gap:0.6rem}
  .facet-icon{font-size:1.15rem}
  .facet-name{font-size:0.85rem;font-weight:600;color:var(--color-text)}
  .facet-id{font-family:var(--font-mono);font-size:0.68rem;color:var(--color-text-muted);margin-top:0.1rem}

  .verifications-list{display:flex;flex-direction:column;gap:0.5rem;margin-top:0.5rem}
  .verification-item{display:flex;align-items:center;gap:0.6rem;padding:0.55rem 0.85rem;background:var(--color-surface);border:1px solid var(--color-border);border-radius:var(--card-radius, 8px);font-size:0.85rem}
  .verification-check{width:20px;height:20px;border-radius:50%;background:var(--color-success);color:#fff;display:flex;align-items:center;justify-content:center;font-size:0.65rem;font-weight:700;flex-shrink:0}
  .verification-type{font-weight:600;color:var(--color-text);font-size:0.82rem}
  .verification-provider{font-size:0.72rem;color:var(--color-text-muted)}

  .actions-bar{display:flex;gap:0.5rem;flex-wrap:wrap;margin:1rem 0}
  .action-btn{display:inline-flex;align-items:center;gap:0.4rem;padding:0.55rem 1.1rem;border-radius:var(--btn-radius, 8px);font-size:0.85rem;font-weight:600;border:none;text-decoration:none;font-family:var(--font-body);transition:opacity 0.15s}
  .action-btn:hover{opacity:0.88;text-decoration:none}
  .action-primary{background:var(--color-accent);color:var(--color-surface)}
  .action-secondary{background:var(--color-surface);color:var(--color-accent);border:1px solid var(--color-border)}

  .pk-section{margin-top:1.5rem;padding:1rem 1.25rem;background:var(--color-surface-variant, #f7f8fa);border:1px solid var(--color-border-light);border-radius:var(--card-radius, 8px);font-family:var(--font-mono);font-size:0.72rem;color:var(--color-text-muted);word-break:break-all;line-height:1.6}
  .pk-label{font-family:var(--font-body);font-size:0.7rem;text-transform:uppercase;letter-spacing:0.08em;font-weight:600;color:var(--color-text-muted);margin-bottom:0.35rem;display:block}

  .page-footer{padding:2rem 0;margin-top:1.5rem;border-top:1px solid var(--color-border-light);text-align:center;font-size:0.78rem;color:var(--color-text-muted);line-height:1.6}
  .page-footer a{color:var(--color-text-muted)}.page-footer a:hover{color:var(--color-accent)}
  .gns-wordmark{font-family:var(--font-mono);font-weight:600;font-size:0.82rem;letter-spacing:0.04em;color:var(--color-text-secondary)}

  /* Business layout */
  .page-full{max-width:920px;margin:0 auto;padding:0 1.5rem 3rem}
  .cover-banner{width:100%;height:200px;background-size:cover;background-position:center;border-radius:0 0 var(--card-radius, 12px) var(--card-radius, 12px);position:relative}
  .cover-overlay{position:absolute;bottom:0;left:0;right:0;padding:1.5rem 2rem;background:linear-gradient(transparent,rgba(0,0,0,0.5));border-radius:0 0 var(--card-radius, 12px) var(--card-radius, 12px);color:#fff}
  .content-grid{display:grid;grid-template-columns:1fr 300px;gap:2rem;margin-top:1.5rem}
  .content-main{min-width:0}
  .content-sidebar-right{position:sticky;top:1.5rem;align-self:start}
  .info-card{background:var(--color-surface);border:1px solid var(--color-border);border-radius:var(--card-radius, 12px);padding:1.25rem;margin-bottom:1rem;box-shadow:var(--shadow-sm)}
  .info-card-title{font-size:0.68rem;text-transform:uppercase;letter-spacing:0.08em;color:var(--color-text-muted);font-weight:600;margin-bottom:0.75rem}
  .info-card-row{display:flex;align-items:flex-start;gap:0.5rem;padding:0.35rem 0;font-size:0.85rem;color:var(--color-text-secondary)}

  .rating{display:flex;align-items:center;gap:0.4rem;margin-bottom:0.5rem}
  .stars{color:#f5b041;letter-spacing:2px}.rating-value{font-weight:700;font-size:1.1rem}.rating-count{color:var(--color-text-muted);font-size:0.85rem}
  .features-list{display:flex;flex-wrap:wrap;gap:0.5rem}
  .feature-chip{display:inline-flex;align-items:center;gap:0.3rem;padding:0.3rem 0.65rem;background:var(--color-surface);border:1px solid var(--color-border);border-radius:var(--radius-full);font-size:0.8rem;color:var(--color-text-secondary)}
  .feature-chip::before{content:'✓';color:var(--color-success);font-weight:700}

  @media(max-width:860px){
    .page-wrapper{flex-direction:column}
    .sidebar{width:100%;height:auto;position:static;padding:1.75rem 1.5rem 1.25rem;border-right:none;border-bottom:1px solid var(--color-border)}
    .avatar-container{width:90px;height:90px}
    .content-area{padding:1.5rem 1.25rem}
    .section-title{font-size:1.3rem}
    .content-grid{grid-template-columns:1fr}
    .content-sidebar-right{position:static}
  }
</style>''';
  }

  // ============================================================
  // HELPERS (unchanged from v1)
  // ============================================================

  static String _esc(String? s) {
    if (s == null) return '';
    return s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#39;');
  }

  static String _formatBio(String bio) {
    return bio.split(RegExp(r'\n\n+')).map((p) => '<p>${_esc(p.trim()).replaceAll('\n', '<br>')}</p>').join('');
  }

  static String? _formatLocation(Map<String, dynamic>? loc) {
    if (loc == null) return null;
    final parts = <String>[];
    if (loc['city'] != null) parts.add(loc['city'] as String);
    if (loc['country'] != null) parts.add(loc['country'] as String);
    return parts.isNotEmpty ? parts.join(', ') : null;
  }

  static String _trustClass(double score) {
    if (score >= 76) return 'trust-high';
    if (score >= 51) return 'trust-med';
    if (score >= 26) return 'trust-low';
    return 'trust-new';
  }

  static String _linkUrl(Map<String, dynamic> link) {
    if (link['url'] != null) return link['url'] as String;
    final h = link['handle'] as String?;
    if (h == null) return '#';
    switch (link['type']) {
      case 'twitter': case 'x': return 'https://x.com/$h';
      case 'github': return 'https://github.com/$h';
      case 'linkedin': return 'https://linkedin.com/in/$h';
      default: return '#';
    }
  }

  static String _linkIcon(String type) {
    const icons = {'website': '🌐', 'github': '💻', 'linkedin': '💼', 'twitter': '𝕏', 'x': '𝕏', 'email': '✉', 'medium': '✍', 'youtube': '▶', 'instagram': '📷'};
    return icons[type] ?? '🔗';
  }

  static String _linkLabel(Map<String, dynamic> link) {
    if (link['handle'] != null) return '@${link['handle']}';
    final url = link['url'] as String?;
    if (url != null) { try { return Uri.parse(url).host.replaceFirst('www.', ''); } catch (_) { return url; } }
    return link['type'] as String? ?? 'Link';
  }

  static String _facetIcon(String id) {
    if (id.startsWith('dix@')) return '📝';
    if (id.startsWith('home@')) return '🏠';
    if (id.startsWith('pay@')) return '💳';
    if (id.startsWith('email@')) return '✉';
    if (id.startsWith('work@')) return '💼';
    if (id.startsWith('personal@')) return '👤';
    return '📎';
  }

  static String _renderActions(Map<String, dynamic> data) {
    final actions = data['actions'] as Map<String, dynamic>?;
    if (actions == null) return '';
    final btns = <String>[];
    if (actions['message'] == true) btns.add('<a class="action-btn action-primary" href="#">✉ Message</a>');
    if (actions['payment'] == true) btns.add('<a class="action-btn action-secondary" href="#">💳 Pay via GNS</a>');
    if (actions['follow'] == true) btns.add('<a class="action-btn action-secondary" href="#">＋ Follow</a>');
    if (btns.isEmpty) return '';
    return '<section class="section"><div class="actions-bar">${btns.join('')}</div></section>';
  }

  static String _renderActionsRaw(Map<String, dynamic> data) {
    final actions = data['actions'] as Map<String, dynamic>?;
    if (actions == null) return '';
    final btns = <String>[];
    if (actions['message'] == true) btns.add('<a class="action-btn action-primary" href="#">✉ Message</a>');
    if (actions['payment'] == true) btns.add('<a class="action-btn action-secondary" href="#">💳 Pay</a>');
    if (actions['follow'] == true) btns.add('<a class="action-btn action-secondary" href="#">＋ Follow</a>');
    return btns.join('');
  }
}
