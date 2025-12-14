#!/bin/bash
# ===========================================
# GNS World Browser - Quick Setup
# ===========================================

echo "🌐 Setting up GNS World Browser..."

# Check if node is installed
if ! command -v node &> /dev/null; then
    echo "❌ Node.js is required. Please install Node.js 18+"
    exit 1
fi

echo "📦 Installing dependencies..."
npm install

echo "📝 Creating .env.local..."
if [ ! -f .env.local ]; then
    cp .env.example .env.local
    echo "✅ Created .env.local (edit if needed)"
else
    echo "⏭️  .env.local already exists"
fi

echo ""
echo "✅ Setup complete!"
echo ""
echo "To run the World Browser:"
echo "  npm run dev"
echo ""
echo "Then open: http://localhost:3000"
echo ""
echo "To run with the API server:"
echo "  Terminal 1: cd ../server && npm run dev"
echo "  Terminal 2: npm run dev"
echo ""
