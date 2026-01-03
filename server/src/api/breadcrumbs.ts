// ===========================================
// GNS NODE - BREADCRUMBS API
// Cloud Sync for Proof-of-Trajectory
// ===========================================

import { Router, Request, Response } from 'express';
import * as db from '../lib/db';
import { ApiResponse } from '../types';

const router = Router();

// ===========================================
// POST /breadcrumbs
// Upload an encrypted breadcrumb
// ===========================================
router.post('/', async (req: Request, res: Response) => {
    try {
        const { pk_root, payload, signature } = req.body;

        if (!pk_root || !payload || !signature) {
            return res.status(400).json({
                success: false,
                error: 'Missing required fields',
            } as ApiResponse);
        }

        // TODO: Verify signature matches pk_root and payload
        // For now, we trust the client's signature

        const breadcrumb = await db.createBreadcrumb(pk_root, payload, signature);

        return res.json({
            success: true,
            data: breadcrumb,
        } as ApiResponse);

    } catch (error) {
        console.error('POST /breadcrumbs error:', error);
        return res.status(500).json({
            success: false,
            error: 'Internal server error',
        } as ApiResponse);
    }
});

// ===========================================
// GET /breadcrumbs/:pk
// Fetch encrypted breadcrumbs for an identity
// ===========================================
router.get('/:pk', async (req: Request, res: Response) => {
    try {
        const { pk } = req.params;

        if (!pk || pk.length !== 64) {
            return res.status(400).json({
                success: false,
                error: 'Invalid public key',
            } as ApiResponse);
        }

        const breadcrumbs = await db.getBreadcrumbs(pk);

        return res.json({
            success: true,
            data: breadcrumbs,
            count: breadcrumbs.length,
        } as ApiResponse);

    } catch (error) {
        console.error('GET /breadcrumbs/:pk error:', error);
        return res.status(500).json({
            success: false,
            error: 'Internal server error',
        } as ApiResponse);
    }
});

export default router;
