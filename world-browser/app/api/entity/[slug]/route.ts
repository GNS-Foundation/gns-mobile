import { NextRequest, NextResponse } from 'next/server';
import { MOCK_ENTITY } from '@/lib/api';

// GET /api/entity/[slug]
export async function GET(
  request: NextRequest,
  { params }: { params: { slug: string } }
) {
  const { slug } = params;

  try {
    // In production, forward to Gateway API
    const gatewayUrl = process.env.GATEWAY_API_URL || 'http://localhost:3001';
    const response = await fetch(`${gatewayUrl}/web/entity/${slug}`, {
      headers: {
        'Content-Type': 'application/json',
      },
      // Cache for 5 minutes
      next: { revalidate: 300 },
    });

    if (response.ok) {
      const data = await response.json();
      return NextResponse.json(data);
    }

    if (response.status === 404 && process.env.NODE_ENV === 'production') {
      return NextResponse.json(
        { error: 'Entity not found' },
        { status: 404 }
      );
    }
  } catch (error) {
    console.error('Gateway API error:', error);
  }

  // In development, return mock data
  if (process.env.NODE_ENV === 'development') {
    return NextResponse.json({
      ...MOCK_ENTITY,
      slug,
    });
  }

  return NextResponse.json(
    { error: 'Entity not found' },
    { status: 404 }
  );
}
