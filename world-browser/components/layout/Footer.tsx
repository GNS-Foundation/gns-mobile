import Link from 'next/link';

export function Footer() {
  return (
    <footer className="border-t border-[var(--border)] bg-[var(--surface)]">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        <div className="grid grid-cols-1 md:grid-cols-4 gap-8">
          {/* Brand */}
          <div className="md:col-span-1">
            <Link href="/" className="flex items-center gap-2 mb-4">
              <span className="text-2xl">🌐</span>
              <span className="font-bold text-lg">GNS</span>
            </Link>
            <p className="text-[var(--text-secondary)] text-sm">
              Browse identities, not websites. Connect by handle, not by phone number.
            </p>
          </div>

          {/* Product */}
          <div>
            <h4 className="font-semibold mb-4 text-[var(--text-primary)]">Product</h4>
            <ul className="space-y-2">
              <li>
                <a 
                  href="https://apps.apple.com/app/globe-crumbs" 
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[var(--text-secondary)] hover:text-gns-primary transition-colors text-sm"
                >
                  Globe Crumbs App
                </a>
              </li>
              <li>
                <Link 
                  href="/search"
                  className="text-[var(--text-secondary)] hover:text-gns-primary transition-colors text-sm"
                >
                  Explore Identities
                </Link>
              </li>
              <li>
                <Link 
                  href="/entity"
                  className="text-[var(--text-secondary)] hover:text-gns-primary transition-colors text-sm"
                >
                  Places & Businesses
                </Link>
              </li>
            </ul>
          </div>

          {/* Developers */}
          <div>
            <h4 className="font-semibold mb-4 text-[var(--text-primary)]">Developers</h4>
            <ul className="space-y-2">
              <li>
                <a 
                  href="https://docs.gns.xyz" 
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[var(--text-secondary)] hover:text-gns-primary transition-colors text-sm"
                >
                  Documentation
                </a>
              </li>
              <li>
                <a 
                  href="https://github.com/gns-protocol" 
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[var(--text-secondary)] hover:text-gns-primary transition-colors text-sm"
                >
                  GitHub
                </a>
              </li>
              <li>
                <a 
                  href="https://api.gns.xyz" 
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[var(--text-secondary)] hover:text-gns-primary transition-colors text-sm"
                >
                  API Reference
                </a>
              </li>
            </ul>
          </div>

          {/* Company */}
          <div>
            <h4 className="font-semibold mb-4 text-[var(--text-primary)]">Company</h4>
            <ul className="space-y-2">
              <li>
                <a 
                  href="https://gns.xyz/about" 
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[var(--text-secondary)] hover:text-gns-primary transition-colors text-sm"
                >
                  About GNS
                </a>
              </li>
              <li>
                <a 
                  href="https://gns.xyz/privacy" 
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[var(--text-secondary)] hover:text-gns-primary transition-colors text-sm"
                >
                  Privacy Policy
                </a>
              </li>
              <li>
                <a 
                  href="https://gns.xyz/terms" 
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[var(--text-secondary)] hover:text-gns-primary transition-colors text-sm"
                >
                  Terms of Service
                </a>
              </li>
            </ul>
          </div>
        </div>

        {/* Bottom */}
        <div className="mt-12 pt-8 border-t border-[var(--border)] flex flex-col sm:flex-row justify-between items-center gap-4">
          <p className="text-[var(--text-muted)] text-sm">
            © {new Date().getFullYear()} GNS Protocol. All rights reserved.
          </p>
          <p className="text-[var(--text-muted)] text-sm">
            Identity through Presence 🍞
          </p>
        </div>
      </div>
    </footer>
  );
}
