import { NextRequest, NextResponse } from 'next/server';
import { MOCK_IDENTITY } from '@/lib/api';

// GET /api/profile/[handle]
// This is an internal API route that can:
// 1. Forward requests to the external Gateway API
// 2. Add caching
// 3. Return mock data in development

export async function GET(
  request: NextRequest,
  { params }: { params: { handle: string } }
) {
  const { handle } = params;
  const cleanHandle = handle.replace(/^@/, '');

  try {
    // In production, forward to Gateway API
    const gatewayUrl = process.env.GATEWAY_API_URL || 'http://localhost:3001';
    const response = await fetch(`${gatewayUrl}/web/profile/@${cleanHandle}`, {
      headers: {
        'Content-Type': 'application/json',
      },
      // Cache for 60 seconds
      next: { revalidate: 60 },
    });

    if (response.ok) {
      const data = await response.json();
      return NextResponse.json(data);
    }

    // If not found in production, return 404
    if (response.status === 404 && process.env.NODE_ENV === 'production') {
      return NextResponse.json(
        { error: 'Identity not found' },
        { status: 404 }
      );
    }
  } catch (error) {
    console.error('Gateway API error:', error);
    // Fall through to mock data in development
  }

  // In development, return mock data
  if (process.env.NODE_ENV === 'development') {
    return NextResponse.json({
      ...MOCK_IDENTITY,
      handle: cleanHandle,
    });
  }

  return NextResponse.json(
    { error: 'Identity not found' },
    { status: 404 }
  );
}
