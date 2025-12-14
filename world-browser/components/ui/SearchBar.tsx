'use client';

import { useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';

interface SearchBarProps {
  size?: 'sm' | 'md' | 'lg';
  placeholder?: string;
  autoFocus?: boolean;
}

export function SearchBar({ 
  size = 'md', 
  placeholder = 'Search @handle or place...',
  autoFocus = false,
}: SearchBarProps) {
  const router = useRouter();
  const [query, setQuery] = useState('');
  const [isFocused, setIsFocused] = useState(false);

  const sizeClasses = {
    sm: 'py-2 px-3 text-sm',
    md: 'py-3 px-4',
    lg: 'py-4 px-6 text-lg',
  };

  const handleSubmit = useCallback((e: React.FormEvent) => {
    e.preventDefault();
    const trimmedQuery = query.trim();
    
    if (!trimmedQuery) return;

    // If starts with @, go directly to profile page
    if (trimmedQuery.startsWith('@')) {
      const handle = trimmedQuery.slice(1);
      router.push(`/${handle}`);
    } else {
      // Otherwise, go to search results
      router.push(`/search?q=${encodeURIComponent(trimmedQuery)}`);
    }
  }, [query, router]);

  return (
    <form onSubmit={handleSubmit} className="relative w-full">
      <div className={`
        relative flex items-center
        ${isFocused ? 'ring-2 ring-gns-primary' : ''}
        rounded-xl transition-all duration-200
      `}>
        {/* Search Icon */}
        <div className="absolute left-4 pointer-events-none">
          <svg 
            className={`w-5 h-5 ${isFocused ? 'text-gns-primary' : 'text-[var(--text-muted)]'} transition-colors`}
            fill="none" 
            stroke="currentColor" 
            viewBox="0 0 24 24"
          >
            <path 
              strokeLinecap="round" 
              strokeLinejoin="round" 
              strokeWidth={2} 
              d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" 
            />
          </svg>
        </div>

        {/* Input */}
        <input
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onFocus={() => setIsFocused(true)}
          onBlur={() => setIsFocused(false)}
          placeholder={placeholder}
          autoFocus={autoFocus}
          className={`
            w-full pl-12 pr-4 ${sizeClasses[size]}
            bg-[var(--surface)] border border-[var(--border)]
            rounded-xl
            text-[var(--text-primary)] placeholder-[var(--text-muted)]
            focus:outline-none focus:border-transparent
            transition-all duration-200
          `}
        />

        {/* Submit Button (appears when there's input) */}
        {query.trim() && (
          <button
            type="submit"
            className="absolute right-2 p-2 rounded-lg bg-gns-primary text-white hover:bg-gns-primary/90 transition-colors"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M14 5l7 7m0 0l-7 7m7-7H3" />
            </svg>
          </button>
        )}
      </div>

      {/* Hint text */}
      {isFocused && (
        <div className="absolute left-0 right-0 mt-2 text-xs text-[var(--text-muted)]">
          Try <span className="text-gns-primary">@caterve</span> or search for places
        </div>
      )}
    </form>
  );
}
