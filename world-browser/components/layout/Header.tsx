'use client';

import Link from 'next/link';
import { useState } from 'react';
import { SearchBar } from '@/components/ui/SearchBar';

export function Header() {
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  return (
    <header className="sticky top-0 z-50 glass border-b border-[var(--border)]">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-16">
          {/* Logo */}
          <Link href="/" className="flex items-center gap-2 hover:opacity-80 transition-opacity">
            <span className="text-2xl">🌐</span>
            <span className="font-bold text-xl tracking-tight">
              <span className="text-gns-primary">GNS</span>
              <span className="text-[var(--text-secondary)] ml-1 hidden sm:inline">World Browser</span>
            </span>
          </Link>

          {/* Search Bar - Desktop */}
          <div className="hidden md:block flex-1 max-w-md mx-8">
            <SearchBar />
          </div>

          {/* Navigation */}
          <nav className="hidden md:flex items-center gap-6">
            <Link 
              href="/search" 
              className="text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-colors"
            >
              Explore
            </Link>
            <a 
              href="https://apps.apple.com/app/globe-crumbs" 
              target="_blank"
              rel="noopener noreferrer"
              className="gns-button-primary text-sm py-2"
            >
              Get the App
            </a>
          </nav>

          {/* Mobile menu button */}
          <button
            onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
            className="md:hidden p-2 rounded-lg hover:bg-[var(--surface)] transition-colors"
            aria-label="Toggle menu"
          >
            <svg
              className="w-6 h-6 text-[var(--text-primary)]"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              {mobileMenuOpen ? (
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              ) : (
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
              )}
            </svg>
          </button>
        </div>

        {/* Mobile menu */}
        {mobileMenuOpen && (
          <div className="md:hidden py-4 border-t border-[var(--border)]">
            <div className="mb-4">
              <SearchBar />
            </div>
            <nav className="flex flex-col gap-4">
              <Link 
                href="/search" 
                className="text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-colors"
                onClick={() => setMobileMenuOpen(false)}
              >
                Explore
              </Link>
              <a 
                href="https://apps.apple.com/app/globe-crumbs" 
                target="_blank"
                rel="noopener noreferrer"
                className="gns-button-primary text-center"
              >
                Get the App
              </a>
            </nav>
          </div>
        )}
      </div>
    </header>
  );
}
