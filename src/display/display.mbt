///| Truncate long text for display, adding "..." if truncated
pub fn truncate(s : String, max : Int) -> String {
  if s.length() <= max {
    s
  } else {
    s.view(start_offset=0, end_offset=max).to_string() + "..."
  }
}

///| Count lines in a string. An empty string has 0 lines.
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
///| Parses the JSON input to extract key fields per tool type.
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
///| Shows line count for Read/Bash, truncated content for others.
pub fn format_tool_result(name : String, output : String) -> String {
  match name {
    "Read" => {
      let line_count = count_lines(output)
      "Read: \{line_count} lines"
    }
    "Edit" => "Edit: \{truncate(output, 80)}"
    "Write" => "Write: \{truncate(output, 80)}"
    "Bash" => {
      let line_count = count_lines(output)
      if line_count > 3 {
        "Bash: \{line_count} lines"
      } else {
        "Bash: \{truncate(output, 120)}"
      }
    }
    "Glob" => "Glob: \{truncate(output, 120)}"
    "Grep" => "Grep: \{truncate(output, 120)}"
    _ => "\{name}: \{truncate(output, 120)}"
  }
}
