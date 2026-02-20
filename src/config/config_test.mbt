test "ProjectConfig::from_json_string parses basic config" {
  let json =
    #|{
    #|  "project_dir": "/tmp/project",
    #|  "review_dir": "reviews",
    #|  "max_review_cycles": 5,
    #|  "agents": [
    #|    { "id": "dev-1", "kind": "claude-code", "role": "dev" },
    #|    { "id": "review-1", "kind": "api", "role": "review", "model": "claude-sonnet" }
    #|  ]
    #|}
  let config = @config.ProjectConfig::from_json_string(json)
  inspect(config.project_dir, content="/tmp/project")
  inspect(config.review_dir, content="reviews")
  inspect(config.max_review_cycles, content="5")
  assert_true(config.agents.length() == 2)
  inspect(config.agents[0].id, content="dev-1")
  inspect(config.agents[0].kind, content="ClaudeCode")
  inspect(config.agents[0].role, content="Dev")
  inspect(config.agents[1].id, content="review-1")
  inspect(config.agents[1].kind, content="Api")
  inspect(config.agents[1].role, content="Review")
  inspect(config.agents[1].model, content="Some(\"claude-sonnet\")")
}

test "ProjectConfig::from_json_string with defaults" {
  let json =
    #|{ "agents": [] }
  let config = @config.ProjectConfig::from_json_string(json)
  inspect(config.project_dir, content=".")
  inspect(config.review_dir, content="docs/reviews")
  inspect(config.max_review_cycles, content="3")
  inspect(config.review_interval, content="1")
}

test "ProjectConfig::default" {
  let config = @config.ProjectConfig::default()
  inspect(config.project_dir, content=".")
  assert_true(config.agents.is_empty())
}

test "ProjectConfig::validate detects no agents" {
  let config = @config.ProjectConfig::default()
  let errors = config.validate()
  assert_true(errors.length() > 0)
  assert_true(errors[0].contains("No agents"))
}

test "ProjectConfig::validate detects duplicate ids" {
  let json =
    #|{
    #|  "agents": [
    #|    { "id": "dev-1", "kind": "claude-code", "role": "dev" },
    #|    { "id": "dev-1", "kind": "claude-code", "role": "dev" }
    #|  ]
    #|}
  let config = @config.ProjectConfig::from_json_string(json)
  let errors = config.validate()
  assert_true(errors.iter().any(fn(e) { e.contains("Duplicate") }))
}

test "ProjectConfig::validate passes with valid config" {
  let json =
    #|{
    #|  "agents": [
    #|    { "id": "dev-1", "kind": "claude-code", "role": "dev" }
    #|  ]
    #|}
  let config = @config.ProjectConfig::from_json_string(json)
  let errors = config.validate()
  assert_true(errors.is_empty())
}

test "ProjectConfig::from_json_string invalid json" {
  let mut caught = false
  try {
    ignore(@config.ProjectConfig::from_json_string("not json"))
  } catch {
    _ => caught = true
  }
  assert_true(caught)
}

test "parse warns on unknown agent kind" {
  let json =
    #|{
    #|  "agents": [
    #|    { "id": "dev-1", "kind": "claude_code", "role": "dev" }
    #|  ]
    #|}
  let config = @config.ProjectConfig::from_json_string(json)
  // Unknown kind "claude_code" (underscore) should generate a warning
  assert_true(config.parse_warnings.length() == 1)
  assert_true(config.parse_warnings[0].contains("unknown kind"))
  assert_true(config.parse_warnings[0].contains("claude_code"))
  // Should default to Mock
  inspect(config.agents[0].kind, content="Mock")
}

test "parse warns on unknown agent role" {
  let json =
    #|{
    #|  "agents": [
    #|    { "id": "dev-1", "kind": "claude-code", "role": "reviewer" }
    #|  ]
    #|}
  let config = @config.ProjectConfig::from_json_string(json)
  // Unknown role "reviewer" (should be "review") generates a warning
  assert_true(config.parse_warnings.length() == 1)
  assert_true(config.parse_warnings[0].contains("unknown role"))
  assert_true(config.parse_warnings[0].contains("reviewer"))
  // Should default to Dev
  inspect(config.agents[0].role, content="Dev")
}

test "parse warns on both unknown kind and role" {
  let json =
    #|{
    #|  "agents": [
    #|    { "id": "agent-1", "kind": "openai", "role": "coder" }
    #|  ]
    #|}
  let config = @config.ProjectConfig::from_json_string(json)
  assert_true(config.parse_warnings.length() == 2)
  assert_true(config.parse_warnings[0].contains("unknown kind"))
  assert_true(config.parse_warnings[1].contains("unknown role"))
}

test "validate includes parse warnings" {
  let json =
    #|{
    #|  "agents": [
    #|    { "id": "dev-1", "kind": "typo", "role": "dev" }
    #|  ]
    #|}
  let config = @config.ProjectConfig::from_json_string(json)
  let errors = config.validate()
  // Should contain the parse warning about unknown kind
  assert_true(errors.iter().any(fn(e) { e.contains("unknown kind") }))
  assert_true(errors.iter().any(fn(e) { e.contains("typo") }))
}

test "valid kind and role produce no warnings" {
  let json =
    #|{
    #|  "agents": [
    #|    { "id": "dev-1", "kind": "claude-code", "role": "dev" },
    #|    { "id": "rev-1", "kind": "codex", "role": "review" },
    #|    { "id": "api-1", "kind": "api", "role": "orchestrator" },
    #|    { "id": "test-1", "kind": "mock", "role": "dev" }
    #|  ]
    #|}
  let config = @config.ProjectConfig::from_json_string(json)
  assert_true(config.parse_warnings.is_empty())
}

test "ProjectConfig::from_json_string parses review_interval" {
  let json =
    #|{
    #|  "review_interval": 3,
    #|  "agents": [
    #|    { "id": "dev-1", "kind": "claude-code", "role": "dev" }
    #|  ]
    #|}
  let config = @config.ProjectConfig::from_json_string(json)
  inspect(config.review_interval, content="3")
}

test "ProjectConfig::validate rejects review_interval < 1" {
  let json =
    #|{
    #|  "review_interval": 0,
    #|  "agents": [
    #|    { "id": "dev-1", "kind": "claude-code", "role": "dev" }
    #|  ]
    #|}
  let config = @config.ProjectConfig::from_json_string(json)
  let errors = config.validate()
  assert_true(errors.iter().any(fn(e) { e.contains("review_interval") }))
}

test "valid config parse_warnings is empty" {
  let json =
    #|{
    #|  "agents": [
    #|    { "id": "dev-1", "kind": "claude-code", "role": "dev" }
    #|  ]
    #|}
  let config = @config.ProjectConfig::from_json_string(json)
  assert_true(config.parse_warnings.is_empty())
  let errors = config.validate()
  assert_true(errors.is_empty())
}
