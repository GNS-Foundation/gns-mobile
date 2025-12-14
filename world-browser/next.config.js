/** @type {import('next').NextConfig} */
const nextConfig = {
  // Enable React strict mode for better development experience
  reactStrictMode: true,
  
  // Image optimization settings
  images: {
    domains: [
      'localhost',
      'api.gns.xyz',
      'browser.gns.xyz',
      // Add Supabase storage if needed
    ],
    // Allow base64 images from profiles
    dangerouslyAllowSVG: true,
  },
  
  // Environment variables available to the browser
  env: {
    NEXT_PUBLIC_API_URL: process.env.NEXT_PUBLIC_API_URL || 'http://localhost:3001',
    NEXT_PUBLIC_APP_URL: process.env.NEXT_PUBLIC_APP_URL || 'http://localhost:3000',
  },
  
  // Redirect @handle URLs to /[handle] route
  async rewrites() {
    return [
      {
        source: '/@:handle',
        destination: '/:handle',
      },
    ];
  },
  
  // SEO-friendly trailing slashes
  trailingSlash: false,
};

module.exports = nextConfig;
