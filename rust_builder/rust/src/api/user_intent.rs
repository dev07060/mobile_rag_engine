// Copyright 2025 mobile_rag_engine contributors
// SPDX-License-Identifier: MIT
//
// Licensed under the MIT License. You may obtain a copy of the License at
// https://opensource.org/licenses/MIT
//
// This software is provided "AS IS", without warranty of any kind, express or
// implied, including but not limited to the warranties of merchantability,
// fitness for a particular purpose, and noninfringement. In no event shall the
// authors or copyright holders be liable for any claim, damages, or other
// liability arising from the use of this software.
//
// CONTRIBUTOR GUIDELINES:
// This file is part of the core engine. Any modifications require owner approval.
// Please submit a PR with detailed explanation of changes before modifying.
//
//! User intent parsing for slash commands.

#[derive(Debug, Clone, PartialEq)]
pub enum UserIntent {
    Summary { query: String },
    Define { term: String },
    ExpandKnowledge { query: String },
    General { query: String },
    InvalidCommand { command: String, reason: String },
}

impl UserIntent {
    pub fn get_query(&self) -> &str {
        match self {
            UserIntent::Summary { query } => query,
            UserIntent::Define { term } => term,
            UserIntent::ExpandKnowledge { query } => query,
            UserIntent::General { query } => query,
            UserIntent::InvalidCommand { command, .. } => command,
        }
    }

    pub fn intent_type(&self) -> &str {
        match self {
            UserIntent::Summary { .. } => "summary",
            UserIntent::Define { .. } => "define",
            UserIntent::ExpandKnowledge { .. } => "more",
            UserIntent::General { .. } => "general",
            UserIntent::InvalidCommand { .. } => "invalid",
        }
    }
}

/// Parse user input into a UserIntent.
#[flutter_rust_bridge::frb(sync)]
pub fn parse_user_intent(input: &str) -> UserIntent {
    let trimmed = input.trim();

    if trimmed.is_empty() {
        return UserIntent::InvalidCommand {
            command: String::new(),
            reason: "Empty input".to_string(),
        };
    }

    if !trimmed.starts_with('/') {
        return UserIntent::General {
            query: trimmed.to_string(),
        };
    }

    let parts: Vec<&str> = trimmed.splitn(2, ' ').collect();
    let command = parts[0].to_lowercase();
    let argument = parts.get(1).map(|s| s.trim()).unwrap_or("");

    match command.as_str() {
        "/summary" => UserIntent::Summary {
            query: argument.to_string(),
        },
        "/define" => {
            if argument.is_empty() {
                UserIntent::InvalidCommand {
                    command: command.to_string(),
                    reason: "Term required for /define. Usage: /define <term>".to_string(),
                }
            } else {
                UserIntent::Define {
                    term: argument.to_string(),
                }
            }
        }
        "/more" => UserIntent::ExpandKnowledge {
            query: argument.to_string(),
        },
        _ => UserIntent::InvalidCommand {
            command: command.to_string(),
            reason: format!(
                "Unknown command '{}'. Available: /summary, /define, /more",
                command
            ),
        },
    }
}

#[derive(Debug, Clone)]
pub struct ParsedIntent {
    pub intent_type: String,
    pub query: String,
    pub is_valid: bool,
    pub error_message: Option<String>,
}

/// Parse intent (FRB-friendly wrapper).
#[flutter_rust_bridge::frb(sync)]
pub fn parse_intent(input: String) -> ParsedIntent {
    let intent = parse_user_intent(&input);
    match intent {
        UserIntent::Summary { query } => ParsedIntent {
            intent_type: "summary".to_string(),
            query,
            is_valid: true,
            error_message: None,
        },
        UserIntent::Define { term } => ParsedIntent {
            intent_type: "define".to_string(),
            query: term,
            is_valid: true,
            error_message: None,
        },
        UserIntent::ExpandKnowledge { query } => ParsedIntent {
            intent_type: "more".to_string(),
            query,
            is_valid: true,
            error_message: None,
        },
        UserIntent::General { query } => ParsedIntent {
            intent_type: "general".to_string(),
            query,
            is_valid: true,
            error_message: None,
        },
        UserIntent::InvalidCommand { command, reason } => ParsedIntent {
            intent_type: "invalid".to_string(),
            query: command,
            is_valid: false,
            error_message: Some(reason),
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_summary_command() {
        let intent = parse_user_intent("/summary about RWA");
        assert!(matches!(intent, UserIntent::Summary { .. }));
        assert_eq!(intent.get_query(), "about RWA");
    }

    #[test]
    fn test_parse_define_command() {
        let intent = parse_user_intent("/define smart contract");
        assert!(matches!(intent, UserIntent::Define { .. }));
    }

    #[test]
    fn test_parse_empty_input() {
        let intent = parse_user_intent("");
        assert!(matches!(intent, UserIntent::InvalidCommand { .. }));
    }
}
