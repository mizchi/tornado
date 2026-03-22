///|
/// Manages milestones and their tasks for the ralph loop
pub struct MilestoneManager {
  milestones : Array[@types.Milestone]
  mut next_task_id : Int
  brief : String
}

///|
/// Create an empty milestone manager
pub fn MilestoneManager::new() -> MilestoneManager {
  { milestones: [], next_task_id: 1, brief: "" }
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
    Object(map) => {
      let brief = match map.get("brief") {
        Some(String(s)) => s
        _ => ""
      }
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
      { milestones, next_task_id: max_id + 1, brief }
    }
    _ => raise Failure::Failure("Milestones must be a JSON object")
  }
}

///|
/// Serialize milestones to JSON string
pub fn MilestoneManager::to_json(self : MilestoneManager) -> String {
  let parts : Array[String] = []
  for m in self.milestones {
    parts.push(milestone_to_json(m))
  }
  "{\"brief\":" +
  json_escape(self.brief) +
  ",\"milestones\":[" +
  join_strings(parts, ",") +
  "]}"
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
  let status : @types.MilestoneStatus = match status_str {
    "in_progress" => InProgress
    "done" => Done
    "failed" => Failed("unknown")
    _ => Pending
  }
  let tasks : Array[@types.RalphTask] = []
  let current_wave = get_num(json, "current_wave", 0)
  let summary = get_str(json, "summary", "")
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
  { id, goal, status, tasks, current_wave, summary }
}

///|
fn parse_ralph_task(json : Json) -> @types.RalphTask {
  let id = get_str(json, "id", "")
  let description = get_str(json, "description", "")
  let wave = get_num(json, "wave", 0)
  let status_str = get_str(json, "status", "pending")
  let status : @types.TaskStatus = match status_str {
    "in_progress" => Pending
    "done" => Done
    "failed" => Failed("unknown")
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
  "\",\"current_wave\":" +
  m.current_wave.to_string() +
  ",\"tasks\":" +
  tasks_json +
  ",\"summary\":" +
  json_escape(m.summary) +
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
  "\",\"result\":" +
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
  let buf = StringBuilder::new()
  buf.write_char('"')
  for ch in s {
    match ch {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\t' => buf.write_string("\\t")
      _ => buf.write_char(ch)
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
    // Stop at "---" separator only after we've found tasks
    if is_separator(trimmed) && tasks.length() > 0 {
      break
    }
    // Strip markdown formatting before checking wave prefix
    let stripped = strip_markdown_prefix(trimmed)
    // Check for "WAVE N:" header
    if has_wave_prefix(stripped) {
      let num = parse_wave_number(stripped)
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
  if not(remaining.is_empty()) {
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
fn is_separator(s : String) -> Bool {
  let chars = s.to_array()
  if chars.length() < 3 {
    return false
  }
  for ch in chars {
    if ch != '-' {
      return false
    }
  }
  true
}

///|
fn strip_markdown_prefix(s : String) -> String {
  let mut result = s
  // Strip leading "## ", "# ", etc.
  while result.has_prefix("#") {
    result = trim(String::from_array(result.to_array()[1:]))
  }
  // Strip bold markers "**"
  while result.has_prefix("**") {
    result = String::from_array(result.to_array()[2:])
  }
  result
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
