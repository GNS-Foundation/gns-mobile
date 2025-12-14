import Link from 'next/link';

export default function NotFound() {
  return (
    <div className="min-h-[60vh] flex items-center justify-center px-4">
      <div className="text-center max-w-md">
        {/* 404 Animation */}
        <div className="text-8xl font-bold text-gns-primary/20 mb-4">
          404
        </div>
        
        {/* Icon */}
        <div className="text-6xl mb-6 animate-float">
          🍞
        </div>

        {/* Message */}
        <h1 className="text-2xl font-bold text-[var(--text-primary)] mb-3">
          Identity Not Found
        </h1>
        <p className="text-[var(--text-secondary)] mb-8">
          This @handle or entity doesn't exist yet. Maybe you'd like to claim it?
        </p>

        {/* Actions */}
        <div className="flex flex-col sm:flex-row gap-3 justify-center">
          <Link href="/" className="gns-button-primary">
            Go Home
          </Link>
          <Link href="/search" className="gns-button-outline">
            Search GNS
          </Link>
        </div>

        {/* Help text */}
        <p className="mt-8 text-sm text-[var(--text-muted)]">
          Want this @handle? Download{' '}
          <a 
            href="https://apps.apple.com/app/globe-crumbs" 
            className="text-gns-primary hover:underline"
          >
            Globe Crumbs
          </a>
          {' '}and start collecting breadcrumbs.
        </p>
      </div>
    </div>
  );
}
