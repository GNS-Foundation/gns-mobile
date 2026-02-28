// trip-verifier/src/bin/analyze.rs
//
// CLI tool: load a breadcrumb chain JSON and run the Criticality Engine.
//
// Usage:
//   cargo run --bin analyze -- chain_export.json
//   cargo run --bin analyze -- --verbose chain_export.json

use std::env;
use std::fs;
use std::process;

use trip_verifier::breadcrumb::Breadcrumb;
use trip_verifier::chain::BreadcrumbChain;
use trip_verifier::criticality::CriticalityEngine;
use trip_verifier::certificate::PoHCertificate;

fn main() {
    let args: Vec<String> = env::args().collect();

    let verbose = args.contains(&"--verbose".to_string()) || args.contains(&"-v".to_string());
    let file_path = args.iter()
        .filter(|a| !a.starts_with('-') && *a != &args[0])
        .next();

    let file_path = match file_path {
        Some(p) => p.clone(),
        None => {
            eprintln!("Usage: analyze [--verbose] <chain_export.json>");
            eprintln!("");
            eprintln!("  Loads a breadcrumb chain and runs the TRIP Criticality Engine.");
            eprintln!("  Export chain from the GNS app using the Export Chain button.");
            process::exit(1);
        }
    };

    // --- Load JSON ---
    println!("Loading chain from: {}", file_path);
    let json_str = match fs::read_to_string(&file_path) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("Error reading file: {e}");
            process::exit(1);
        }
    };

    let breadcrumbs: Vec<Breadcrumb> = match serde_json::from_str(&json_str) {
        Ok(b) => b,
        Err(e) => {
            eprintln!("Error parsing JSON: {e}");
            eprintln!("Expected: array of breadcrumb objects from chain_exporter.dart");
            process::exit(1);
        }
    };

    println!("Loaded {} breadcrumbs", breadcrumbs.len());

    if breadcrumbs.is_empty() {
        eprintln!("Empty chain — nothing to analyze.");
        process::exit(1);
    }

    // --- Verify Chain ---
    println!("\n=== Chain Verification ===");
    let chain = match BreadcrumbChain::from_breadcrumbs(breadcrumbs) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("Chain verification FAILED: {e}");
            eprintln!("The chain has structural issues. Running analysis on what we have...");
            // For development, try to proceed with unverified data
            process::exit(1);
        }
    };

    let identity_short = if chain.identity.len() > 16 {
        format!("{}...{}", &chain.identity[..8], &chain.identity[chain.identity.len()-8..])
    } else {
        chain.identity.clone()
    };

    println!("  Identity:     {}", identity_short);
    println!("  Breadcrumbs:  {}", chain.len());
    println!("  Unique cells: {}", chain.unique_cells());
    println!("  Duration:     {:.1} hours", chain.duration_seconds() / 3600.0);
    println!("  Chain hash:   {}...", &chain.head_hash()[..16.min(chain.head_hash().len())]);

    // --- Displacement Stats ---
    let displacements = chain.displacement_series();
    let intervals = chain.interval_series();

    if !displacements.is_empty() {
        let mean_disp = displacements.iter().sum::<f64>() / displacements.len() as f64;
        let max_disp = displacements.iter().cloned().fold(0.0f64, f64::max);
        let mean_int = intervals.iter().sum::<f64>() / intervals.len() as f64;
        let total_dist: f64 = displacements.iter().sum();

        println!("\n=== Displacement Statistics ===");
        println!("  Total distance:     {:.2} km", total_dist);
        println!("  Mean displacement:  {:.4} km ({:.1} m)", mean_disp, mean_disp * 1000.0);
        println!("  Max displacement:   {:.4} km ({:.1} m)", max_disp, max_disp * 1000.0);
        println!("  Mean interval:      {:.0} seconds ({:.1} min)", mean_int, mean_int / 60.0);
        println!("  Non-zero moves:     {} / {}", 
            displacements.iter().filter(|&&d| d > 0.001).count(),
            displacements.len()
        );
    }

    // --- Run Criticality Engine ---
    println!("\n=== Criticality Engine ===");
    let engine = CriticalityEngine::with_defaults();

    match engine.evaluate(&chain) {
        Ok(result) => {
            println!("\n  --- PSD Analysis (α exponent) ---");
            println!("  α = {:.4}  ({})", result.psd.alpha, result.psd.classification.label());
            println!("  R² = {:.4}", result.psd.r_squared);
            println!("  Frequency bins: {}", result.psd.num_bins);
            println!("  Human range: [0.30, 0.80] → {}", 
                if result.psd.classification.is_human() { "✅ PASS" } else { "❌ FAIL" });

            println!("\n  --- Lévy Flight Analysis (β, κ) ---");
            println!("  β = {:.4}  ({})", result.levy.beta, result.levy.classification.label());
            println!("  κ = {:.2} km  (characteristic travel range)", result.levy.kappa_km);
            println!("  KS statistic: {:.4}", result.levy.ks_statistic);
            println!("  Samples: {}", result.levy.n_samples);
            println!("  Human range: [0.80, 1.20] → {}",
                if result.levy.classification.is_human() { "✅ PASS" } else { "❌ FAIL" });

            println!("\n  --- Six-Component Hamiltonian ---");
            println!("  Mean energy:  {:.4}", result.hamiltonian.mean_energy);
            println!("  Max energy:   {:.4}", result.hamiltonian.max_energy);
            println!("  Alerts: 🟢{} 🟡{} 🟠{} 🔴{}",
                result.hamiltonian.alert_count.green,
                result.hamiltonian.alert_count.yellow,
                result.hamiltonian.alert_count.orange,
                result.hamiltonian.alert_count.red);

            println!("\n  --- Verdict ---");
            println!("  Trust Score:  {:.1} / 100", result.trust_score);
            println!("  Confidence:   {:.1}%", result.confidence * 100.0);
            println!("  Classification: {}", if result.is_human { "🧬 HUMAN" } else { "🤖 NOT VERIFIED" });
            println!("\n  {}", result.verdict.summary);

            if verbose {
                println!("\n  --- PSD Spectrum (top 20 bins) ---");
                for (i, &(freq, power)) in result.psd.spectrum.iter().take(20).enumerate() {
                    println!("    [{:2}] f={:.6} Hz  P={:.6}", i, freq, power);
                }

                println!("\n  --- Hamiltonian Per-Breadcrumb (first 20) ---");
                for score in result.hamiltonian.scores.iter().take(20) {
                    println!("    [{}] H={:.4} ({:?})  spatial={:.3} temporal={:.3} kinetic={:.3}",
                        score.index, score.h_total, score.alert_level,
                        score.h_spatial, score.h_temporal, score.h_kinetic);
                }
            }

            // --- Generate PoH Certificate ---
            println!("\n=== PoH Certificate ===");
            let cert = PoHCertificate::from_criticality_result(
                &result,
                chain.identity.clone(),
                "0000000000000000000000000000000000000000000000000000000000000000".to_string(), // placeholder verifier key
                chain.unique_cells(),
                chain.head_hash().to_string(),
                3600,
            );

            match cert.to_json() {
                Ok(json) => {
                    // Save certificate
                    let cert_path = file_path.replace(".json", "_poh_certificate.json");
                    match fs::write(&cert_path, &json) {
                        Ok(_) => println!("  Certificate saved: {cert_path}"),
                        Err(e) => eprintln!("  Error saving certificate: {e}"),
                    }
                }
                Err(e) => eprintln!("  Error encoding certificate: {e}"),
            }

            match cert.to_cbor_signable() {
                Ok(cbor) => {
                    let cbor_path = file_path.replace(".json", "_poh_certificate.cbor");
                    match fs::write(&cbor_path, &cbor) {
                        Ok(_) => println!("  CBOR certificate: {cbor_path} ({} bytes)", cbor.len()),
                        Err(e) => eprintln!("  Error saving CBOR: {e}"),
                    }
                }
                Err(e) => eprintln!("  Error encoding CBOR: {e}"),
            }

            println!("\nDone. 🌍");
        }
        Err(e) => {
            eprintln!("\nCriticality Engine error: {e}");
            eprintln!("\nThis usually means not enough breadcrumbs for statistical analysis.");
            eprintln!("Need at least 64, ideally 200+ for confident classification.");
            process::exit(1);
        }
    }
}
