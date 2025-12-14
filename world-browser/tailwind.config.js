/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './app/**/*.{js,ts,jsx,tsx,mdx}',
    './components/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        // GNS Brand Colors (matching Globe Crumbs)
        gns: {
          primary: '#6366F1',      // Indigo - main brand color
          secondary: '#10B981',    // Emerald - success/verified
          accent: '#F59E0B',       // Amber - highlights
          warning: '#F59E0B',      // Amber
          error: '#EF4444',        // Red
          
          // Backgrounds
          bg: {
            light: '#FFFFFF',
            dark: '#0F172A',
          },
          
          // Surfaces
          surface: {
            light: '#F8FAFC',
            dark: '#1E293B',
          },
          
          // Borders
          border: {
            light: '#E2E8F0',
            dark: '#334155',
          },
          
          // Text
          text: {
            primary: {
              light: '#0F172A',
              dark: '#F8FAFC',
            },
            secondary: {
              light: '#475569',
              dark: '#94A3B8',
            },
            muted: {
              light: '#94A3B8',
              dark: '#64748B',
            },
          },
        },
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
        mono: ['JetBrains Mono', 'monospace'],
      },
      animation: {
        'pulse-slow': 'pulse 3s cubic-bezier(0.4, 0, 0.6, 1) infinite',
        'fade-in': 'fadeIn 0.5s ease-out',
        'slide-up': 'slideUp 0.5s ease-out',
      },
      keyframes: {
        fadeIn: {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
        slideUp: {
          '0%': { opacity: '0', transform: 'translateY(20px)' },
          '100%': { opacity: '1', transform: 'translateY(0)' },
        },
      },
    },
  },
  plugins: [],
};
