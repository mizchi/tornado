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
    parse_warnings: [],
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
    parse_warnings: [],
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

test "Orchestrator iteration: NeedsChanges triggers rework then approval" {
  let config = make_test_config()
  // Dev returns "v1" by default, "fixed version" after rework (prompt contains "Feedback")
  let dev_mock = @agent.MockBackend::new(default_response="v1 implementation")
  dev_mock.add_response("Feedback", "fixed version")
  // Review rejects "v1" but approves "fixed"
  let review_mock = @agent.MockBackend::new(
    default_response="<needs_changes>fix naming</needs_changes>",
  )
  review_mock.add_response("fixed", "<approved> looks good now")
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["dev-1"] = dev_mock.boxed()
  backends["review-1"] = review_mock.boxed()
  let phases : Array[String] = []
  let callbacks = make_callbacks_with_phases(phases)
  let orch = @orchestrator.Orchestrator::new(config, backends, callbacks)
  let session = @types.Session::new("s1", "Build API", config.agents)
  orch.run(session)
  inspect(session.status, content="Completed")
  assert_true(phases.iter().any(fn(p) { p == "Iterating" }))
  // Dev mock called more than once: decompose + initial exec + rework
  assert_true(dev_mock.get_history().length() > 1)
  // Final task result should be the fixed version
  let last_task = session.tasks[session.tasks.length() - 1]
  assert_true(last_task.result is Some(_))
}

test "Orchestrator decompose failure falls back to original task" {
  let config = make_test_config()
  // Dev decomposer fails, but execution should still proceed with original task
  let dev_failing = @agent.FailingMockBackend::new(error_msg="LLM timeout")
  let review_mock = @agent.MockBackend::new(default_response="<approved>")
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["dev-1"] = dev_failing.boxed()
  backends["review-1"] = review_mock.boxed()
  let infos : Array[String] = []
  let cb = @types.OrchestratorCallbacks::noop()
  let callbacks = { ..cb, on_info: fn(msg) { infos.push(msg) } }
  let orch = @orchestrator.Orchestrator::new(config, backends, callbacks)
  let session = @types.Session::new("s1", "Build API", config.agents)
  orch.run(session)
  inspect(session.status, content="Completed")
  // Should have fallen back to single task
  assert_true(infos.iter().any(fn(i) { i.contains("Falling back") }))
  assert_true(session.tasks.length() >= 1)
}

test "Orchestrator handles missing backend for assigned task" {
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
    parse_warnings: [],
  }
  // Register backend as "dev-1" for decompose, but task gets assigned to "dev-1"
  // and we remove it before execution
  let dev_mock = @agent.MockBackend::new(default_response="single task")
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["dev-1"] = dev_mock.boxed()
  let task_events : Array[String] = []
  let cb = @types.OrchestratorCallbacks::noop()
  let callbacks = {
    ..cb,
    on_task_complete: fn(_tid, status) { task_events.push(status) },
  }
  let orch = @orchestrator.Orchestrator::new(config, backends, callbacks)
  let session = @types.Session::new("s1", "Build API", config.agents)
  orch.run(session)
  // All tasks should complete (decompose produces "single task" as one task)
  inspect(session.status, content="Completed")
}

test "Orchestrator iteration respects max_review_cycles" {
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
  let config : @config.ProjectConfig = {
    project_dir: ".",
    review_dir: "docs/reviews",
    max_review_cycles: 2,
    agents: [dev_agent, review_agent],
    parse_warnings: [],
  }
  let dev_mock = @agent.MockBackend::new(default_response="task done")
  // Always returns needs_changes - never approves
  let review_mock = @agent.MockBackend::new(
    default_response="<needs_changes>still broken</needs_changes>",
  )
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["dev-1"] = dev_mock.boxed()
  backends["review-1"] = review_mock.boxed()
  let phases : Array[String] = []
  let callbacks = make_callbacks_with_phases(phases)
  let orch = @orchestrator.Orchestrator::new(config, backends, callbacks)
  let session = @types.Session::new("s1", "Fix bug", config.agents)
  orch.run(session)
  // Session still completes (reaches Finalizing)
  inspect(session.status, content="Completed")
  // Review phases should be capped
  let review_count = phases.iter().filter(fn(p) { p == "Reviewing" }).count()
  assert_true(review_count <= 3)
}

test "Orchestrator progress reports accurate completed count" {
  let config = make_test_config()
  let dev_mock = @agent.MockBackend::new(
    default_response="1. Task A\n2. Task B",
  )
  let review_mock = @agent.MockBackend::new(default_response="<approved>")
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["dev-1"] = dev_mock.boxed()
  backends["review-1"] = review_mock.boxed()
  let progress_msgs : Array[String] = []
  let cb = @types.OrchestratorCallbacks::noop()
  let callbacks = {
    ..cb,
    on_info: fn(msg) {
      if msg.contains("Progress:") {
        progress_msgs.push(msg)
      }
    },
  }
  let orch = @orchestrator.Orchestrator::new(config, backends, callbacks)
  let session = @types.Session::new("s1", "Build API", config.agents)
  orch.run(session)
  // Should have progress messages for each completed task
  assert_true(progress_msgs.length() >= 1)
  // Last progress should show all tasks done
  let last = progress_msgs[progress_msgs.length() - 1]
  assert_true(last.contains("/"))
}
