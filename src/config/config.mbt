///| Project configuration
pub(all) struct ProjectConfig {
  project_dir : String
  review_dir : String
  max_review_cycles : Int
  agents : Array[@types.AgentConfig]
}

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

///| Parse a single agent config from JSON
fn parse_agent_config(json : Json) -> @types.AgentConfig {
  let id = get_string(json, "id", "")
  let kind = parse_agent_kind(get_string(json, "kind", "mock"))
  let role = parse_agent_role(get_string(json, "role", "dev"))
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
    Object(_) => {
      let project_dir = get_string(json, "project_dir", ".")
      let review_dir = get_string(json, "review_dir", "docs/reviews")
      let max_review_cycles = get_int(json, "max_review_cycles", 3)
      let agents : Array[@types.AgentConfig] = []
      match json {
        Object(map) =>
          match map.get("agents") {
            Some(Array(arr)) =>
              for item in arr {
                agents.push(parse_agent_config(item))
              }
            _ => ()
          }
        _ => ()
      }
      { project_dir, review_dir, max_review_cycles, agents }
    }
    _ => raise Failure::Failure("Config must be a JSON object")
  }
}

///| Create a default config (empty agents)
pub fn ProjectConfig::default() -> ProjectConfig {
  { project_dir: ".", review_dir: "docs/reviews", max_review_cycles: 3, agents: [] }
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
  }
}

///| Validate the config
pub fn ProjectConfig::validate(self : ProjectConfig) -> Array[String] {
  let errors : Array[String] = []
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
