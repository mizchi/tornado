///| Project configuration
pub(all) struct ProjectConfig {
  project_dir : String
  review_dir : String
  max_review_cycles : Int
  agents : Array[@types.AgentConfig]
  parse_warnings : Array[String]
}

///| Known valid agent kind strings
let valid_agent_kinds : Array[String] = [
  "claude-code", "codex", "api", "mock",
]

///| Known valid agent role strings
let valid_agent_roles : Array[String] = ["dev", "review", "orchestrator"]

///| Parse AgentKind from string
fn parse_agent_kind(s : String) -> @types.AgentKind {
  match s {
    "claude-code" => ClaudeCode
    "codex" => Codex
    "api" => Api
    _ => Mock
  }
}

///| Parse AgentRole from string
fn parse_agent_role(s : String) -> @types.AgentRole {
  match s {
    "dev" => Dev
    "review" => Review
    "orchestrator" => Orchestrator
    _ => Dev
  }
}

///| Get a string from a JSON object
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

///| Get an int from a JSON object
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

///| Get an optional string from a JSON object
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

///| Parse a single agent config from JSON, collecting warnings for unknown values
fn parse_agent_config(
  json : Json,
  warnings : Array[String],
) -> @types.AgentConfig {
  let id = get_string(json, "id", "")
  let kind_str = get_string(json, "kind", "mock")
  if not(valid_agent_kinds.contains(kind_str)) {
    warnings.push(
      "Agent '\{id}': unknown kind '\{kind_str}', defaulting to Mock",
    )
  }
  let kind = parse_agent_kind(kind_str)
  let role_str = get_string(json, "role", "dev")
  if not(valid_agent_roles.contains(role_str)) {
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

///| Parse project config from JSON string
pub fn ProjectConfig::from_json_string(
  s : String,
) -> ProjectConfig raise Failure {
  let json = @json.parse(s) catch {
    err => raise Failure::Failure("Invalid JSON: \{err}")
  }
  ProjectConfig::from_json(json)
}

///| Parse project config from Json value
pub fn ProjectConfig::from_json(json : Json) -> ProjectConfig raise Failure {
  match json {
    Object(map) => {
      let project_dir = get_string(json, "project_dir", ".")
      let review_dir = get_string(json, "review_dir", "docs/reviews")
      let max_review_cycles = get_int(json, "max_review_cycles", 3)
      let agents : Array[@types.AgentConfig] = []
      let parse_warnings : Array[String] = []
      match map.get("agents") {
        Some(Array(arr)) =>
          for item in arr {
            agents.push(parse_agent_config(item, parse_warnings))
          }
        _ => ()
      }
      { project_dir, review_dir, max_review_cycles, agents, parse_warnings }
    }
    _ => raise Failure::Failure("Config must be a JSON object")
  }
}

///| Create a default config (empty agents)
pub fn ProjectConfig::default() -> ProjectConfig {
  {
    project_dir: ".",
    review_dir: "docs/reviews",
    max_review_cycles: 3,
    agents: [],
    parse_warnings: [],
  }
}

///| Preset: dev=claude-code, review=codex
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
    agents: [dev, reviewer],
    parse_warnings: [],
  }
}

///| Validate the config. Returns errors and parse warnings.
pub fn ProjectConfig::validate(self : ProjectConfig) -> Array[String] {
  let errors : Array[String] = []
  // Include any parse warnings (unknown kind/role values)
  for w in self.parse_warnings {
    errors.push(w)
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
  if not(has_dev) && not(self.agents.is_empty()) {
    errors.push("No dev agent configured")
  }
  errors
}
