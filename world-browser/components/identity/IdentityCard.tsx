'use client';

import { GnsIdentity, getTrustLevel, getTrustEmoji, getTrustColor, getLinkIcon, truncateAddress, formatNumber } from '@/lib/types';
import { QRCodeSVG } from 'qrcode.react';
import { useState } from 'react';

interface IdentityCardProps {
  identity: GnsIdentity;
  size?: 'sm' | 'md' | 'lg';
  showQR?: boolean;
  showLinks?: boolean;
  showStats?: boolean;
}

export function IdentityCard({ 
  identity, 
  size = 'md',
  showQR = true,
  showLinks = true,
  showStats = true,
}: IdentityCardProps) {
  const [qrVisible, setQrVisible] = useState(false);
  
  const trustLevel = getTrustLevel(identity.trustScore);
  const trustEmoji = getTrustEmoji(identity.trustScore);
  const trustColor = getTrustColor(identity.trustScore);

  const sizeConfig = {
    sm: {
      card: 'p-4',
      avatar: 'w-16 h-16 text-2xl',
      name: 'text-lg',
      handle: 'text-sm',
    },
    md: {
      card: 'p-6',
      avatar: 'w-24 h-24 text-4xl',
      name: 'text-2xl',
      handle: 'text-base',
    },
    lg: {
      card: 'p-8',
      avatar: 'w-32 h-32 text-5xl',
      name: 'text-3xl',
      handle: 'text-lg',
    },
  };

  const config = sizeConfig[size];
  const profileUrl = `https://browser.gns.xyz/@${identity.handle}`;
  const deepLink = `globecrumbs://profile/${identity.publicKey}`;

  return (
    <div className={`gns-card ${config.card} animate-fade-in`}>
      {/* Top Section: Avatar + Basic Info */}
      <div className="flex flex-col sm:flex-row items-center sm:items-start gap-6">
        {/* Avatar */}
        <div className="relative">
          <div className={`
            ${config.avatar} rounded-full 
            bg-gradient-to-br from-gns-primary to-gns-secondary
            flex items-center justify-center
            ring-4 ring-[var(--surface)]
            shadow-lg
          `}>
            {identity.avatarUrl ? (
              <img 
                src={identity.avatarUrl} 
                alt={identity.displayName || identity.handle || 'Avatar'}
                className="w-full h-full rounded-full object-cover"
              />
            ) : (
              <span className="text-white">
                {(identity.displayName || identity.handle || '?')[0].toUpperCase()}
              </span>
            )}
          </div>
          
          {/* Verified badge */}
          {identity.isVerified && (
            <div className="absolute -bottom-1 -right-1 bg-gns-secondary text-white rounded-full p-1.5 shadow-lg">
              <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
              </svg>
            </div>
          )}
        </div>

        {/* Info */}
        <div className="flex-1 text-center sm:text-left">
          {/* Name */}
          {identity.displayName && (
            <h1 className={`${config.name} font-bold text-[var(--text-primary)]`}>
              {identity.displayName}
            </h1>
          )}
          
          {/* Handle */}
          {identity.handle && (
            <p className={`${config.handle} text-gns-primary font-medium`}>
              @{identity.handle}
            </p>
          )}

          {/* Trust Badge */}
          <div className="mt-2 flex items-center justify-center sm:justify-start gap-2">
            <span className={`trust-badge ${
              identity.trustScore >= 70 ? 'trust-badge-high' :
              identity.trustScore >= 40 ? 'trust-badge-medium' :
              'trust-badge-low'
            }`}>
              {trustEmoji} {identity.trustScore}% trust
            </span>
            <span className="text-[var(--text-muted)] text-sm capitalize">
              {trustLevel}
            </span>
          </div>

          {/* Bio */}
          {identity.bio && (
            <p className="mt-3 text-[var(--text-secondary)] max-w-md">
              {identity.bio}
            </p>
          )}

          {/* Location */}
          {identity.lastLocationRegion && (
            <p className="mt-2 text-sm text-[var(--text-muted)] flex items-center justify-center sm:justify-start gap-1">
              <span>📍</span>
              <span>{identity.lastLocationRegion}</span>
            </p>
          )}
        </div>
      </div>

      {/* Stats Section */}
      {showStats && (
        <div className="mt-6 grid grid-cols-3 gap-4">
          <div className="stat-box">
            <span className="text-2xl font-bold text-gns-primary">
              {formatNumber(identity.breadcrumbCount)}
            </span>
            <span className="text-xs text-[var(--text-muted)] mt-1">🍞 Breadcrumbs</span>
          </div>
          <div className="stat-box">
            <span className="text-2xl font-bold text-gns-secondary">
              {identity.trustScore}%
            </span>
            <span className="text-xs text-[var(--text-muted)] mt-1">⭐ Trust Score</span>
          </div>
          <div className="stat-box">
            <span className="text-2xl font-bold text-gns-accent">
              {identity.daysSinceCreation}
            </span>
            <span className="text-xs text-[var(--text-muted)] mt-1">📅 Days Active</span>
          </div>
        </div>
      )}

      {/* Links Section */}
      {showLinks && identity.links && identity.links.length > 0 && (
        <div className="mt-6">
          <h3 className="text-sm font-medium text-[var(--text-muted)] mb-3">Links</h3>
          <div className="flex flex-wrap gap-2">
            {identity.links.map((link, index) => (
              <a
                key={index}
                href={link.url}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-2 px-3 py-2 rounded-lg bg-[var(--surface)] border border-[var(--border)] hover:border-gns-primary transition-colors"
              >
                <span>{getLinkIcon(link.type)}</span>
                <span className="text-sm text-[var(--text-secondary)]">
                  {link.label || link.type}
                </span>
              </a>
            ))}
          </div>
        </div>
      )}

      {/* Public Key */}
      <div className="mt-6 pt-4 border-t border-[var(--border)]">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-xs text-[var(--text-muted)] mb-1">Public Key</p>
            <code className="text-sm font-mono text-[var(--text-secondary)]">
              {truncateAddress(identity.publicKey, 8)}
            </code>
          </div>
          
          {/* QR Toggle */}
          {showQR && (
            <button
              onClick={() => setQrVisible(!qrVisible)}
              className="p-2 rounded-lg hover:bg-[var(--surface)] transition-colors"
              title="Show QR Code"
            >
              <svg className="w-6 h-6 text-[var(--text-muted)]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v1m6 11h2m-6 0h-2v4m0-11v3m0 0h.01M12 12h4.01M16 20h4M4 12h4m12 0h.01M5 8h2a1 1 0 001-1V5a1 1 0 00-1-1H5a1 1 0 00-1 1v2a1 1 0 001 1zm12 0h2a1 1 0 001-1V5a1 1 0 00-1-1h-2a1 1 0 00-1 1v2a1 1 0 001 1zM5 20h2a1 1 0 001-1v-2a1 1 0 00-1-1H5a1 1 0 00-1 1v2a1 1 0 001 1z" />
              </svg>
            </button>
          )}
        </div>
        
        {/* QR Code Panel */}
        {qrVisible && (
          <div className="mt-4 p-4 bg-white rounded-xl flex flex-col items-center gap-3 animate-slide-up">
            <QRCodeSVG 
              value={deepLink}
              size={160}
              level="M"
              includeMargin={true}
              fgColor="#6366F1"
            />
            <p className="text-xs text-gray-500 text-center">
              Scan with Globe Crumbs app to connect
            </p>
          </div>
        )}
      </div>

      {/* Action Buttons */}
      <div className="mt-6 flex flex-col sm:flex-row gap-3">
        <a
          href={deepLink}
          className="gns-button-primary flex-1 text-center flex items-center justify-center gap-2"
        >
          <span>📱</span>
          <span>Open in App</span>
        </a>
        <button
          onClick={() => {
            navigator.clipboard.writeText(profileUrl);
            // Could add a toast notification here
          }}
          className="gns-button-outline flex-1 flex items-center justify-center gap-2"
        >
          <span>🔗</span>
          <span>Copy Link</span>
        </button>
      </div>
    </div>
  );
}
