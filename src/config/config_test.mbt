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
