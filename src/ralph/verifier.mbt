///| Verifier agent for the ralph loop
pub struct VerifierAgent {
  agent_id : String
  lang : String
}

///| Create a new verifier agent
pub fn VerifierAgent::new(
  agent_id~ : String = "verifier",
  lang~ : String = "en",
) -> VerifierAgent {
  { agent_id, lang }
}

///| Build the verification prompt
pub fn VerifierAgent::build_verify_prompt(
  self : VerifierAgent,
  milestone : @types.Milestone,
  wave : Int,
  wave_results : Array[(String, String)],
  project_context : String,
) -> String {
  let lang_instruction = if self.lang == "ja" {
    "Respond in Japanese."
  } else {
    "Respond in English."
  }
  let buf = StringBuilder::new()
  buf.write_string("You are a Verifier agent. ")
  buf.write_string(lang_instruction)
  buf.write_string("\n\n")
  buf.write_string("## Milestone\n")
  buf.write_string("ID: ")
  buf.write_string(milestone.id)
  buf.write_string("\nGoal: ")
  buf.write_string(milestone.goal)
  buf.write_string("\nWave: ")
  buf.write_string(wave.to_string())
  buf.write_string("\n\n")
  if not(project_context.is_empty()) {
    buf.write_string("## Project Context\n")
    buf.write_string(project_context)
    buf.write_string("\n\n")
  }
  buf.write_string("## Wave Results\n")
  for pair in wave_results {
    buf.write_string("### Task: ")
    buf.write_string(pair.0)
    buf.write_string("\n")
    buf.write_string(pair.1)
    buf.write_string("\n\n")
  }
  buf.write_string(
    "## Instructions\n" +
    "Verify that all tasks in this wave were completed correctly.\n" +
    "Check code quality, correctness, and alignment with the milestone goal.\n\n" +
    "## Output Format\n" +
    "Use exactly one of these tags:\n" +
    "- <wave_approved> if all tasks pass verification\n" +
    "- <needs_rework>task_id: reason</needs_rework> for tasks that need fixes\n" +
    "- <milestone_failed>reason</milestone_failed> if the milestone cannot be achieved\n",
  )
  buf.to_string()
}

///| Parse verifier output into a verdict
pub fn VerifierAgent::parse_verdict(
  _self : VerifierAgent,
  output : String,
) -> @types.VerifierVerdict {
  // Check for <milestone_failed>
  let failed_content = extract_tag(output, "milestone_failed")
  if not(failed_content.is_empty()) {
    return MilestoneFailed(failed_content)
  }
  // Check for <needs_rework>
  let rework_content = extract_tag(output, "needs_rework")
  if not(rework_content.is_empty()) {
    let items = split_rework_items(rework_content)
    return NeedsRework(items)
  }
  // Check for <wave_approved>
  if output.contains("<wave_approved>") {
    return Approved
  }
  // Default to approved if no tags found
  Approved
}

///| Run the verifier agent
pub fn VerifierAgent::verify(
  self : VerifierAgent,
  milestone : @types.Milestone,
  wave : Int,
  wave_results : Array[(String, String)],
  backend : @agent.BoxedBackend,
  project_context : String,
  on_event~ : (@types.AgentEvent) -> Unit = fn(_e) {  },
) -> @types.VerifierVerdict {
  let prompt = self.build_verify_prompt(
    milestone, wave, wave_results, project_context,
  )
  let system_prompt = "You are a verification agent that checks task completion quality."
  let result = backend.run(prompt, system_prompt, on_event)
  match result.status {
    Completed => self.parse_verdict(result.content)
    _ => Approved // If verifier fails, default to approved
  }
}

// --- Internal helpers ---

///| Extract content between <tag> and </tag>
fn extract_tag(s : String, tag : String) -> String {
  let open = "<" + tag + ">"
  let close = "</" + tag + ">"
  let open_idx = find_substring(s, open)
  if open_idx < 0 {
    return ""
  }
  let start = open_idx + open.length()
  let close_idx = find_substring_from(s, close, start)
  if close_idx < 0 {
    // No closing tag, take rest of string
    return trim(substring(s, start, s.to_array().length()))
  }
  trim(substring(s, start, close_idx))
}

///| Split rework items by newline
fn split_rework_items(s : String) -> Array[String] {
  let items : Array[String] = []
  let lines = split_lines(s)
  for line in lines {
    let trimmed = trim(line)
    if not(trimmed.is_empty()) {
      items.push(trimmed)
    }
  }
  if items.is_empty() {
    items.push(s)
  }
  items
}

fn find_substring(haystack : String, needle : String) -> Int {
  let h = haystack.to_array()
  let n = needle.to_array()
  if n.length() > h.length() {
    return -1
  }
  for i = 0; i <= h.length() - n.length(); i = i + 1 {
    let mut found = true
    for j = 0; j < n.length(); j = j + 1 {
      if h[i + j] != n[j] {
        found = false
        break
      }
    }
    if found {
      return i
    }
  }
  -1
}

fn find_substring_from(haystack : String, needle : String, from : Int) -> Int {
  let h = haystack.to_array()
  let n = needle.to_array()
  if from + n.length() > h.length() {
    return -1
  }
  for i = from; i <= h.length() - n.length(); i = i + 1 {
    let mut found = true
    for j = 0; j < n.length(); j = j + 1 {
      if h[i + j] != n[j] {
        found = false
        break
      }
    }
    if found {
      return i
    }
  }
  -1
}

fn substring(s : String, start : Int, end : Int) -> String {
  let chars = s.to_array()
  let actual_start = if start < 0 { 0 } else { start }
  let actual_end = if end > chars.length() { chars.length() } else { end }
  if actual_start >= actual_end {
    return ""
  }
  String::from_array(chars[actual_start:actual_end])
}
