//! Utility functions for fitgrab.

use rand::Rng;
use rand::thread_rng;
use regex::Regex;

use crate::config::{BACKOFF_BASE, BACKOFF_CAP};

/// Turn a game title into a safe directory name.
pub fn slugify(title: &str) -> String {
    let re_brackets = Regex::new(r"[\[({][^\])}]*[\])}]").unwrap();
    let re_special = Regex::new(r"[^\w\s\-]").unwrap();
    let re_spaces = Regex::new(r"\s+").unwrap();

    let title = re_brackets.replace_all(title, "");
    let title = re_special.replace_all(&title, "");
    let title = re_spaces.replace_all(title.trim(), "_");

    let result = title.to_string();
    if result.len() > 80 {
        result[..80].to_string()
    } else {
        result
    }
}

/// Full-jitter exponential backoff for distributed retry timing.
pub fn jittered_backoff(attempt: u32) -> f64 {
    let ceiling = (BACKOFF_BASE * (2_f64.powi(attempt as i32))).min(BACKOFF_CAP);
    let mut rng = thread_rng();
    rng.gen_range(0.0..ceiling)
}

/// Extract game name from first resolved URL.
pub fn extract_game_name(direct_urls: &[String]) -> Option<String> {
    if direct_urls.is_empty() {
        return None;
    }

    let fname = direct_urls[0]
        .split('/')
        .next_back()
        .unwrap_or("")
        .split('?')
        .next()
        .unwrap_or("");

    let re = Regex::new(r"^(.+?)_--_").unwrap();
    re.captures(fname)
        .map(|caps| caps[1].replace('_', " "))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_slugify() {
        assert_eq!(slugify("God of War Ragnarök"), "God_of_War_Ragnar_k");
        assert_eq!(slugify("Game [Update] (DLC)"), "Game");
        assert_eq!(slugify("Test   Multiple   Spaces"), "Test_Multiple_Spaces");
    }

    #[test]
    fn test_extract_game_name() {
        let urls = vec![
            "https://cdn.example.com/GameName_--_fitgirl-repacks.site_--_.part01.rar?token=abc".to_string()
        ];
        assert_eq!(extract_game_name(&urls), Some("Game Name".to_string()));

        let empty_urls: Vec<String> = vec![];
        assert_eq!(extract_game_name(&empty_urls), None);
    }
}
