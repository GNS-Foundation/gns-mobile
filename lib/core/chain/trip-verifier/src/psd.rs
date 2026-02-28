// trip-verifier/src/psd.rs
//
// Power Spectral Density (PSD) Analysis
// ======================================
//
// v2: Handles sparse trajectories from mobile collection.
//
// Real-world breadcrumb chains have irregular sampling intervals
// and stationary periods. Before computing PSD, we:
// 1. Filter out zero-displacement entries (stationary)
// 2. Resample to regular intervals via linear interpolation
// 3. Apply Welch's method on the resampled signal
//
// The spectral signature of human mobility: real humans produce
// 1/f^α pink noise with α ∈ [0.30, 0.80].
//
// - White noise (α ≈ 0): bots, random walk generators
// - Pink noise (α ∈ [0.30, 0.80]): biological systems at criticality
// - Brown noise (α ≈ 2): GPS replays, scripted movement

use rustfft::{FftPlanner, num_complex::Complex};
use crate::error::{TripError, Result};

/// Result of PSD analysis on a displacement time series.
#[derive(Debug, Clone)]
pub struct PsdResult {
    /// The PSD scaling exponent α.
    pub alpha: f64,

    /// R² of the log-log fit (goodness of fit).
    pub r_squared: f64,

    /// Number of frequency bins used in the fit.
    pub num_bins: usize,

    /// The raw PSD values (frequency, power) for diagnostics.
    pub spectrum: Vec<(f64, f64)>,

    /// Classification based on α range.
    pub classification: PsdClassification,

    /// Preprocessing stats
    pub preprocess: PreprocessStats,
}

/// Stats from the preprocessing step.
#[derive(Debug, Clone)]
pub struct PreprocessStats {
    /// Original number of samples
    pub original_count: usize,
    /// Samples after filtering stationary
    pub after_filter: usize,
    /// Samples after resampling
    pub resampled_count: usize,
    /// Fraction of non-zero displacements
    pub movement_fraction: f64,
}

/// Classification of the PSD scaling exponent per TRIP spec Table 3.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum PsdClassification {
    WhiteNoise,
    Borderline,
    Biological,
    StrongCorrelation,
    BrownNoise,
}

impl PsdClassification {
    pub fn from_alpha(alpha: f64) -> Self {
        match alpha {
            a if a < 0.10 => Self::WhiteNoise,
            a if a < 0.30 => Self::Borderline,
            a if a <= 0.80 => Self::Biological,
            a if a <= 1.50 => Self::StrongCorrelation,
            _ => Self::BrownNoise,
        }
    }

    pub fn is_human(&self) -> bool {
        matches!(self, Self::Biological)
    }

    pub fn label(&self) -> &'static str {
        match self {
            Self::WhiteNoise => "white_noise",
            Self::Borderline => "borderline",
            Self::Biological => "biological",
            Self::StrongCorrelation => "strong_correlation",
            Self::BrownNoise => "brown_noise",
        }
    }
}

/// Compute PSD from a BreadcrumbChain's displacement + interval series.
///
/// This is the main entry point. Handles sparse, irregular data
/// by preprocessing before FFT.
pub fn compute_psd_from_chain(
    displacement_km: &[f64],
    interval_seconds: &[f64],
) -> Result<PsdResult> {
    if displacement_km.len() != interval_seconds.len() {
        return Err(TripError::PsdError(
            "Displacement and interval arrays must be same length".to_string()
        ));
    }

    let original_count = displacement_km.len();

    // --- Step 1: Build cumulative position signal ---
    // Instead of analyzing raw displacements (which are mostly zero
    // for sparse collection), build a cumulative distance signal
    // and resample it at regular intervals.
    //
    // The VELOCITY (displacement/interval) at regular intervals
    // is what carries the spectral signature.
    let (resampled, resample_dt, stats) = preprocess_sparse(
        displacement_km, interval_seconds
    )?;

    // --- Step 2: Compute PSD on the resampled signal ---
    let mut result = compute_psd_welch(&resampled, resample_dt)?;
    result.preprocess = stats;

    Ok(result)
}

/// Preprocess sparse, irregularly-sampled trajectory data.
///
/// Strategy:
/// 1. Compute cumulative elapsed time and cumulative distance
/// 2. Build velocity = d(distance)/d(time) as a function of time
/// 3. Resample at the median interval to get regular spacing
/// 4. Return the resampled velocity series
fn preprocess_sparse(
    displacement_km: &[f64],
    interval_seconds: &[f64],
) -> Result<(Vec<f64>, f64, PreprocessStats)> {
    let n = displacement_km.len();

    if n < 32 {
        return Err(TripError::PsdError(
            format!("Need at least 32 displacements, got {n}")
        ));
    }

    // Count movement fraction
    let non_zero = displacement_km.iter().filter(|&&d| d > 0.001).count();
    let movement_fraction = non_zero as f64 / n as f64;

    // Build cumulative time axis
    let mut cum_time = Vec::with_capacity(n + 1);
    cum_time.push(0.0);
    for &dt in interval_seconds {
        cum_time.push(cum_time.last().unwrap() + dt);
    }

    // Build velocity series: v[i] = displacement[i] / interval[i]
    // This is the instantaneous speed at each sample point
    let velocities: Vec<f64> = displacement_km.iter()
        .zip(interval_seconds.iter())
        .map(|(&d, &dt)| if dt > 0.1 { d / dt } else { 0.0 })
        .collect();

    // Time midpoints for each velocity sample
    let time_midpoints: Vec<f64> = (0..n)
        .map(|i| cum_time[i] + interval_seconds[i] / 2.0)
        .collect();

    // Find resampling interval: use median of non-zero intervals
    let mut sorted_intervals: Vec<f64> = interval_seconds.iter()
        .filter(|&&dt| dt > 0.0 && dt < 86400.0) // filter extreme gaps (>24h)
        .copied()
        .collect();
    sorted_intervals.sort_by(|a, b| a.partial_cmp(b).unwrap());

    let resample_dt = if sorted_intervals.is_empty() {
        300.0 // default 5 minutes
    } else {
        sorted_intervals[sorted_intervals.len() / 2] // median
    };

    // Resample velocity at regular intervals via linear interpolation
    let total_time = *cum_time.last().unwrap();

    // Cap maximum gap: if there's a gap > 4 hours, skip it
    // This prevents long idle periods from dominating
    let max_gap = 4.0 * 3600.0; // 4 hours in seconds

    // Build segments (contiguous periods without huge gaps)
    let mut segments: Vec<(Vec<f64>, Vec<f64>)> = Vec::new(); // (times, velocities)
    let mut seg_times = vec![time_midpoints[0]];
    let mut seg_vels = vec![velocities[0]];

    for i in 1..n {
        let gap = time_midpoints[i] - time_midpoints[i - 1];
        if gap > max_gap {
            // End current segment, start new one
            if seg_times.len() >= 4 {
                segments.push((seg_times.clone(), seg_vels.clone()));
            }
            seg_times.clear();
            seg_vels.clear();
        }
        seg_times.push(time_midpoints[i]);
        seg_vels.push(velocities[i]);
    }
    if seg_times.len() >= 4 {
        segments.push((seg_times, seg_vels));
    }

    if segments.is_empty() {
        return Err(TripError::PsdError(
            "No continuous segments found (all gaps > 4 hours)".to_string()
        ));
    }

    // Find the longest segment and resample it
    let longest = segments.iter()
        .max_by_key(|(t, _)| t.len())
        .unwrap();

    let (seg_t, seg_v) = longest;
    let seg_start = seg_t[0];
    let seg_end = *seg_t.last().unwrap();
    let seg_duration = seg_end - seg_start;

    let n_resampled = (seg_duration / resample_dt).ceil() as usize;
    let n_resampled = n_resampled.max(32).min(4096);

    let mut resampled = Vec::with_capacity(n_resampled);
    for i in 0..n_resampled {
        let t = seg_start + i as f64 * resample_dt;
        let v = interpolate_linear(seg_t, seg_v, t);
        resampled.push(v);
    }

    let stats = PreprocessStats {
        original_count: n,
        after_filter: longest.0.len(),
        resampled_count: resampled.len(),
        movement_fraction,
    };

    Ok((resampled, resample_dt, stats))
}

/// Linear interpolation of value at time t given (times, values) arrays.
fn interpolate_linear(times: &[f64], values: &[f64], t: f64) -> f64 {
    if t <= times[0] { return values[0]; }
    if t >= *times.last().unwrap() { return *values.last().unwrap(); }

    // Binary search for bracket
    let mut lo = 0;
    let mut hi = times.len() - 1;
    while hi - lo > 1 {
        let mid = (lo + hi) / 2;
        if times[mid] <= t {
            lo = mid;
        } else {
            hi = mid;
        }
    }

    let dt = times[hi] - times[lo];
    if dt < 0.001 {
        return values[lo];
    }

    let frac = (t - times[lo]) / dt;
    values[lo] + frac * (values[hi] - values[lo])
}

/// Core Welch's method PSD computation on a regularly-sampled signal.
fn compute_psd_welch(signal: &[f64], dt: f64) -> Result<PsdResult> {
    let n = signal.len();

    if n < 32 {
        return Err(TripError::PsdError(
            format!("Need at least 32 samples after preprocessing, got {n}")
        ));
    }

    // Remove mean
    let mean = signal.iter().sum::<f64>() / n as f64;
    let centered: Vec<f64> = signal.iter().map(|&x| x - mean).collect();

    // Welch parameters
    let segment_len = optimal_segment_length(n);
    let overlap = segment_len / 2;
    let step = segment_len - overlap;

    let hann_window = hann(segment_len);
    let window_power: f64 = hann_window.iter().map(|w| w * w).sum::<f64>() / segment_len as f64;

    let mut planner = FftPlanner::<f64>::new();
    let fft = planner.plan_fft_forward(segment_len);

    let mut avg_psd = vec![0.0f64; segment_len / 2 + 1];
    let mut n_segments = 0;

    let mut start = 0;
    while start + segment_len <= n {
        let mut buffer: Vec<Complex<f64>> = centered[start..start + segment_len]
            .iter()
            .zip(hann_window.iter())
            .map(|(&x, &w)| Complex::new(x * w, 0.0))
            .collect();

        fft.process(&mut buffer);

        for (i, psd_bin) in avg_psd.iter_mut().enumerate() {
            let mag_sq = buffer[i].norm_sqr();
            let scale = if i == 0 || i == segment_len / 2 { 1.0 } else { 2.0 };
            *psd_bin += scale * mag_sq / (segment_len as f64 * window_power);
        }

        n_segments += 1;
        start += step;
    }

    if n_segments == 0 {
        return Err(TripError::PsdError("No complete segments".to_string()));
    }

    for bin in &mut avg_psd {
        *bin /= n_segments as f64;
    }

    // Frequency axis
    let fs = 1.0 / dt;
    let df = fs / segment_len as f64;
    let spectrum: Vec<(f64, f64)> = (1..avg_psd.len())
        .map(|i| (i as f64 * df, avg_psd[i]))
        .filter(|&(_, p)| p > 0.0)
        .collect();

    if spectrum.len() < 4 {
        return Err(TripError::PsdError(
            "Too few non-zero frequency bins for fitting".to_string()
        ));
    }

    // Log-log fit
    let log_f: Vec<f64> = spectrum.iter().map(|&(f, _)| f.ln()).collect();
    let log_p: Vec<f64> = spectrum.iter().map(|&(_, p)| p.ln()).collect();

    let (slope, _intercept, r_squared) = linear_regression(&log_f, &log_p);
    let alpha = -slope;

    let classification = PsdClassification::from_alpha(alpha);

    Ok(PsdResult {
        alpha,
        r_squared,
        num_bins: spectrum.len(),
        spectrum,
        classification,
        preprocess: PreprocessStats {
            original_count: 0,
            after_filter: 0,
            resampled_count: signal.len(),
            movement_fraction: 0.0,
        },
    })
}

// ========================================================================
// Internal helpers
// ========================================================================

fn hann(size: usize) -> Vec<f64> {
    let n = size as f64;
    (0..size)
        .map(|i| 0.5 * (1.0 - (2.0 * std::f64::consts::PI * i as f64 / (n - 1.0)).cos()))
        .collect()
}

fn optimal_segment_length(total_samples: usize) -> usize {
    let mut seg = 64;
    while seg * 2 <= total_samples / 2 {
        seg *= 2;
    }
    seg.max(32)
}

fn linear_regression(x: &[f64], y: &[f64]) -> (f64, f64, f64) {
    let n = x.len() as f64;
    let sum_x: f64 = x.iter().sum();
    let sum_y: f64 = y.iter().sum();
    let sum_xy: f64 = x.iter().zip(y.iter()).map(|(a, b)| a * b).sum();
    let sum_x2: f64 = x.iter().map(|a| a * a).sum();
    let sum_y2: f64 = y.iter().map(|a| a * a).sum();

    let denom = n * sum_x2 - sum_x * sum_x;
    if denom.abs() < f64::EPSILON {
        return (0.0, 0.0, 0.0);
    }

    let slope = (n * sum_xy - sum_x * sum_y) / denom;
    let intercept = (sum_y - slope * sum_x) / n;

    let y_mean = sum_y / n;
    let ss_tot = sum_y2 - n * y_mean * y_mean;
    let ss_res: f64 = x.iter().zip(y.iter())
        .map(|(&xi, &yi)| {
            let pred = slope * xi + intercept;
            (yi - pred).powi(2)
        })
        .sum();

    let r_squared = if ss_tot.abs() > f64::EPSILON {
        1.0 - ss_res / ss_tot
    } else {
        0.0
    };

    (slope, intercept, r_squared)
}

/// Legacy entry point: compute PSD directly on raw displacements.
/// Used by unit tests.
pub fn compute_psd(displacements: &[f64], dt_mean: f64) -> Result<PsdResult> {
    compute_psd_welch(displacements, dt_mean)
}

#[cfg(test)]
mod tests {
    use super::*;
    use rand::Rng;

    #[test]
    fn test_white_noise_alpha() {
        let mut rng = rand::thread_rng();
        let signal: Vec<f64> = (0..1024).map(|_| rng.gen_range(0.0..1.0)).collect();
        let result = compute_psd(&signal, 300.0).unwrap();
        assert!(result.alpha.abs() < 0.30, "White noise α should be near 0, got {}", result.alpha);
    }

    #[test]
    fn test_brown_noise_alpha() {
        let mut rng = rand::thread_rng();
        let mut signal = vec![0.0f64; 1024];
        for i in 1..1024 { signal[i] = signal[i - 1] + rng.gen_range(-1.0..1.0); }
        let result = compute_psd(&signal, 300.0).unwrap();
        assert!(result.alpha > 1.5, "Brown noise α should be > 1.5, got {}", result.alpha);
    }

    #[test]
    fn test_linear_regression_perfect() {
        let x = vec![1.0, 2.0, 3.0, 4.0, 5.0];
        let y = vec![2.0, 4.0, 6.0, 8.0, 10.0];
        let (slope, intercept, r2) = linear_regression(&x, &y);
        assert!((slope - 2.0).abs() < 0.001);
        assert!(intercept.abs() < 0.001);
        assert!((r2 - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_hann_window() {
        let w = hann(64);
        assert_eq!(w.len(), 64);
        assert!(w[0] < 0.01);
        assert!(w[63] < 0.01);
        assert!((w[32] - 1.0).abs() < 0.01);
    }

    #[test]
    fn test_insufficient_samples() {
        let signal = vec![1.0; 16];
        let result = compute_psd(&signal, 300.0);
        assert!(result.is_err());
    }

    #[test]
    fn test_sparse_preprocessing() {
        // Simulate sparse collection: mostly zero with some movement
        let mut rng = rand::thread_rng();
        let n = 200;
        let mut displacements = Vec::with_capacity(n);
        let mut intervals = Vec::with_capacity(n);
        
        for _ in 0..n {
            // 30% chance of movement
            if rng.gen_range(0.0..1.0) < 0.3 {
                displacements.push(rng.gen_range(0.01..0.5));
            } else {
                displacements.push(0.0);
            }
            // Irregular intervals: 1-30 minutes
            intervals.push(rng.gen_range(60.0..1800.0));
        }

        let result = compute_psd_from_chain(&displacements, &intervals);
        assert!(result.is_ok(), "Sparse data should be processable: {:?}", result.err());
    }

    #[test]
    fn test_interpolation() {
        let times = vec![0.0, 1.0, 2.0, 3.0];
        let values = vec![0.0, 10.0, 20.0, 30.0];
        assert!((interpolate_linear(&times, &values, 1.5) - 15.0).abs() < 0.01);
        assert!((interpolate_linear(&times, &values, 0.0) - 0.0).abs() < 0.01);
        assert!((interpolate_linear(&times, &values, 3.0) - 30.0).abs() < 0.01);
    }
}
