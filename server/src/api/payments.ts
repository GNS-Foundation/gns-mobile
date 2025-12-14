// ===========================================
// GNS NODE - PAYMENTS API
// /payments endpoints for financial transfers
//
// Location: src/api/payments.ts
//
// ENDPOINTS:
//   POST /payments/transfer     - Queue payment envelope
//   GET  /payments/inbox        - Fetch pending incoming payments
//   POST /payments/ack/:id      - Accept/reject payment
//   GET  /payments/history      - Get payment history (optional)
//   GET  /payments/:id          - Get single payment (optional)
//
// REQUIRES: Run supabase_payments_migration.sql first
// ===========================================

import { Router, Request, Response } from 'express';
import { isValidPublicKey } from '../lib/crypto';
import * as db from '../lib/db';
import { ApiResponse } from '../types';
import { notifyRecipients } from './messages';  // Reuse WebSocket notification

const router = Router();

// ===========================================
// AUTH MIDDLEWARE (same as messages.ts)
// ===========================================

interface AuthenticatedRequest extends Request {
  gnsPublicKey?: string;
}

/**
 * Verify GNS authentication headers
 * Headers:
 *   X-GNS-PublicKey: sender's public key (hex)
 *   X-GNS-Timestamp: unix timestamp (ms)
 *   X-GNS-Signature: signature of "timestamp:publicKey"
 */
const verifyGnsAuth = async (
  req: AuthenticatedRequest,
  res: Response,
  next: Function
) => {
  try {
    const publicKey = (req.headers['x-gns-publickey'] as string)?.toLowerCase();
    const timestamp = req.headers['x-gns-timestamp'] as string;
    const signature = req.headers['x-gns-signature'] as string;

    // Also accept X-GNS-Identity for backward compatibility
    const identity = (req.headers['x-gns-identity'] as string)?.toLowerCase();

    const pk = publicKey || identity;

    if (!pk || !isValidPublicKey(pk)) {
      return res.status(401).json({
        success: false,
        error: 'Missing or invalid X-GNS-PublicKey header',
      } as ApiResponse);
    }

    // TODO: Verify signature in production
    // if (signature && timestamp) {
    //   const message = `${timestamp}:${pk}`;
    //   const isValid = verifySignature(pk, message, signature);
    //   if (!isValid) {
    //     return res.status(401).json({ success: false, error: 'Invalid signature' });
    //   }
    // }

    req.gnsPublicKey = pk;
    next();
  } catch (error) {
    console.error('Payment auth error:', error);
    res.status(401).json({ success: false, error: 'Authentication failed' });
  }
};

// ===========================================
// POST /payments/transfer
// Queue a payment envelope for delivery
// ===========================================

router.post('/transfer', verifyGnsAuth, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const { envelope } = req.body;

    if (!envelope) {
      return res.status(400).json({
        success: false,
        error: 'Missing envelope',
      } as ApiResponse);
    }

    // Verify sender matches authenticated user
    const senderKey = envelope.fromPublicKey?.toLowerCase();
    if (senderKey !== req.gnsPublicKey) {
      return res.status(403).json({
        success: false,
        error: 'Sender mismatch',
      } as ApiResponse);
    }

    // Verify payload type
    if (envelope.payloadType !== 'gns/payment.transfer') {
      return res.status(400).json({
        success: false,
        error: 'Invalid payload type. Expected gns/payment.transfer',
      } as ApiResponse);
    }

    // Get recipients
    const recipients: string[] = envelope.toPublicKeys || [];
    if (recipients.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'No recipients specified',
      } as ApiResponse);
    }

    if (recipients.length > 1) {
      return res.status(400).json({
        success: false,
        error: 'Payments can only have one recipient',
      } as ApiResponse);
    }

    const recipientPk = recipients[0].toLowerCase();

    // Extract payment ID from envelope
    // Note: The actual paymentId is inside the encrypted payload,
    // so we use envelope.id as the external reference
    const paymentId = envelope.id;

    if (!paymentId) {
      return res.status(400).json({
        success: false,
        error: 'Missing envelope ID',
      } as ApiResponse);
    }

    // Store payment intent
    const paymentIntent = await db.createPaymentIntent({
      payment_id: paymentId,
      from_pk: senderKey,
      to_pk: recipientPk,
      envelope_json: envelope,
      payload_type: envelope.payloadType,
      // Optional metadata (can be extracted from envelope if available)
      currency: envelope.metadata?.currency || null,
      route_type: envelope.metadata?.routeType || null,
      expires_at: envelope.expiresAt ? new Date(envelope.expiresAt).toISOString() : null,
    });

    // Notify recipient via WebSocket
    notifyRecipients([recipientPk], {
      type: 'payment',
      action: 'incoming',
      paymentId: paymentId,
      fromPublicKey: senderKey,
      fromHandle: envelope.fromHandle,
      timestamp: Date.now(),
    });

    console.log(`💰 Payment queued: ${senderKey.substring(0, 8)}... → ${recipientPk.substring(0, 8)}... (${paymentId.substring(0, 8)}...)`);

    return res.status(201).json({
      success: true,
      data: {
        paymentId: paymentId,
        status: 'pending',
        createdAt: paymentIntent.created_at,
        expiresAt: paymentIntent.expires_at,
      },
      message: 'Payment queued for delivery',
    } as ApiResponse);

  } catch (error: any) {
    console.error('POST /payments/transfer error:', error);

    // Handle duplicate payment ID
    if (error?.code === '23505') {  // Unique violation
      return res.status(409).json({
        success: false,
        error: 'Payment with this ID already exists',
      } as ApiResponse);
    }

    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// GET /payments/inbox
// Fetch pending incoming payments
// ===========================================

router.get('/inbox', verifyGnsAuth, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const pk = req.gnsPublicKey!;
    const since = req.query.since as string | undefined;
    const limit = Math.min(parseInt(req.query.limit as string) || 50, 100);

    // Fetch pending payments
    const payments = await db.getPendingPayments(pk, since, limit);

    // Mark as delivered
    const paymentIds = payments.map(p => p.payment_id);
    if (paymentIds.length > 0) {
      await db.markPaymentsDelivered(paymentIds);
    }

    console.log(`📥 Payment inbox: ${pk.substring(0, 8)}... fetched ${payments.length} payments`);

    return res.json({
      success: true,
      data: {
        payments: payments.map(p => ({
          paymentId: p.payment_id,
          envelope: p.envelope_json,
          status: p.status,
          createdAt: p.created_at,
          expiresAt: p.expires_at,
        })),
        total: payments.length,
      },
    } as ApiResponse);

  } catch (error) {
    console.error('GET /payments/inbox error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// POST /payments/ack/:paymentId
// Accept or reject a payment
// ===========================================

router.post('/ack/:paymentId', verifyGnsAuth, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const { paymentId } = req.params;
    const { status, reason, envelope } = req.body;
    const pk = req.gnsPublicKey!;

    // Validate status
    if (!status || !['accepted', 'rejected'].includes(status)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid status. Must be "accepted" or "rejected"',
      } as ApiResponse);
    }

    // Get the payment intent
    const payment = await db.getPaymentIntent(paymentId);

    if (!payment) {
      return res.status(404).json({
        success: false,
        error: 'Payment not found',
      } as ApiResponse);
    }

    // Verify the acknowledger is the recipient
    if (payment.to_pk !== pk) {
      return res.status(403).json({
        success: false,
        error: 'Only the recipient can acknowledge this payment',
      } as ApiResponse);
    }

    // Check if already acknowledged
    if (payment.status === 'accepted' || payment.status === 'rejected') {
      return res.status(409).json({
        success: false,
        error: `Payment already ${payment.status}`,
      } as ApiResponse);
    }

    // Create acknowledgment record
    const ack = await db.createPaymentAck({
      payment_id: paymentId,
      from_pk: pk,
      status: status,
      reason: reason || null,
      envelope_json: envelope || null,
    });

    // Update payment intent status
    await db.updatePaymentStatus(paymentId, status);

    // Notify sender via WebSocket
    notifyRecipients([payment.from_pk], {
      type: 'payment',
      action: status,
      paymentId: paymentId,
      fromPublicKey: pk,
      reason: reason,
      timestamp: Date.now(),
    });

    console.log(`${status === 'accepted' ? '✅' : '❌'} Payment ${status}: ${paymentId.substring(0, 8)}... by ${pk.substring(0, 8)}...`);

    return res.json({
      success: true,
      data: {
        paymentId: paymentId,
        status: status,
        ackedAt: ack.created_at,
      },
      message: `Payment ${status}`,
    } as ApiResponse);

  } catch (error) {
    console.error('POST /payments/ack/:paymentId error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// GET /payments/:paymentId
// Get single payment details
// ===========================================

router.get('/:paymentId', verifyGnsAuth, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const { paymentId } = req.params;
    const pk = req.gnsPublicKey!;

    const payment = await db.getPaymentIntent(paymentId);

    if (!payment) {
      return res.status(404).json({
        success: false,
        error: 'Payment not found',
      } as ApiResponse);
    }

    // Only sender or recipient can view
    if (payment.from_pk !== pk && payment.to_pk !== pk) {
      return res.status(403).json({
        success: false,
        error: 'Access denied',
      } as ApiResponse);
    }

    // Get acknowledgment if exists
    const ack = await db.getPaymentAck(paymentId);

    return res.json({
      success: true,
      data: {
        paymentId: payment.payment_id,
        envelope: payment.envelope_json,
        status: payment.status,
        createdAt: payment.created_at,
        deliveredAt: payment.delivered_at,
        ackedAt: payment.acked_at,
        expiresAt: payment.expires_at,
        ack: ack ? {
          status: ack.status,
          reason: ack.reason,
          createdAt: ack.created_at,
        } : null,
      },
    } as ApiResponse);

  } catch (error) {
    console.error('GET /payments/:paymentId error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

// ===========================================
// GET /payments/history
// Get payment history (sent and received)
// ===========================================

router.get('/history', verifyGnsAuth, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const pk = req.gnsPublicKey!;
    const direction = req.query.direction as 'sent' | 'received' | undefined;
    const status = req.query.status as string | undefined;
    const limit = Math.min(parseInt(req.query.limit as string) || 50, 100);
    const offset = parseInt(req.query.offset as string) || 0;

    const payments = await db.getPaymentHistory(pk, {
      direction,
      status,
      limit,
      offset,
    });

    return res.json({
      success: true,
      data: {
        payments: payments.map(p => ({
          paymentId: p.payment_id,
          direction: p.from_pk === pk ? 'sent' : 'received',
          counterparty: p.from_pk === pk ? p.to_pk : p.from_pk,
          status: p.status,
          createdAt: p.created_at,
          ackedAt: p.acked_at,
        })),
        total: payments.length,
        offset,
        limit,
      },
    } as ApiResponse);

  } catch (error) {
    console.error('GET /payments/history error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    } as ApiResponse);
  }
});

export default router;
