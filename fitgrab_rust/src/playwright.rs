//! Playwright helper subprocess management.

use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::process::Stdio;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;

/// Input for the Playwright helper.
#[derive(Debug, Serialize)]
pub struct HelperInput {
    pub url: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub concurrency: Option<usize>,
}

/// Output from the Playwright helper.
#[derive(Debug, Deserialize)]
pub struct HelperOutput {
    pub title: String,
    pub links: Vec<String>,
}

/// Find the playwright-helper script location.
fn find_helper_script() -> Option<PathBuf> {
    // Check for script relative to executable
    if let Ok(exe_path) = std::env::current_exe() {
        let parent = exe_path.parent()?.parent()?.to_path_buf();
        let candidate = parent.join("playwright-helper").join("index.js");
        if candidate.exists() {
            return Some(candidate);
        }
    }

    // Check relative to CWD (for development)
    let cwd_candidate = PathBuf::from("playwright-helper/index.js");
    if cwd_candidate.exists() {
        return Some(cwd_candidate);
    }

    // Check in the fitgrab_rust directory
    let home = std::env::var("HOME").ok()?;
    let home_candidate = PathBuf::from(&home)
        .join(".local/bin/fitgrab_rust/playwright-helper/index.js");
    if home_candidate.exists() {
        return Some(home_candidate);
    }

    None
}

/// Resolve download links using the Playwright helper.
pub async fn resolve_links(url: &str, concurrency: usize) -> Result<HelperOutput, String> {
    let script_path = find_helper_script()
        .ok_or_else(|| "Could not find playwright-helper/index.js".to_string())?;

    let input = HelperInput {
        url: url.to_string(),
        concurrency: Some(concurrency),
    };

    let input_json = serde_json::to_string(&input)
        .map_err(|e| format!("Failed to serialize input: {}", e))?;

    let mut child = Command::new("node")
        .arg(&script_path)
        .arg(&input_json)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("Failed to spawn node: {}", e))?;

    // Read stdout for JSON result
    let stdout = child.stdout.take().ok_or("Failed to capture stdout")?;
    let stderr = child.stderr.take().ok_or("Failed to capture stderr")?;

    let mut stdout_reader = BufReader::new(stdout).lines();
    let mut stderr_reader = BufReader::new(stderr).lines();

    let mut json_line = None;
    let mut stderr_lines = Vec::new();

    // Read both stdout and stderr concurrently
    loop {
        tokio::select! {
            line = stdout_reader.next_line() => {
                match line {
                    Ok(Some(l)) => {
                        // First line from stdout is our JSON result
                        if json_line.is_none() {
                            json_line = Some(l);
                        }
                    }
                    Ok(None) => break,
                    Err(e) => return Err(format!("Failed to read stdout: {}", e)),
                }
            }
            line = stderr_reader.next_line() => {
                match line {
                    Ok(Some(l)) => {
                        // Print stderr to show progress
                        eprintln!("{}", l);
                        stderr_lines.push(l);
                    }
                    Ok(None) => {}
                    Err(_) => {}
                }
            }
        }
    }

    let status = child.wait().await.map_err(|e| format!("Failed to wait for node: {}", e))?;

    if !status.success() {
        return Err(format!(
            "Playwright helper exited with status {}",
            status
        ));
    }

    let json = json_line.ok_or("No output from Playwright helper")?;
    let output: HelperOutput = serde_json::from_str(&json)
        .map_err(|e| format!("Failed to parse helper output: {}", e))?;

    Ok(output)
}
