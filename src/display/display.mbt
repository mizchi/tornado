///|
/// Truncate long text for display, adding "..." if truncated
pub fn truncate(s : String, max : Int) -> String {
  if s.length() <= max {
    s
  } else {
    s.view(start_offset=0, end_offset=max).to_string() + "..."
  }
}

///| Normalize provider-specific UI chrome to plain TUI-style log lines.

///|
/// Returns None for blank lines and visual separators.
pub fn format_agent_output_line(line : String) -> String? {
  let trimmed = line.trim().to_string()
  if trimmed.is_empty() || is_separator_line(trimmed) {
    return None
  }
  let normalized = strip_provider_prefix(trimmed)
  if normalized.is_empty() {
    None
  } else {
    Some(normalized)
  }
}

///|
/// Format a normalized agent panel entry, including the leading agent label.
pub fn format_agent_panel_entry(agent_id : String, line : String) -> String? {
  match format_agent_output_line(line) {
    Some(formatted) => Some("  [\{agent_id}] \{formatted}")
    None => None
  }
}

///|
/// Format a task start entry for the agent panel.
pub fn format_task_start_line(task_id : String, desc : String) -> String {
  "[\{task_id}] Starting: \{desc}"
}

///|
/// Format a task assignment entry for the agent panel.
pub fn format_task_assign_line(task_id : String) -> String {
  "[\{task_id}] Assigned"
}

///|
/// Format a review start entry for the agent panel.
pub fn format_review_start_line(task_id : String) -> String {
  "[\{task_id}] Review starting"
}

///|
/// Format a task completion entry for the orchestrator log.
pub fn format_task_complete_line(task_id : String, status : String) -> String {
  "Task \{task_id} -> \{status}"
}

///|
/// Format a review completion entry for the orchestrator log.
pub fn format_review_complete_line(
  task_id : String,
  verdict : String,
) -> String {
  "Review \{task_id}: \{verdict}"
}

///|
/// Format a phase change entry for the orchestrator log.
pub fn format_phase_change_line(phase : String) -> String {
  "Phase: \{phase}"
}

///|
/// Format the session completion entry for the orchestrator log.
pub fn format_session_complete_line() -> String {
  "[session complete]"
}

///|
/// Format a non-agent CLI log line in a plain TUI-like style.
pub fn format_cli_log_line(level : String, msg : String) -> String {
  match level {
    "WARN" => "Warning: \{msg}"
    "ERROR" => "Error: \{msg}"
    "USAGE" => "Usage: \{msg}"
    "INFO"
    | "BOOT"
    | "RESUME"
    | "HEARTBEAT"
    | "SUMMARY"
    | "REVIEW"
    | "DEV"
    | "SESSION"
    | "SKIP"
    | "EXIT"
    | "USER" => msg
    _ => "[\{level}] \{msg}"
  }
}

///|
fn strip_provider_prefix(line : String) -> String {
  let chars = line.to_array()
  if chars.length() >= 2 && is_provider_marker(chars[0]) && chars[1] == ' ' {
    return String::from_array(chars[2:]).trim().to_string()
  }
  line
}

///|
fn is_provider_marker(ch : Char) -> Bool {
  ch == '⏺' || ch == '•' || ch == '└'
}

///|
fn is_separator_line(line : String) -> Bool {
  let chars = line.to_array()
  if chars.length() < 8 {
    return false
  }
  for ch in chars {
    if ch != '─' && ch != '-' && ch != '=' {
      return false
    }
  }
  true
}

///|
/// Count lines in a string. An empty string has 0 lines.
pub fn count_lines(s : String) -> Int {
  if s.is_empty() {
    return 0
  }
  let mut count = 1
  for c in s {
    if c == '\n' {
      count += 1
    }
  }
  // Don't count trailing newline as an extra line
  if s.length() > 0 && s[s.length() - 1] == '\n' {
    count -= 1
  }
  count
}

///| Format a tool call for human-readable display.

///|
/// Parses the JSON input to extract key fields per tool type.
pub fn format_tool_call(name : String, input_json : String) -> String {
  let json = @json.parse(input_json) catch {
    _ => return "\{name}(\{truncate(input_json, 100)})"
  }
  match json {
    Object(m) =>
      match name {
        "Read" => {
          let path = match m.get("file_path") {
            Some(String(p)) => p
            _ => "?"
          }
          "Read(\{path})"
        }
        "Edit" => {
          let path = match m.get("file_path") {
            Some(String(p)) => p
            _ => "?"
          }
          let old_str = match m.get("old_string") {
            Some(String(s)) => truncate(s.trim().to_string(), 60)
            _ => ""
          }
          let new_str = match m.get("new_string") {
            Some(String(s)) => truncate(s.trim().to_string(), 60)
            _ => ""
          }
          "Edit(\{path})\n           old: \{old_str}\n           new: \{new_str}"
        }
        "Write" => {
          let path = match m.get("file_path") {
            Some(String(p)) => p
            _ => "?"
          }
          let content_len = match m.get("content") {
            Some(String(s)) => s.length()
            _ => 0
          }
          "Write(\{path}, \{content_len} chars)"
        }
        "Bash" => {
          let cmd = match m.get("command") {
            Some(String(c)) => truncate(c, 120)
            _ => "?"
          }
          "Bash(\{cmd})"
        }
        "Glob" => {
          let pattern = match m.get("pattern") {
            Some(String(p)) => p
            _ => "?"
          }
          "Glob(\{pattern})"
        }
        "Grep" => {
          let pattern = match m.get("pattern") {
            Some(String(p)) => p
            _ => "?"
          }
          let path = match m.get("path") {
            Some(String(p)) => " in \{p}"
            _ => ""
          }
          "Grep(\{pattern}\{path})"
        }
        "Task" => {
          let desc = match m.get("description") {
            Some(String(d)) => d
            _ => ""
          }
          let agent = match m.get("subagent_type") {
            Some(String(t)) => t
            _ => "?"
          }
          "Task(\{agent}: \{desc})"
        }
        _ => "\{name}(\{truncate(input_json, 100)})"
      }
    _ => "\{name}(\{truncate(input_json, 100)})"
  }
}

///| Format a tool result for human-readable display.

///|
/// Shows line count for Read/Bash, truncated content for others.
pub fn format_tool_result(name : String, output : String) -> String {
  match name {
    "Read" => {
      let line_count = count_lines(output)
      "Read: \{line_count} lines"
    }
    "Bash" => {
      let line_count = count_lines(output)
      if line_count > 3 {
        "Bash: \{line_count} lines"
      } else {
        "Bash: \{output}"
      }
    }
    "Edit" => "Edit: \{output}"
    "Write" => "Write: \{output}"
    "Glob" => "Glob: \{output}"
    "Grep" => "Grep: \{output}"
    _ => "\{name}: \{output}"
  }
}
