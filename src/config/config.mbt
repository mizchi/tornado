///|
/// Project configuration
pub(all) struct ProjectConfig {
  project_dir : String
  review_dir : String
  max_review_cycles : Int
  review_interval : Int
  agents : Array[@types.AgentConfig]
  parse_warnings : Array[String]
  ralph_enabled : Bool
  milestones_path : String?
  max_rework_attempts : Int
}

///|
/// Known valid agent kind strings
let valid_agent_kinds : Array[String] = ["claude-code", "codex", "api", "mock"]

///|
/// Known valid agent role strings
let valid_agent_roles : Array[String] = [
  "dev", "builder", "review", "orchestrator", "planner", "verifier",
]

///|
/// Parse AgentKind from string
fn parse_agent_kind(s : String) -> @types.AgentKind {
  match s {
    "claude-code" => ClaudeCode
    "codex" => Codex
    "api" => Api
    _ => Mock
  }
}

///|
/// Parse AgentRole from string
fn parse_agent_role(s : String) -> @types.AgentRole {
  match s {
    "dev" | "builder" => Dev
    "review" => Review
    "orchestrator" => Orchestrator
    "planner" => Planner
    "verifier" => Verifier
    _ => Dev
  }
}

///|
/// Get a string from a JSON object
fn get_string(json : Json, key : String, default : String) -> String {
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
/// Get an int from a JSON object
fn get_int(json : Json, key : String, default : Int) -> Int {
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
/// Get a bool from a JSON object
fn get_bool(json : Json, key : String, default : Bool) -> Bool {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(True) => true
        Some(False) => false
        _ => default
      }
    _ => default
  }
}

///|
/// Get an optional string from a JSON object
fn get_string_opt(json : Json, key : String) -> String? {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(String(s)) => Some(s)
        _ => None
      }
    _ => None
  }
}

///|
/// Parse a single agent config from JSON, collecting warnings for unknown values
fn parse_agent_config(
  json : Json,
  warnings : Array[String],
) -> @types.AgentConfig {
  let id = get_string(json, "id", "")
  let kind_str = get_string(json, "kind", "mock")
  if !(valid_agent_kinds.contains(kind_str)) {
    warnings.push(
      "Agent '\{id}': unknown kind '\{kind_str}', defaulting to Mock",
    )
  }
  let kind = parse_agent_kind(kind_str)
  let role_str = get_string(json, "role", "dev")
  if !(valid_agent_roles.contains(role_str)) {
    warnings.push(
      "Agent '\{id}': unknown role '\{role_str}', defaulting to Dev",
    )
  }
  let role = parse_agent_role(role_str)
  let model = get_string_opt(json, "model")
  let system_prompt = get_string_opt(json, "system_prompt")
  let working_dir = get_string(json, "working_dir", ".")
  let max_iterations = get_int(json, "max_iterations", 10)
  { id, kind, role, model, system_prompt, working_dir, max_iterations }
}

///|
/// Parse project config from JSON string
pub fn ProjectConfig::from_json_string(
  s : String,
) -> ProjectConfig raise Failure {
  let json = @json.parse(s) catch {
    err => raise Failure::Failure("Invalid JSON: \{err}")
  }
  ProjectConfig::from_json(json)
}

///|
/// Parse project config from Json value
pub fn ProjectConfig::from_json(json : Json) -> ProjectConfig raise Failure {
  match json {
    Object(map) => {
      let project_dir = get_string(json, "project_dir", ".")
      let review_dir = get_string(json, "review_dir", "docs/reviews")
      let max_review_cycles = get_int(json, "max_review_cycles", 3)
      let review_interval = get_int(json, "review_interval", 1)
      let agents : Array[@types.AgentConfig] = []
      let parse_warnings : Array[String] = []
      match map.get("agents") {
        Some(Array(arr)) =>
          for item in arr {
            agents.push(parse_agent_config(item, parse_warnings))
          }
        _ => ()
      }
      let ralph_enabled = get_bool(json, "ralph_enabled", false)
      let milestones_path = get_string_opt(json, "milestones_path")
      let max_rework_attempts = get_int(json, "max_rework_attempts", 3)
      {
        project_dir,
        review_dir,
        max_review_cycles,
        review_interval,
        agents,
        parse_warnings,
        ralph_enabled,
        milestones_path,
        max_rework_attempts,
      }
    }
    _ => raise Failure::Failure("Config must be a JSON object")
  }
}

///|
/// Create a default config (empty agents)
pub fn ProjectConfig::default() -> ProjectConfig {
  {
    project_dir: ".",
    review_dir: "docs/reviews",
    max_review_cycles: 3,
    review_interval: 1,
    agents: [],
    parse_warnings: [],
    ralph_enabled: false,
    milestones_path: None,
    max_rework_attempts: 3,
  }
}

///|
/// Preset: dev=claude-code, review=codex
pub fn ProjectConfig::preset_default() -> ProjectConfig {
  let dev : @types.AgentConfig = {
    id: "dev",
    kind: ClaudeCode,
    role: Dev,
    model: None,
    system_prompt: None,
    working_dir: ".",
    max_iterations: 10,
  }
  let reviewer : @types.AgentConfig = {
    id: "reviewer",
    kind: Codex,
    role: Review,
    model: None,
    system_prompt: None,
    working_dir: ".",
    max_iterations: 5,
  }
  {
    project_dir: ".",
    review_dir: "docs/reviews",
    max_review_cycles: 2,
    review_interval: 1,
    agents: [dev, reviewer],
    parse_warnings: [],
    ralph_enabled: false,
    milestones_path: None,
    max_rework_attempts: 3,
  }
}

///|
/// Preset for ralph loop: planner=claude-code, builder=claude-code, verifier=codex
pub fn ProjectConfig::preset_ralph() -> ProjectConfig {
  let planner : @types.AgentConfig = {
    id: "planner",
    kind: ClaudeCode,
    role: Planner,
    model: None,
    system_prompt: None,
    working_dir: ".",
    max_iterations: 10,
  }
  let builder : @types.AgentConfig = {
    id: "builder",
    kind: ClaudeCode,
    role: Dev,
    model: None,
    system_prompt: None,
    working_dir: ".",
    max_iterations: 10,
  }
  let verifier : @types.AgentConfig = {
    id: "verifier",
    kind: Codex,
    role: Verifier,
    model: None,
    system_prompt: None,
    working_dir: ".",
    max_iterations: 5,
  }
  {
    project_dir: ".",
    review_dir: "docs/reviews",
    max_review_cycles: 3,
    review_interval: 1,
    agents: [planner, builder, verifier],
    parse_warnings: [],
    ralph_enabled: true,
    milestones_path: None,
    max_rework_attempts: 3,
  }
}

///|
/// Validate the config. Returns errors and parse warnings.
pub fn ProjectConfig::validate(self : ProjectConfig) -> Array[String] {
  let errors : Array[String] = []
  // Include any parse warnings (unknown kind/role values)
  for w in self.parse_warnings {
    errors.push(w)
  }
  if self.review_interval < 1 {
    errors.push("review_interval must be >= 1, got \{self.review_interval}")
  }
  if self.agents.is_empty() {
    errors.push("No agents configured")
  }
  let ids : Map[String, Bool] = {}
  for agent in self.agents {
    if agent.id.is_empty() {
      errors.push("Agent has empty id")
    }
    if ids.get(agent.id) is Some(true) {
      errors.push("Duplicate agent id: \{agent.id}")
    }
    ids[agent.id] = true
  }
  // Check for at least one dev agent
  let has_dev = self.agents.iter().any(fn(a) { a.role == Dev })
  if !(has_dev) && !(self.agents.is_empty()) {
    errors.push("No dev agent configured")
  }
  // Ralph-specific validation
  if self.ralph_enabled {
    let has_planner = self.agents.iter().any(fn(a) { a.role == Planner })
    if !(has_planner) {
      errors.push("Ralph mode requires a planner agent")
    }
  }
  errors
}
