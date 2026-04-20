#!/usr/bin/env rust
//! fitgrab — FitGirl Repacks downloader via FuckingFast mirrors.

use clap::Parser;
use std::path::PathBuf;

use fitgrab::{
    config::DEFAULT_CONCURRENCY,
    downloader,
    playwright,
    signal,
    utils::{extract_game_name, slugify},
};

#[derive(Parser, Debug)]
#[command(
    name = "fitgrab",
    about = "FitGirl Repacks downloader via FuckingFast mirrors",
    after_help = "Examples:
  fitgrab https://fitgirl-repacks.site/god-of-war-ragnarok/
  fitgrab https://fitgirl-repacks.site/stellar-blade/ --dir ~/Games
  fitgrab https://paste.fitgirl-repacks.site/?<id>#<key> --dir ~/Games
  fitgrab <url> --dry-run"
)]
struct Args {
    /// FitGirl game URL or PrivateBin paste URL
    url: String,

    /// Download directory (default: auto-detect from filename → ~/Games/<game>/)
    #[arg(short, long)]
    dir: Option<PathBuf>,

    /// Show resolved URLs without downloading
    #[arg(long)]
    dry_run: bool,

    /// Parallel contexts for URL resolution
    #[arg(short, long, default_value_t = DEFAULT_CONCURRENCY)]
    concurrency: usize,
}

#[tokio::main]
async fn main() {
    // Setup signal handler
    signal::setup_sigint();

    let args = Args::parse();

    // Check aria2c availability
    if !args.dry_run {
        if let Err(e) = downloader::check_aria2c() {
            eprintln!();
            eprintln!("  ✗ {}", e);
            eprintln!();
            std::process::exit(1);
        }
    }

    // Resolve links via Playwright helper
    let result = match playwright::resolve_links(&args.url, args.concurrency).await {
        Ok(r) => r,
        Err(e) => {
            eprintln!();
            eprintln!("  ✗ {}", e);
            eprintln!();
            std::process::exit(1);
        }
    };

    if result.links.is_empty() {
        eprintln!();
        eprintln!("  ✗  No FuckingFast links found. Check the game URL.");
        eprintln!();
        std::process::exit(1);
    }

    // Determine download directory
    let dest_dir = if let Some(dir) = &args.dir {
        dir.clone()
    } else {
        // Auto-detect from resolved URLs
        let game_name = extract_game_name(&result.links);
        if let Some(name) = game_name {
            let folder_name = slugify(&name);
            dirs::home_dir()
                .unwrap_or_else(|| PathBuf::from("."))
                .join("Games")
                .join(folder_name)
        } else {
            PathBuf::from(".")
        }
    };

    eprintln!();
    eprintln!("  ✓  Dest  : {}", dest_dir.display());

    if result.links.is_empty() {
        eprintln!();
        eprintln!("  ✗  Nothing to download.");
        eprintln!();
        std::process::exit(1);
    }

    if args.dry_run {
        eprintln!();
        eprintln!("  [DRY RUN — resolved URLs]");
        eprintln!();
        for url in &result.links {
            eprintln!("    {}", url);
        }
        eprintln!();
        return;
    }

    // Download via aria2c
    if let Err(e) = downloader::download(&result.links, &dest_dir) {
        eprintln!();
        eprintln!("  ✗ {}", e);
        eprintln!();
        std::process::exit(1);
    }

    eprintln!();
    eprintln!("  ✓  Done!  →  {}", dest_dir.display());
    eprintln!("  Extract: cd '{}' && unrar x *.part01.rar", dest_dir.display());
    eprintln!();
}
