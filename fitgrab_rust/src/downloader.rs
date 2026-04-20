//! aria2c download orchestration.

use std::path::Path;
use std::process::Command;
use which::which;

use crate::config::{
    ARIA2_CONCURRENT, ARIA2_CONNECT_TIMEOUT, ARIA2_FILE_ALLOCATION, ARIA2_MAX_TRIES,
    ARIA2_MIN_SPLIT, ARIA2_RETRY_WAIT, ARIA2_SPLIT, ARIA2_TIMEOUT, DEFAULT_USER_AGENT,
};

/// Check if aria2c is available.
pub fn check_aria2c() -> Result<(), String> {
    which("aria2c")
        .map(|_| ())
        .map_err(|_| {
            "aria2c not found. Install: sudo apt install aria2".to_string()
        })
}

/// Download files using aria2c.
pub fn download(direct_urls: &[String], dest_dir: &Path) -> Result<(), String> {
    if direct_urls.is_empty() {
        return Err("No URLs to download".to_string());
    }

    // Create destination directory
    std::fs::create_dir_all(dest_dir)
        .map_err(|e| format!("Failed to create directory: {}", e))?;

    // Write aria2c input file
    let input_path = dest_dir.join(".fitgrab_queue.txt");
    let content: String = direct_urls
        .iter()
        .flat_map(|url| vec![url.clone(), format!(" dir={}", dest_dir.display())])
        .collect::<Vec<_>>()
        .join("\n");
    std::fs::write(&input_path, content)
        .map_err(|e| format!("Failed to write input file: {}", e))?;

    let log_path = dest_dir.join(".fitgrab_aria2.log");

    println!();
    println!("  → aria2c  [{} files → {}]", direct_urls.len(), dest_dir.display());
    println!(
        "     {} concurrent × {} connection/file  |  resume: yes",
        ARIA2_CONCURRENT, ARIA2_SPLIT
    );
    println!("     log: {}", log_path.display());
    println!();
    println!("  {}", "─".repeat(60));

    let status = Command::new("aria2c")
        .arg(format!("--input-file={}", input_path.display()))
        .arg(format!("--max-concurrent-downloads={}", ARIA2_CONCURRENT))
        .arg(format!("--max-connection-per-server={}", ARIA2_SPLIT))
        .arg(format!("--split={}", ARIA2_SPLIT))
        .arg(format!("--min-split-size={}", ARIA2_MIN_SPLIT))
        .arg(format!("--file-allocation={}", ARIA2_FILE_ALLOCATION))
        .arg("--continue=true")
        .arg(format!("--retry-wait={}", ARIA2_RETRY_WAIT))
        .arg(format!("--max-tries={}", ARIA2_MAX_TRIES))
        .arg(format!("--timeout={}", ARIA2_TIMEOUT))
        .arg(format!("--connect-timeout={}", ARIA2_CONNECT_TIMEOUT))
        .arg(format!("--user-agent={}", DEFAULT_USER_AGENT))
        .arg("--console-log-level=notice")
        .arg("--summary-interval=15")
        .arg("--download-result=full")
        .arg(format!("--log={}", log_path.display()))
        .arg("--log-level=warn")
        .status()
        .map_err(|e| format!("Failed to run aria2c: {}", e))?;

    if status.success() {
        // Clean up input file on success
        let _ = std::fs::remove_file(&input_path);
        Ok(())
    } else {
        println!();
        println!(
            "  ⚠  aria2c exited {} — re-run fitgrab to resume.",
            status.code().unwrap_or(1)
        );
        Err(format!("aria2c exited with status {:?}", status.code()))
    }
}
