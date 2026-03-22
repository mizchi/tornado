// Pure helper functions extracted from main.mbt for testability.
// These functions have NO FFI dependencies.

///|
/// Resolve --lang flag: None/"auto" -> detect via detect_fn, otherwise use as-is
pub fn resolve_lang(cli_lang : String?, detect_fn : () -> String) -> String {
  match cli_lang {
    None => detect_fn()
    Some("auto") => detect_fn()
    Some(lang) => lang
  }
}

///|
/// Extract embedded [TS:HH:MM:SS] prefix from a message.
/// Returns (timestamp, remaining_message). If no prefix found, calls fallback_ts.
pub fn extract_event_ts(
  msg : String,
  fallback_ts : () -> String,
) -> (String, String) {
  if msg.has_prefix("[TS:") {
    let mut end = 4
    while end < msg.length() && msg[end] != ']'.to_int().to_uint16() {
      end = end + 1
    }
    if end < msg.length() {
      let ts = msg.unsafe_substring(start=4, end~)
      let rest_start = if end + 2 <= msg.length() { end + 2 } else { end + 1 }
      let rest = msg.unsafe_substring(start=rest_start, end=msg.length())
      return (ts, rest)
    }
  }
  (fallback_ts(), msg)
}

///|
/// Derive archive path: "TODO.md" -> "TODO.archive.md", "plan" -> "plan.archive.md"
pub fn derive_archive_path(plan_path : String) -> String {
  if plan_path.has_suffix(".md") && plan_path.length() > 3 {
    let buf = StringBuilder::new()
    let mut i = 0
    let stop = plan_path.length() - 3
    for ch in plan_path {
      if i >= stop {
        break
      }
      buf.write_char(ch)
      i += 1
    }
    buf.write_string(".archive.md")
    buf.to_string()
  } else {
    plan_path + ".archive.md"
  }
}

///|
/// Combine multiple dev outputs into a structured summary
pub fn join_dev_outputs(outputs : Array[String]) -> String {
  let buf = StringBuilder::new()
  let mut i = 0
  for output in outputs {
    i += 1
    buf.write_string("### Dev Iteration \{i}\n")
    buf.write_string(output)
    buf.write_string("\n\n")
  }
  buf.to_string()
}

///|
/// Build a human-readable summary of what happened in this cycle
pub fn build_cycle_summary(
  iteration : Int,
  dev_outputs : Array[String],
  review_summary : String,
) -> String {
  let buf = StringBuilder::new()
  buf.write_string("## Cycle \{iteration} Summary\n\n")
  let mut i = 0
  for output in dev_outputs {
    i += 1
    buf.write_string("### Dev Step \{i}\n")
    buf.write_string(truncate_str(output, 1000))
    buf.write_string("\n\n")
  }
  if not(review_summary.is_empty()) {
    buf.write_string("### Review\n")
    buf.write_string(truncate_str(review_summary, 500))
    buf.write_string("\n")
  }
  buf.to_string()
}

///|
/// Build a task prompt that directs the agent to read/write the plan file
pub fn build_plan_file_task(
  plan_path : String,
  review_summary : String,
  context : String,
) -> String {
  let buf = StringBuilder::new()
  buf.write_string("You are in an autonomous development loop.\n\n")
  buf.write_string("## Plan File: \{plan_path}\n")
  buf.write_string("Read this file to see your current task list.\n\n")
  buf.write_string("## Instructions\n")
  buf.write_string("1. Read `\{plan_path}` to understand the current tasks\n")
  buf.write_string(
    "2. Pick the highest-priority uncompleted task and implement it\n",
  )
  buf.write_string(
    "3. After completing work, update `\{plan_path}` to mark the task as done\n",
  )
  let archive_path = derive_archive_path(plan_path)
  buf.write_string(
    "4. If the file has many completed items (10+), archive them to `\{archive_path}`\n\n",
  )
  if not(review_summary.is_empty()) {
    buf.write_string("## Review Feedback\n")
    buf.write_string(truncate_str(review_summary, 2000))
    buf.write_string("\n\n")
  }
  if not(context.is_empty()) {
    buf.write_string("## Current Project State\n")
    buf.write_string(context)
  }
  buf.to_string()
}

///|
/// Build improvement loop prompt for --rlm mode
pub fn build_improvement_task(
  prev_output : String,
  current_step : Int,
  total_steps : Int,
  cycle_summary : String,
  context : String,
) -> String {
  let buf = StringBuilder::new()
  buf.write_string("You are in an autonomous IMPROVEMENT loop.\n")
  buf.write_string(
    "Budget: iteration \{current_step}/\{total_steps} before next review.\n\n",
  )
  if not(cycle_summary.is_empty()) {
    buf.write_string("## Previous Cycle Summary\n")
    buf.write_string(cycle_summary)
    buf.write_string("\n\n")
  }
  if not(context.is_empty()) {
    buf.write_string("## Current Project State\n")
    buf.write_string(context)
    buf.write_string("\n")
  }
  if not(prev_output.is_empty()) {
    buf.write_string("## Previous Iteration Output\n")
    buf.write_string(truncate_str(prev_output, 2000))
    buf.write_string("\n\n")
  }
  buf.write_string("## Improvement Protocol\n")
  buf.write_string(
    "1. **Measure Baseline**: Run tests, record pass/fail counts, build status, coverage\n",
  )
  buf.write_string(
    "2. **Make ONE Focused Improvement**: Choose exactly one of: fix / test / refactor / optimize\n",
  )
  buf.write_string(
    "3. **Validate**: Re-run tests, compare with baseline. No regression + improvement = ACCEPTABLE\n",
  )
  buf.write_string(
    "4. **Commit or Revert**: If acceptable, commit with descriptive message. Otherwise `git checkout .`\n",
  )
  buf.write_string(
    "5. **Report**: Output a structured summary in this format:\n\n",
  )
  buf.write_string("```\n")
  buf.write_string("IMPROVEMENT_REPORT:\n")
  buf.write_string("  type: <fix|test|refactor|optimize>\n")
  buf.write_string("  baseline: tests=N/N, build=ok|fail\n")
  buf.write_string("  result: tests=N/N, build=ok|fail\n")
  buf.write_string("  verdict: committed|reverted\n")
  buf.write_string("  summary: <one-line description of what changed>\n")
  buf.write_string("```\n")
  buf.to_string()
}

// ── Session persistence (pure JSON logic) ────────────────────

///|
/// Persisted session state
pub(all) struct SessionState {
  iteration : Int
  phase : String
  task : String
  dev_output : String
  review_summary : String
  agent_sessions : Map[String, String]
  dev_since_review : Int
  accumulated_dev_outputs : Array[String]
} derive(Show)

///|
/// Serialize session state to JSON string
pub fn session_to_json(state : SessionState) -> String {
  let sessions_map : Map[String, Json] = {}
  for entry in state.agent_sessions {
    sessions_map[entry.0] = entry.1.to_json()
  }
  let obj : Map[String, Json] = {}
  obj["iteration"] = state.iteration.to_json()
  obj["phase"] = state.phase.to_json()
  obj["task"] = state.task.to_json()
  obj["dev_output"] = state.dev_output.to_json()
  obj["review_summary"] = state.review_summary.to_json()
  obj["agent_sessions"] = Json::object(sessions_map)
  obj["dev_since_review"] = state.dev_since_review.to_json()
  obj["accumulated_dev_outputs"] = state.accumulated_dev_outputs.to_json()
  Json::object(obj).stringify()
}

///|
/// Parse session state from JSON string
pub fn session_from_json(content : String) -> SessionState? {
  let json = @json.parse(content) catch { _ => return None }
  match json {
    Object(map) => {
      let iteration = match map.get("iteration") {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
      let phase = match map.get("phase") {
        Some(String(s)) => s
        _ => "idle"
      }
      let task = match map.get("task") {
        Some(String(s)) => s
        _ => ""
      }
      let dev_output = match map.get("dev_output") {
        Some(String(s)) => s
        _ => ""
      }
      let review_summary = match map.get("review_summary") {
        Some(String(s)) => s
        _ => ""
      }
      let agent_sessions : Map[String, String] = {}
      match map.get("agent_sessions") {
        Some(Object(sessions)) =>
          for entry in sessions {
            match entry.1 {
              String(sid) => agent_sessions[entry.0] = sid
              _ => ()
            }
          }
        _ => ()
      }
      let dev_since_review = match map.get("dev_since_review") {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
      let accumulated_dev_outputs : Array[String] = []
      match map.get("accumulated_dev_outputs") {
        Some(Array(arr)) =>
          for item in arr {
            match item {
              String(s) => accumulated_dev_outputs.push(s)
              _ => ()
            }
          }
        _ => ()
      }
      Some({
        iteration,
        phase,
        task,
        dev_output,
        review_summary,
        agent_sessions,
        dev_since_review,
        accumulated_dev_outputs,
      })
    }
    _ => None
  }
}

// ── Simple agent lookup (FFI-free) ───────────────────────────

///|
/// Minimal agent descriptor for find_agent_id (avoids @types dependency)
pub(all) struct SimpleAgent {
  id : String
  kind : String
  role : String
} derive(Show)

///|
/// Find agent id by role string
pub fn find_agent_id(agents : Array[SimpleAgent], role : String) -> String? {
  for agent in agents {
    if agent.role == role {
      return Some(agent.id)
    }
  }
  None
}

// ── Internal helper ──────────────────────────────────────────

///|
/// Truncate string to max length, adding "..." if truncated
fn truncate_str(s : String, max : Int) -> String {
  if s.length() <= max {
    s
  } else {
    let buf = StringBuilder::new()
    let mut i = 0
    for ch in s {
      if i >= max {
        break
      }
      buf.write_char(ch)
      i += 1
    }
    buf.write_string("...")
    buf.to_string()
  }
}
