///|
/// Manages milestones and their tasks for the ralph loop
pub struct MilestoneManager {
  milestones : Array[@types.Milestone]
  mut next_task_id : Int
}

///|
/// Create an empty milestone manager
pub fn MilestoneManager::new() -> MilestoneManager {
  { milestones: [], next_task_id: 1 }
}

///|
/// Load milestones from JSON string
pub fn MilestoneManager::load_from_json(
  s : String,
) -> MilestoneManager raise Failure {
  let json = @json.parse(s) catch {
    err => raise Failure::Failure("Invalid milestones JSON: \{err}")
  }
  let milestones : Array[@types.Milestone] = []
  let mut max_id = 0
  match json {
    Object(map) =>
      match map.get("milestones") {
        Some(Array(arr)) =>
          for item in arr {
            let m = parse_milestone(item)
            for t in m.tasks {
              let num = extract_task_num(t.id)
              if num > max_id {
                max_id = num
              }
            }
            milestones.push(m)
          }
        _ => ()
      }
    _ => raise Failure::Failure("Milestones must be a JSON object")
  }
  { milestones, next_task_id: max_id + 1 }
}

///|
/// Serialize milestones to JSON string
pub fn MilestoneManager::to_json(self : MilestoneManager) -> String {
  let parts : Array[String] = []
  for m in self.milestones {
    parts.push(milestone_to_json(m))
  }
  "{\"milestones\":[" + join_strings(parts, ",") + "]}"
}

///|
/// Get the next pending milestone
pub fn MilestoneManager::next_pending_milestone(
  self : MilestoneManager,
) -> @types.Milestone? {
  for m in self.milestones {
    if m.status == @types.MilestoneStatus::Pending ||
      m.status == @types.MilestoneStatus::InProgress {
      return Some(m)
    }
  }
  None
}

///|
/// Get all tasks in a specific wave
pub fn MilestoneManager::get_wave_tasks(
  _self : MilestoneManager,
  milestone : @types.Milestone,
  wave : Int,
) -> Array[@types.RalphTask] {
  let result : Array[@types.RalphTask] = []
  for t in milestone.tasks {
    if t.wave == wave {
      result.push(t)
    }
  }
  result
}

///|
/// Check if milestone has undone tasks (Pending, InProgress, or Failed)
pub fn MilestoneManager::has_undone_tasks(
  _self : MilestoneManager,
  milestone : @types.Milestone,
) -> Bool {
  milestone.tasks
  .iter()
  .any(fn(t) {
    match t.status {
      Pending | InProgress(_) | Failed(_) => true
      _ => false
    }
  })
}

///|
/// Get the next wave number that has undone tasks (Pending, InProgress, or Failed)
pub fn MilestoneManager::next_wave_number(
  _self : MilestoneManager,
  milestone : @types.Milestone,
) -> Int? {
  let mut min_wave : Int? = None
  for t in milestone.tasks {
    match t.status {
      Pending | InProgress(_) | Failed(_) =>
        match min_wave {
          None => min_wave = Some(t.wave)
          Some(w) => if t.wave < w { min_wave = Some(t.wave) }
        }
      _ => ()
    }
  }
  min_wave
}

///|
/// Check if all milestones are done
pub fn MilestoneManager::all_milestones_done(self : MilestoneManager) -> Bool {
  self.milestones
  .iter()
  .all(fn(m) {
    m.status == @types.MilestoneStatus::Done ||
    m.status is @types.MilestoneStatus::Failed(_)
  })
}

///|
/// Generate a unique task id
pub fn MilestoneManager::gen_task_id(
  self : MilestoneManager,
  milestone_id : String,
) -> String {
  let id = "\{milestone_id}-t\{self.next_task_id}"
  self.next_task_id += 1
  id
}

///|
/// Parse milestone design output in "MILESTONE <id>: <goal>" format
pub fn MilestoneManager::parse_milestone_design(
  _self : MilestoneManager,
  output : String,
) -> Array[@types.Milestone] {
  let milestones : Array[@types.Milestone] = []
  let lines = split_lines(output)
  for line in lines {
    let trimmed = trim(line)
    if trimmed.is_empty() {
      continue
    }
    // Check for "MILESTONE <id>: <goal>" format
    if trimmed.has_prefix("MILESTONE ") {
      let chars = trimmed.to_array()
      let rest = String::from_array(chars[10:]) // after "MILESTONE "
      let colon_idx = find_char(rest, ':')
      if colon_idx >= 0 {
        let rest_chars = rest.to_array()
        let id = trim(String::from_array(rest_chars[:colon_idx]))
        let goal = trim(String::from_array(rest_chars[colon_idx + 1:]))
        if !(id.is_empty()) && !(goal.is_empty()) {
          milestones.push({
            id,
            goal,
            status: @types.MilestoneStatus::Pending,
            tasks: [],
            current_wave: 0,
          })
        }
      }
    }
  }
  milestones
}

///|
/// Add parsed milestones to the manager
pub fn MilestoneManager::add_milestones(
  self : MilestoneManager,
  new_milestones : Array[@types.Milestone],
) -> Unit {
  for m in new_milestones {
    self.milestones.push(m)
  }
}

///|
/// Parse planner output into tasks
pub fn MilestoneManager::parse_planner_output(
  self : MilestoneManager,
  output : String,
  milestone_id : String,
) -> Array[@types.RalphTask] {
  parse_plan_text(self, output, milestone_id)
}

// --- Internal helpers ---

///|
fn parse_milestone(json : Json) -> @types.Milestone {
  let id = get_str(json, "id", "")
  let goal = get_str(json, "goal", "")
  let status_str = get_str(json, "status", "pending")
  let failure_reason = get_str(json, "failure_reason", "unknown")
  let status : @types.MilestoneStatus = match status_str {
    "in_progress" => InProgress
    "done" => Done
    "failed" => Failed(failure_reason)
    _ => Pending
  }
  let tasks : Array[@types.RalphTask] = []
  let current_wave = get_num(json, "current_wave", 0)
  match json {
    Object(map) =>
      match map.get("tasks") {
        Some(Array(arr)) =>
          for item in arr {
            tasks.push(parse_ralph_task(item))
          }
        _ => ()
      }
    _ => ()
  }
  { id, goal, status, tasks, current_wave }
}

///|
fn parse_ralph_task(json : Json) -> @types.RalphTask {
  let id = get_str(json, "id", "")
  let description = get_str(json, "description", "")
  let wave = get_num(json, "wave", 0)
  let status_str = get_str(json, "status", "pending")
  let task_failure_reason = get_str(json, "failure_reason", "unknown")
  let status : @types.TaskStatus = match status_str {
    "in_progress" => InProgress("")
    "done" => Done
    "failed" => Failed(task_failure_reason)
    _ => Pending
  }
  let result : String? = match json {
    Object(map) =>
      match map.get("result") {
        Some(String(s)) => Some(s)
        _ => None
      }
    _ => None
  }
  let plan_doc : String? = match json {
    Object(map) =>
      match map.get("plan_doc") {
        Some(String(s)) => Some(s)
        _ => None
      }
    _ => None
  }
  { id, description, wave, status, result, plan_doc }
}

///|
fn milestone_to_json(m : @types.Milestone) -> String {
  let status_str = match m.status {
    Pending => "pending"
    InProgress => "in_progress"
    Done => "done"
    Failed(_) => "failed"
  }
  let failure_reason = match m.status {
    Failed(reason) => ",\"failure_reason\":" + json_escape(reason)
    _ => ""
  }
  let task_parts : Array[String] = []
  for t in m.tasks {
    task_parts.push(ralph_task_to_json(t))
  }
  let tasks_json = "[" + join_strings(task_parts, ",") + "]"
  "{\"id\":" +
  json_escape(m.id) +
  ",\"goal\":" +
  json_escape(m.goal) +
  ",\"status\":\"" +
  status_str +
  "\"" +
  failure_reason +
  ",\"current_wave\":" +
  m.current_wave.to_string() +
  ",\"tasks\":" +
  tasks_json +
  "}"
}

///|
fn ralph_task_to_json(t : @types.RalphTask) -> String {
  let status_str = match t.status {
    Pending => "pending"
    InProgress(_) => "in_progress"
    Done => "done"
    Failed(_) => "failed"
  }
  let failure_reason = match t.status {
    Failed(reason) => ",\"failure_reason\":" + json_escape(reason)
    _ => ""
  }
  let result_json = match t.result {
    Some(s) => json_escape(s)
    None => "null"
  }
  let plan_doc_json = match t.plan_doc {
    Some(s) => json_escape(s)
    None => "null"
  }
  "{\"id\":" +
  json_escape(t.id) +
  ",\"description\":" +
  json_escape(t.description) +
  ",\"wave\":" +
  t.wave.to_string() +
  ",\"status\":\"" +
  status_str +
  "\"" +
  failure_reason +
  ",\"result\":" +
  result_json +
  ",\"plan_doc\":" +
  plan_doc_json +
  "}"
}

///|
fn join_strings(parts : Array[String], sep : String) -> String {
  let buf = StringBuilder::new()
  for i, part in parts {
    if i > 0 {
      buf.write_string(sep)
    }
    buf.write_string(part)
  }
  buf.to_string()
}

///|
fn json_escape(s : String) -> String {
  let hex = "0123456789abcdef"
  let buf = StringBuilder::new()
  buf.write_char('"')
  for ch in s {
    match ch {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ =>
        if ch.to_int() < 0x20 {
          // Escape control characters as \u00XX per RFC 8259
          let code = ch.to_int()
          let hex_chars = hex.to_array()
          buf.write_string("\\u00")
          buf.write_char(hex_chars[code / 16])
          buf.write_char(hex_chars[code % 16])
        } else {
          buf.write_char(ch)
        }
    }
  }
  buf.write_char('"')
  buf.to_string()
}

///|
fn get_str(json : Json, key : String, default : String) -> String {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(String(s)) => s
        _ => default
      }
    _ => default
  }
}

///|
fn get_num(json : Json, key : String, default : Int) -> Int {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(Number(n, ..)) => n.to_int()
        _ => default
      }
    _ => default
  }
}

///|
fn find_char(s : String, ch : Char) -> Int {
  let chars = s.to_array()
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == ch {
      return i
    }
  }
  -1
}

///|
fn extract_task_num(id : String) -> Int {
  // Extract number after last 't' in id like "m1-t3"
  let chars = id.to_array()
  let mut last_t = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == 't' {
      last_t = i
    }
  }
  if last_t < 0 || last_t + 1 >= chars.length() {
    return 0
  }
  let mut num = 0
  for i = last_t + 1; i < chars.length(); i = i + 1 {
    let ch = chars[i]
    if ch >= '0' && ch <= '9' {
      num = num * 10 + (ch.to_int() - '0'.to_int())
    } else {
      break
    }
  }
  num
}

///|
/// Parse planner text output in WAVE format
fn parse_plan_text(
  mgr : MilestoneManager,
  output : String,
  milestone_id : String,
) -> Array[@types.RalphTask] {
  let tasks : Array[@types.RalphTask] = []
  let mut current_wave = 0
  let lines = split_lines(output)
  for line in lines {
    let trimmed = trim(line)
    if trimmed.is_empty() {
      continue
    }
    // Check for "WAVE N:" header
    if has_wave_prefix(trimmed) {
      let num = parse_wave_number(trimmed)
      if num >= 0 {
        current_wave = num
      }
      continue
    }
    // Check for numbered items: "1. description" or "- description"
    let desc = parse_list_item(trimmed)
    if desc.length() > 0 {
      let id = mgr.gen_task_id(milestone_id)
      tasks.push({
        id,
        description: desc,
        wave: current_wave,
        status: @types.TaskStatus::Pending,
        result: None,
        plan_doc: None,
      })
    }
  }
  tasks
}

///|
fn split_lines(s : String) -> Array[String] {
  let lines : Array[String] = []
  let buf = StringBuilder::new()
  for ch in s {
    if ch == '\n' {
      lines.push(buf.to_string())
      buf.reset()
    } else if ch == '\r' {
      // skip
    } else {
      buf.write_char(ch)
    }
  }
  let remaining = buf.to_string()
  if !(remaining.is_empty()) {
    lines.push(remaining)
  }
  lines
}

///|
fn trim(s : String) -> String {
  let chars = s.to_array()
  let len = chars.length()
  let mut start = 0
  while start < len && (chars[start] == ' ' || chars[start] == '\t') {
    start += 1
  }
  let mut end = len
  while end > start && (chars[end - 1] == ' ' || chars[end - 1] == '\t') {
    end -= 1
  }
  if start >= end {
    return ""
  }
  String::from_array(chars[start:end])
}

///|
fn has_wave_prefix(s : String) -> Bool {
  s.has_prefix("WAVE ") || s.has_prefix("wave ") || s.has_prefix("Wave ")
}

///|
fn parse_wave_number(s : String) -> Int {
  // Extract number after "WAVE "
  let chars = s.to_array()
  let mut i = 5 // after "WAVE "
  let mut num = 0
  let mut found = false
  while i < chars.length() {
    let ch = chars[i]
    if ch >= '0' && ch <= '9' {
      num = num * 10 + (ch.to_int() - '0'.to_int())
      found = true
    } else {
      break
    }
    i += 1
  }
  if found {
    num
  } else {
    -1
  }
}

///|
fn parse_list_item(s : String) -> String {
  let chars = s.to_array()
  let len = chars.length()
  // Check "N. description"
  let mut i = 0
  if i < len && chars[i] >= '0' && chars[i] <= '9' {
    while i < len && chars[i] >= '0' && chars[i] <= '9' {
      i += 1
    }
    if i < len && chars[i] == '.' {
      i += 1
      // skip spaces
      while i < len && chars[i] == ' ' {
        i += 1
      }
      return trim(String::from_array(chars[i:]))
    }
  }
  // Check "- description"
  if len > 1 && chars[0] == '-' && chars[1] == ' ' {
    return trim(String::from_array(chars[2:]))
  }
  ""
}
