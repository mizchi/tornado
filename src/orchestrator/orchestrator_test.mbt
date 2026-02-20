///| Helper to create noop callbacks with phase tracking
fn make_callbacks_with_phases(
  phases : Array[String],
) -> @types.OrchestratorCallbacks {
  let cb = @types.OrchestratorCallbacks::noop()
  { ..cb, on_phase_change: fn(_id, phase) { phases.push(phase.to_string()) } }
}

///| Helper to create a test config with dev and review agents
fn make_test_config() -> @config.ProjectConfig {
  let dev_agent : @types.AgentConfig = {
    id: "dev-1",
    kind: Mock,
    role: Dev,
    model: None,
    system_prompt: None,
    working_dir: ".",
    max_iterations: 10,
  }
  let review_agent : @types.AgentConfig = {
    id: "review-1",
    kind: Mock,
    role: Review,
    model: None,
    system_prompt: None,
    working_dir: ".",
    max_iterations: 10,
  }
  {
    project_dir: ".",
    review_dir: "docs/reviews",
    max_review_cycles: 3,
    agents: [dev_agent, review_agent],
  }
}

///| Helper to create backends map
fn make_backends(
  dev_response : String,
  review_response : String,
) -> Map[String, @agent.BoxedBackend] {
  let dev_mock = @agent.MockBackend::new(default_response=dev_response)
  let review_mock = @agent.MockBackend::new(default_response=review_response)
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["dev-1"] = dev_mock.boxed()
  backends["review-1"] = review_mock.boxed()
  backends
}

test "Orchestrator full cycle with approval" {
  let config = make_test_config()
  let backends = make_backends(
    "1. Create schema\n2. Build handlers",
    "<approved> great work",
  )
  let phases : Array[String] = []
  let callbacks = make_callbacks_with_phases(phases)
  let orch = @orchestrator.Orchestrator::new(config, backends, callbacks)
  let session = @types.Session::new("s1", "Build REST API", config.agents)
  orch.run(session)
  inspect(session.status, content="Completed")
  assert_true(phases.length() >= 4)
  inspect(phases[0], content="Decomposing")
  inspect(phases[1], content="Assigning")
  inspect(phases[2], content="Executing")
  inspect(phases[3], content="Reviewing")
}

test "Orchestrator without review agent" {
  let dev_agent : @types.AgentConfig = {
    id: "dev-1",
    kind: Mock,
    role: Dev,
    model: None,
    system_prompt: None,
    working_dir: ".",
    max_iterations: 10,
  }
  let config : @config.ProjectConfig = {
    project_dir: ".",
    review_dir: "docs/reviews",
    max_review_cycles: 3,
    agents: [dev_agent],
  }
  let dev_mock = @agent.MockBackend::new(
    default_response="1. Task A\n2. Task B",
  )
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["dev-1"] = dev_mock.boxed()
  let phases : Array[String] = []
  let callbacks = make_callbacks_with_phases(phases)
  let orch = @orchestrator.Orchestrator::new(config, backends, callbacks)
  let session = @types.Session::new("s1", "Do something", config.agents)
  orch.run(session)
  inspect(session.status, content="Completed")
  assert_true(not(phases.iter().any(fn(p) { p == "Reviewing" })))
}

test "Orchestrator emits agent events" {
  let config = make_test_config()
  let backends = make_backends("task done", "<approved>")
  let outputs : Array[String] = []
  let cb = @types.OrchestratorCallbacks::noop()
  let callbacks = {
    ..cb,
    on_agent_output: fn(id, line) { outputs.push("\{id}: \{line}") },
  }
  let orch = @orchestrator.Orchestrator::new(config, backends, callbacks)
  let session = @types.Session::new("s1", "Build API", config.agents)
  orch.run(session)
  assert_true(outputs.length() > 0)
}

test "Orchestrator calls on_session_complete" {
  let config = make_test_config()
  let backends = make_backends("done", "<approved>")
  let completed : Array[String] = []
  let cb = @types.OrchestratorCallbacks::noop()
  let callbacks = { ..cb, on_session_complete: fn(id) { completed.push(id) } }
  let orch = @orchestrator.Orchestrator::new(config, backends, callbacks)
  let session = @types.Session::new("s1", "Build API", config.agents)
  orch.run(session)
  assert_true(completed.length() == 1)
  inspect(completed[0], content="s1")
}
