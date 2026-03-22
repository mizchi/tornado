///|
fn make_ralph_config(ralph_enabled? : Bool = true) -> @config.ProjectConfig {
  let planner_agent : @types.AgentConfig = {
    id: "planner",
    kind: Mock,
    role: Planner,
    model: None,
    system_prompt: None,
    working_dir: ".",
    max_iterations: 10,
  }
  let builder_agent : @types.AgentConfig = {
    id: "builder",
    kind: Mock,
    role: Dev,
    model: None,
    system_prompt: None,
    working_dir: ".",
    max_iterations: 10,
  }
  let verifier_agent : @types.AgentConfig = {
    id: "verifier",
    kind: Mock,
    role: Verifier,
    model: None,
    system_prompt: None,
    working_dir: ".",
    max_iterations: 10,
  }
  {
    project_dir: ".",
    review_dir: "docs/reviews",
    max_review_cycles: 3,
    review_interval: 1,
    agents: [planner_agent, builder_agent, verifier_agent],
    parse_warnings: [],
    ralph_enabled,
    milestones_path: None,
    max_rework_attempts: 3,
  }
}

///|
test "RalphLoop full cycle with single milestone" {
  let config = make_ralph_config()
  let json =
    #|{
    #|  "milestones": [
    #|    { "id": "m1", "goal": "Build auth", "status": "pending", "tasks": [] }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let planner_mock = @agent.MockBackend::new(
    default_response="WAVE 0:\n1. Create schema\n2. Write tests",
  )
  let builder_mock = @agent.MockBackend::new(
    default_response="Task completed successfully",
  )
  let verifier_mock = @agent.MockBackend::new(
    default_response="<wave_approved>",
  )
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["planner"] = planner_mock.boxed()
  backends["builder"] = builder_mock.boxed()
  backends["verifier"] = verifier_mock.boxed()
  let infos : Array[String] = []
  let cb = @types.OrchestratorCallbacks::noop()
  let callbacks = { ..cb, on_info: fn(msg) { infos.push(msg) } }
  let rl = @ralph.RalphLoop::new(config, mgr, backends, callbacks)
  rl.run()
  // Milestone should be complete
  inspect(mgr.milestones[0].status, content="Done")
  // Should have info messages about progress
  assert_true(infos.iter().any(fn(m) { m.contains("Ralph loop started") }))
  assert_true(infos.iter().any(fn(m) { m.contains("Planning") }))
  assert_true(infos.iter().any(fn(m) { m.contains("Executing wave") }))
  assert_true(infos.iter().any(fn(m) { m.contains("approved") }))
  assert_true(infos.iter().any(fn(m) { m.contains("complete") }))
  // Phase should be AllComplete
  inspect(rl.current_phase, content="AllComplete")
}

///|
test "planner receives system prompt with brief and completed milestone summaries" {
  let config = make_ralph_config()
  let json =
    #|{
    #|  "brief": "Ship an auth service with audit logging.",
    #|  "milestones": [
    #|    {
    #|      "id": "m1",
    #|      "goal": "Setup project",
    #|      "status": "done",
    #|      "summary": "Initialized repo; added config",
    #|      "tasks": []
    #|    },
    #|    {
    #|      "id": "m2",
    #|      "goal": "Build auth",
    #|      "status": "pending",
    #|      "tasks": []
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let planner_mock = @agent.MockBackend::new(
    default_response="WAVE 0:\n1. Create schema",
  )
  let builder_mock = @agent.MockBackend::new(default_response="Done")
  let verifier_mock = @agent.MockBackend::new(
    default_response="<wave_approved>",
  )
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["planner"] = planner_mock.boxed()
  backends["builder"] = builder_mock.boxed()
  backends["verifier"] = verifier_mock.boxed()
  let callbacks = @types.OrchestratorCallbacks::noop()
  let rl = @ralph.RalphLoop::new(config, mgr, backends, callbacks)
  rl.run()
  let (_, system_prompt) = planner_mock.get_history()[0]
  assert_true(
    system_prompt.contains(
      "You are a planning agent that breaks down milestones into executable tasks.\n",
    ),
  )
  assert_true(
    system_prompt.contains(
      "Do NOT write to or modify files under .claude/plans/",
    ),
  )
  assert_true(
    system_prompt.contains(
      "## Brief\nShip an auth service with audit logging.\n\n",
    ),
  )
  assert_true(
    system_prompt.contains(
      "## Completed Milestones\n- m1: Initialized repo; added config\n",
    ),
  )
}

///|
test "builder receives system prompt with brief" {
  let config = make_ralph_config()
  let json =
    #|{
    #|  "brief": "Keep public APIs stable while refactoring internals.",
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "Build auth", "status": "pending",
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "Create schema", "wave": 0, "status": "pending" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let planner_mock = @agent.MockBackend::new(default_response="unused")
  let builder_mock = @agent.MockBackend::new(default_response="Done")
  let verifier_mock = @agent.MockBackend::new(
    default_response="<wave_approved>",
  )
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["planner"] = planner_mock.boxed()
  backends["builder"] = builder_mock.boxed()
  backends["verifier"] = verifier_mock.boxed()
  let callbacks = @types.OrchestratorCallbacks::noop()
  let rl = @ralph.RalphLoop::new(config, mgr, backends, callbacks)
  rl.run()
  let (_, system_prompt) = builder_mock.get_history()[0]
  let expected =
    #|## Brief
    #|Keep public APIs stable while refactoring internals.
    #|
  inspect(system_prompt, content=expected)
}

///|
test "completed milestone summary concatenates completed task descriptions" {
  let config = make_ralph_config()
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "Build auth", "status": "pending",
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "Create schema", "wave": 0, "status": "pending" },
    #|        { "id": "m1-t2", "description": "Build handlers", "wave": 1, "status": "pending" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let planner_mock = @agent.MockBackend::new(default_response="unused")
  let builder_mock = @agent.MockBackend::new(default_response="Done")
  let verifier_mock = @agent.MockBackend::new(
    default_response="<wave_approved>",
  )
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["planner"] = planner_mock.boxed()
  backends["builder"] = builder_mock.boxed()
  backends["verifier"] = verifier_mock.boxed()
  let callbacks = @types.OrchestratorCallbacks::noop()
  let rl = @ralph.RalphLoop::new(config, mgr, backends, callbacks)
  rl.run()
  inspect(mgr.milestones[0].summary, content="Create schema; Build handlers")
}

///|
test "RalphLoop with pre-planned tasks" {
  let config = make_ralph_config()
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "Build auth", "status": "pending",
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "Create schema", "wave": 0, "status": "pending" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let planner_mock = @agent.MockBackend::new(default_response="unused")
  let builder_mock = @agent.MockBackend::new(default_response="Schema created")
  let verifier_mock = @agent.MockBackend::new(
    default_response="<wave_approved>",
  )
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["planner"] = planner_mock.boxed()
  backends["builder"] = builder_mock.boxed()
  backends["verifier"] = verifier_mock.boxed()
  let callbacks = @types.OrchestratorCallbacks::noop()
  let rl = @ralph.RalphLoop::new(config, mgr, backends, callbacks)
  rl.run()
  inspect(mgr.milestones[0].status, content="Done")
  // Planner should not have been called since tasks were pre-planned
  assert_true(planner_mock.get_history().is_empty())
}

///|
test "RalphLoop logs resume progress for partially completed milestone" {
  let config = make_ralph_config()
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "Build auth", "status": "in_progress",
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "Create schema", "wave": 0, "status": "done" },
    #|        { "id": "m1-t2", "description": "Write tests", "wave": 0, "status": "done" },
    #|        { "id": "m1-t3", "description": "Add handlers", "wave": 1, "status": "pending" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let planner_mock = @agent.MockBackend::new(default_response="unused")
  let builder_mock = @agent.MockBackend::new(default_response="Done")
  let verifier_mock = @agent.MockBackend::new(
    default_response="<wave_approved>",
  )
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["planner"] = planner_mock.boxed()
  backends["builder"] = builder_mock.boxed()
  backends["verifier"] = verifier_mock.boxed()
  let infos : Array[String] = []
  let cb = @types.OrchestratorCallbacks::noop()
  let callbacks = { ..cb, on_info: fn(msg) { infos.push(msg) } }
  let rl = @ralph.RalphLoop::new(config, mgr, backends, callbacks)
  rl.run()
  assert_true(
    infos
    .iter()
    .any(fn(msg) {
      msg.contains("Resuming milestone m1: 2 of 3 tasks already done")
    }),
  )
}

///|
test "run_wave skips already-done tasks before submitting to builder" {
  let config = make_ralph_config()
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "Resume auth", "status": "pending",
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "Create schema", "wave": 0, "status": "done", "result": "already finished" },
    #|        { "id": "m1-t2", "description": "Write tests", "wave": 0, "status": "done", "result": "already finished" },
    #|        { "id": "m1-t3", "description": "Write handlers", "wave": 0, "status": "pending" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let planner_mock = @agent.MockBackend::new(default_response="unused")
  let builder_mock = @agent.MockBackend::new(default_response="fresh result")
  let verifier_mock = @agent.MockBackend::new(
    default_response="<wave_approved>",
  )
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["planner"] = planner_mock.boxed()
  backends["builder"] = builder_mock.boxed()
  backends["verifier"] = verifier_mock.boxed()
  let infos : Array[String] = []
  let cb = @types.OrchestratorCallbacks::noop()
  let callbacks = { ..cb, on_info: fn(msg) { infos.push(msg) } }
  let rl = @ralph.RalphLoop::new(config, mgr, backends, callbacks)

  rl.run()

  let history = builder_mock.get_history()
  assert_true(history.length() == 1)
  inspect(history[0].0, content="Write handlers")
  inspect(
    mgr.milestones[0].tasks[0].result.unwrap(),
    content="already finished",
  )
  inspect(
    mgr.milestones[0].tasks[1].result.unwrap(),
    content="already finished",
  )
  inspect(mgr.milestones[0].tasks[2].result.unwrap(), content="fresh result")
  assert_true(
    infos
    .iter()
    .any(fn(msg) { msg.contains("Wave 0: skipping 2 already-done tasks") }),
  )
}

///|
test "run_wave does not emit running logs for already-done tasks" {
  let config = make_ralph_config()
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "Resume auth", "status": "pending",
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "Create schema", "wave": 0, "status": "done", "result": "already finished" },
    #|        { "id": "m1-t2", "description": "Write handlers", "wave": 0, "status": "pending" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let planner_mock = @agent.MockBackend::new(default_response="unused")
  let builder_mock = @agent.MockBackend::new(default_response="fresh result")
  let verifier_mock = @agent.MockBackend::new(
    default_response="<wave_approved>",
  )
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["planner"] = planner_mock.boxed()
  backends["builder"] = builder_mock.boxed()
  backends["verifier"] = verifier_mock.boxed()
  let infos : Array[String] = []
  let cb = @types.OrchestratorCallbacks::noop()
  let callbacks = { ..cb, on_info: fn(msg) { infos.push(msg) } }
  let rl = @ralph.RalphLoop::new(config, mgr, backends, callbacks)

  rl.run()

  assert_true(
    not(infos.iter().any(fn(msg) { msg.contains("Running task m1-t1") })),
  )
  assert_true(infos.iter().any(fn(msg) { msg.contains("Running task m1-t2") }))
}

///|
test "resume skips already-done milestones" {
  let config = make_ralph_config()
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "Completed milestone", "status": "done",
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "Create schema", "wave": 0, "status": "done", "result": "already finished" }
    #|      ]
    #|    },
    #|    {
    #|      "id": "m2", "goal": "Pending milestone", "status": "pending",
    #|      "tasks": [
    #|        { "id": "m2-t1", "description": "Write handlers", "wave": 0, "status": "pending" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let planner_mock = @agent.MockBackend::new(default_response="unused")
  let builder_mock = @agent.MockBackend::new(default_response="fresh result")
  let verifier_mock = @agent.MockBackend::new(
    default_response="<wave_approved>",
  )
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["planner"] = planner_mock.boxed()
  backends["builder"] = builder_mock.boxed()
  backends["verifier"] = verifier_mock.boxed()
  let infos : Array[String] = []
  let cb = @types.OrchestratorCallbacks::noop()
  let callbacks = { ..cb, on_info: fn(msg) { infos.push(msg) } }
  let rl = @ralph.RalphLoop::new(config, mgr, backends, callbacks)

  rl.run()

  assert_true(planner_mock.get_history().is_empty())
  let history = builder_mock.get_history()
  assert_true(history.length() == 1)
  inspect(history[0].0, content="Write handlers")
  inspect(
    mgr.milestones[0].tasks[0].result.unwrap(),
    content="already finished",
  )
  inspect(mgr.milestones[1].tasks[0].result.unwrap(), content="fresh result")
  assert_true(
    not(infos.iter().any(fn(msg) { msg.contains("Planning milestone: m1") })),
  )
  assert_true(
    not(infos.iter().any(fn(msg) { msg.contains("Executing wave 0 of m1") })),
  )
  assert_true(
    not(infos.iter().any(fn(msg) { msg.contains("Resuming milestone m1:") })),
  )
  assert_true(
    not(infos.iter().any(fn(msg) { msg.contains("Running task m1-t1") })),
  )
  assert_true(
    infos.iter().any(fn(msg) { msg.contains("Executing wave 0 of m2") }),
  )
}

///|
test "RalphLoop with rework cycle at milestone verification" {
  let config = make_ralph_config()
  let json =
    #|{
    #|  "milestones": [
    #|    { "id": "m1", "goal": "Build auth", "status": "pending", "tasks": [] }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let planner_mock = @agent.MockBackend::new(
    default_response="WAVE 0:\n1. Create schema",
  )
  let builder_mock = @agent.MockBackend::new(default_response="Done")
  let verifier_mock = @agent.MockBackend::new(
    default_response="<wave_approved>",
  )
  verifier_mock.add_response(
    "Security", "<needs_rework>m1-t1: add validation</needs_rework>",
  )
  verifier_mock.add_response("REWORKED", "<wave_approved>")
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["planner"] = planner_mock.boxed()
  backends["builder"] = builder_mock.boxed()
  backends["verifier"] = verifier_mock.boxed()
  let infos : Array[String] = []
  let cb = @types.OrchestratorCallbacks::noop()
  let callbacks = { ..cb, on_info: fn(msg) { infos.push(msg) } }
  let rl = @ralph.RalphLoop::new(config, mgr, backends, callbacks)
  rl.run()
  // Should have rework info from milestone verification
  assert_true(
    infos
    .iter()
    .any(fn(m) { m.contains("Rework needed") || m.contains("rework needed") }),
  )
  // Eventually reaches max rework and accepts
  assert_true(
    infos
    .iter()
    .any(fn(m) { m.contains("Max rework attempts") || m.contains("complete") }),
  )
}

///|
test "RalphLoop milestone failure at milestone verification" {
  let config = make_ralph_config()
  let json =
    #|{
    #|  "milestones": [
    #|    { "id": "m1", "goal": "Build auth", "status": "pending", "tasks": [] }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let planner_mock = @agent.MockBackend::new(
    default_response="WAVE 0:\n1. Create schema",
  )
  let builder_mock = @agent.MockBackend::new(default_response="Done")
  let verifier_mock = @agent.MockBackend::new(
    default_response="<milestone_failed>Architecture fundamentally flawed</milestone_failed>",
  )
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["planner"] = planner_mock.boxed()
  backends["builder"] = builder_mock.boxed()
  backends["verifier"] = verifier_mock.boxed()
  let infos : Array[String] = []
  let cb = @types.OrchestratorCallbacks::noop()
  let callbacks = { ..cb, on_info: fn(msg) { infos.push(msg) } }
  let rl = @ralph.RalphLoop::new(config, mgr, backends, callbacks)
  rl.run()
  // Milestone should be failed
  assert_true(mgr.milestones[0].status is @types.MilestoneStatus::Failed(_))
  assert_true(infos.iter().any(fn(m) { m.contains("failed") }))
}

///|
test "RalphLoop without verifier auto-approves" {
  let builder_agent : @types.AgentConfig = {
    id: "builder",
    kind: Mock,
    role: Dev,
    model: None,
    system_prompt: None,
    working_dir: ".",
    max_iterations: 10,
  }
  let planner_agent : @types.AgentConfig = {
    id: "planner",
    kind: Mock,
    role: Planner,
    model: None,
    system_prompt: None,
    working_dir: ".",
    max_iterations: 10,
  }
  let config : @config.ProjectConfig = {
    project_dir: ".",
    review_dir: "docs/reviews",
    max_review_cycles: 3,
    review_interval: 1,
    agents: [planner_agent, builder_agent],
    parse_warnings: [],
    ralph_enabled: true,
    milestones_path: None,
    max_rework_attempts: 3,
  }
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "Build auth", "status": "pending",
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "Create schema", "wave": 0, "status": "pending" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let planner_mock = @agent.MockBackend::new(default_response="unused")
  let builder_mock = @agent.MockBackend::new(default_response="Done")
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["planner"] = planner_mock.boxed()
  backends["builder"] = builder_mock.boxed()
  let callbacks = @types.OrchestratorCallbacks::noop()
  let rl = @ralph.RalphLoop::new(config, mgr, backends, callbacks)
  rl.run()
  inspect(mgr.milestones[0].status, content="Done")
}

///|
test "RalphLoop multiple milestones" {
  let config = make_ralph_config()
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "Setup", "status": "pending",
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "Init project", "wave": 0, "status": "pending" }
    #|      ]
    #|    },
    #|    {
    #|      "id": "m2", "goal": "Build API", "status": "pending",
    #|      "tasks": [
    #|        { "id": "m2-t1", "description": "Create routes", "wave": 0, "status": "pending" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let planner_mock = @agent.MockBackend::new(default_response="unused")
  let builder_mock = @agent.MockBackend::new(default_response="Done")
  let verifier_mock = @agent.MockBackend::new(
    default_response="<wave_approved>",
  )
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["planner"] = planner_mock.boxed()
  backends["builder"] = builder_mock.boxed()
  backends["verifier"] = verifier_mock.boxed()
  let callbacks = @types.OrchestratorCallbacks::noop()
  let rl = @ralph.RalphLoop::new(config, mgr, backends, callbacks)
  rl.run()
  inspect(mgr.milestones[0].status, content="Done")
  inspect(mgr.milestones[1].status, content="Done")
  inspect(rl.current_phase, content="AllComplete")
}

///|
test "RalphLoop multi-wave execution" {
  let config = make_ralph_config()
  let json =
    #|{
    #|  "milestones": [
    #|    { "id": "m1", "goal": "Build", "status": "pending", "tasks": [] }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let planner_mock = @agent.MockBackend::new(
    default_response="WAVE 0:\n1. Setup\n\nWAVE 1:\n1. Build\n2. Test",
  )
  let builder_mock = @agent.MockBackend::new(default_response="Done")
  let verifier_mock = @agent.MockBackend::new(
    default_response="<wave_approved>",
  )
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["planner"] = planner_mock.boxed()
  backends["builder"] = builder_mock.boxed()
  backends["verifier"] = verifier_mock.boxed()
  let infos : Array[String] = []
  let cb = @types.OrchestratorCallbacks::noop()
  let callbacks = { ..cb, on_info: fn(msg) { infos.push(msg) } }
  let rl = @ralph.RalphLoop::new(config, mgr, backends, callbacks)
  rl.run()
  inspect(mgr.milestones[0].status, content="Done")
  // Should execute wave 0 and wave 1
  assert_true(infos.iter().any(fn(m) { m.contains("Executing wave 0") }))
  assert_true(infos.iter().any(fn(m) { m.contains("Executing wave 1") }))
  // Builder should have been called 3 times (1 in wave 0 + 2 in wave 1)
  assert_true(builder_mock.get_history().length() == 3)
}

///|
test "RalphLoop verifies all 4 perspectives after waves complete" {
  let config = make_ralph_config()
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "Build auth", "status": "pending",
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "Create schema", "wave": 0, "status": "pending" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let planner_mock = @agent.MockBackend::new(default_response="unused")
  let builder_mock = @agent.MockBackend::new(default_response="Done")
  let verifier_mock = @agent.MockBackend::new(
    default_response="<wave_approved>",
  )
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["planner"] = planner_mock.boxed()
  backends["builder"] = builder_mock.boxed()
  backends["verifier"] = verifier_mock.boxed()
  let infos : Array[String] = []
  let cb = @types.OrchestratorCallbacks::noop()
  let callbacks = { ..cb, on_info: fn(msg) { infos.push(msg) } }
  let rl = @ralph.RalphLoop::new(config, mgr, backends, callbacks)

  rl.run()

  inspect(mgr.milestones[0].status, content="Done")
  assert_true(
    infos.iter().any(fn(msg) { msg.contains("Verifying milestone m1") }),
  )
  assert_true(infos.iter().any(fn(msg) { msg.contains("approved") }))
  // 4 perspectives: CodeQuality, Performance, Security, GoalAlignment
  let history = verifier_mock.get_history()
  assert_true(history.length() == 4)
}

///|
test "RalphLoop multi-wave full cycle verifies all 4 perspectives once at milestone completion" {
  let config = make_ralph_config()
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "Ship auth flow", "status": "pending",
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "Create schema", "wave": 0, "status": "pending" },
    #|        { "id": "m1-t2", "description": "Build handlers", "wave": 1, "status": "pending" },
    #|        { "id": "m1-t3", "description": "Add integration tests", "wave": 2, "status": "pending" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let planner_mock = @agent.MockBackend::new(default_response="unused")
  let builder_mock = @agent.MockBackend::new(default_response="Done")
  let verifier_mock = @agent.MockBackend::new(
    default_response="<wave_approved>",
  )
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["planner"] = planner_mock.boxed()
  backends["builder"] = builder_mock.boxed()
  backends["verifier"] = verifier_mock.boxed()
  let rl = @ralph.RalphLoop::new(
    config,
    mgr,
    backends,
    @types.OrchestratorCallbacks::noop(),
  )

  rl.run()

  inspect(mgr.milestones[0].status, content="Done")
  let history = verifier_mock.get_history()
  // Only 4 verifier calls: one per perspective at milestone completion
  assert_true(history.length() == 4)
  // All prompts should contain all task results (by task ID)
  let (first_prompt, _) = history[0]
  assert_true(first_prompt.contains("m1-t1"))
  assert_true(first_prompt.contains("m1-t2"))
  assert_true(first_prompt.contains("m1-t3"))
}

///|
test "RalphLoop reworks milestone tasks during milestone verification" {
  let config = make_ralph_config()
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "Build auth", "status": "pending",
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "Implement login flow", "wave": 0, "status": "pending" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let planner_mock = @agent.MockBackend::new(default_response="unused")
  let builder_mock = @agent.MockBackend::new(default_response="Done v1")
  builder_mock.add_response("Feedback from verifier", "Done v2 REWORKED")
  let verifier_mock = @agent.MockBackend::new(
    default_response="<wave_approved>",
  )
  // First verification: Security perspective returns needs_rework
  // "Done v1" uniquely matches the first run's result content
  verifier_mock.add_response(
    "Done v1", "<needs_rework>m1-t1: missing end-to-end behavior</needs_rework>",
  )
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["planner"] = planner_mock.boxed()
  backends["builder"] = builder_mock.boxed()
  backends["verifier"] = verifier_mock.boxed()
  let infos : Array[String] = []
  let cb = @types.OrchestratorCallbacks::noop()
  let callbacks = { ..cb, on_info: fn(msg) { infos.push(msg) } }
  let rl = @ralph.RalphLoop::new(config, mgr, backends, callbacks)

  rl.run()

  inspect(mgr.milestones[0].status, content="Done")
  assert_true(
    infos
    .iter()
    .any(fn(msg) {
      msg.contains("rework needed for m1") || msg.contains("Rework needed")
    }),
  )
  let builder_history = builder_mock.get_history()
  assert_true(builder_history.length() == 2)
  let (rework_task, _) = builder_history[1]
  assert_true(rework_task.contains("Implement login flow"))
  assert_true(rework_task.contains("Feedback from verifier"))
  assert_true(mgr.milestones[0].tasks[0].result.unwrap().contains("REWORKED"))
}

///|
test "RalphLoop milestone verification rework cycle retries and then completes" {
  let config = make_ralph_config()
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "Ship auth flow", "status": "pending",
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "Implement login flow", "wave": 0, "status": "pending" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let planner_mock = @agent.MockBackend::new(default_response="unused")
  let builder_mock = @agent.MockBackend::new(default_response="Done v1")
  builder_mock.add_response("Feedback from verifier", "Done v2 REWORKED")
  let verifier_mock = @agent.MockBackend::new(
    default_response="<wave_approved>",
  )
  // "Done v1" uniquely matches first-run results, triggers rework
  verifier_mock.add_response(
    "Done v1", "<needs_rework>m1-t1: missing end-to-end behavior</needs_rework>",
  )
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["planner"] = planner_mock.boxed()
  backends["builder"] = builder_mock.boxed()
  backends["verifier"] = verifier_mock.boxed()
  let infos : Array[String] = []
  let cb = @types.OrchestratorCallbacks::noop()
  let callbacks = { ..cb, on_info: fn(msg) { infos.push(msg) } }
  let rl = @ralph.RalphLoop::new(config, mgr, backends, callbacks)

  rl.run()

  inspect(mgr.milestones[0].status, content="Done")
  assert_true(
    infos
    .iter()
    .any(fn(msg) { msg.contains("Verifying milestone m1 (attempt 1)") }),
  )
  assert_true(
    infos
    .iter()
    .any(fn(msg) {
      msg.contains("rework needed for m1") || msg.contains("Rework needed")
    }),
  )
  assert_true(
    infos
    .iter()
    .any(fn(msg) { msg.contains("Verifying milestone m1 (attempt 2)") }),
  )
  assert_true(infos.iter().any(fn(msg) { msg.contains("approved") }))

  let builder_history = builder_mock.get_history()
  assert_true(builder_history.length() == 2)
  let (rework_task, _) = builder_history[1]
  assert_true(rework_task.contains("Implement login flow"))
  inspect(
    mgr.milestones[0].tasks[0].result.unwrap(),
    content="Done v2 REWORKED",
  )
}

///|
test "RalphLoop fails milestone when goal alignment verification fails" {
  let config = make_ralph_config()
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "Build auth", "status": "pending",
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "Create schema", "wave": 0, "status": "pending" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let planner_mock = @agent.MockBackend::new(default_response="unused")
  let builder_mock = @agent.MockBackend::new(default_response="Done")
  let verifier_mock = @agent.MockBackend::new(
    default_response="<wave_approved>",
  )
  verifier_mock.add_response(
    "## Review Focus: Goal Alignment", "<milestone_failed>Milestone goal was not achieved</milestone_failed>",
  )
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["planner"] = planner_mock.boxed()
  backends["builder"] = builder_mock.boxed()
  backends["verifier"] = verifier_mock.boxed()
  let rl = @ralph.RalphLoop::new(
    config,
    mgr,
    backends,
    @types.OrchestratorCallbacks::noop(),
  )

  rl.run()

  assert_true(mgr.milestones[0].status is @types.MilestoneStatus::Failed(_))
}

///|
test "RalphLoop marks milestone failed when milestone verification returns milestone_failed" {
  let config = make_ralph_config()
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "Build auth", "status": "pending",
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "Create schema", "wave": 0, "status": "pending" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let planner_mock = @agent.MockBackend::new(default_response="unused")
  let builder_mock = @agent.MockBackend::new(default_response="Done")
  let verifier_mock = @agent.MockBackend::new(
    default_response="<milestone_failed>Milestone goal was not achieved</milestone_failed>",
  )
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["planner"] = planner_mock.boxed()
  backends["builder"] = builder_mock.boxed()
  backends["verifier"] = verifier_mock.boxed()
  let rl = @ralph.RalphLoop::new(
    config,
    mgr,
    backends,
    @types.OrchestratorCallbacks::noop(),
  )

  rl.run()

  let history = verifier_mock.get_history()
  // 4 perspectives called at milestone verification
  assert_true(history.length() == 4)
  assert_true(mgr.milestones[0].status is @types.MilestoneStatus::Failed(_))
}

///|
test "rework_tasks passes targeted feedback to specific task only" {
  let config = make_ralph_config()
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "Build auth", "status": "pending",
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "Implement login flow", "wave": 0, "status": "pending" },
    #|        { "id": "m1-t2", "description": "Add audit logging", "wave": 0, "status": "pending" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let planner_mock = @agent.MockBackend::new(default_response="unused")
  let builder_mock = @agent.MockBackend::new(default_response="Done v1")
  builder_mock.add_response("Feedback from verifier", "Done v2 REWORKED")
  let verifier_mock = @agent.MockBackend::new(
    default_response="<wave_approved>",
  )
  verifier_mock.add_response(
    "### Task: m1-t1\nDone v1\n\n### Task: m1-t2\nDone v1\n\n## Review Focus: Security",
    "<needs_rework>m1-t1: fix error handling</needs_rework>",
  )
  verifier_mock.add_response("REWORKED", "<wave_approved>")
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["planner"] = planner_mock.boxed()
  backends["builder"] = builder_mock.boxed()
  backends["verifier"] = verifier_mock.boxed()
  let callbacks = @types.OrchestratorCallbacks::noop()
  let rl = @ralph.RalphLoop::new(config, mgr, backends, callbacks)

  rl.run()

  let history = builder_mock.get_history()
  assert_true(history.length() == 3)
  let (initial_task_1, _) = history[0]
  let (initial_task_2, _) = history[1]
  let (rework_task, _) = history[2]
  inspect(initial_task_1, content="Implement login flow")
  inspect(initial_task_2, content="Add audit logging")
  assert_true(rework_task.contains("Implement login flow"))
  assert_true(
    rework_task.contains(
      "Feedback from verifier:\n- [Security] fix error handling",
    ),
  )
  assert_true(not(rework_task.contains("Add audit logging")))
  assert_true(mgr.milestones[0].tasks[0].result.unwrap().contains("REWORKED"))
  inspect(mgr.milestones[0].tasks[1].result.unwrap(), content="Done v1")
}

///|
test "rework_tasks resets all done tasks when feedback has no task ID (fallback)" {
  let config = make_ralph_config()
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "Build auth", "status": "pending",
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "Implement login flow", "wave": 0, "status": "pending" },
    #|        { "id": "m1-t2", "description": "Add audit logging", "wave": 0, "status": "pending" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let planner_mock = @agent.MockBackend::new(default_response="unused")
  let builder_mock = @agent.MockBackend::new(default_response="Done v1")
  builder_mock.add_response("Feedback from verifier", "Done v2 REWORKED")
  let verifier_mock = @agent.MockBackend::new(
    default_response="<wave_approved>",
  )
  verifier_mock.add_response(
    "### Task: m1-t1\nDone v1\n\n### Task: m1-t2\nDone v1\n\n## Review Focus: Security",
    "<needs_rework>general quality issues</needs_rework>",
  )
  verifier_mock.add_response("REWORKED", "<wave_approved>")
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["planner"] = planner_mock.boxed()
  backends["builder"] = builder_mock.boxed()
  backends["verifier"] = verifier_mock.boxed()
  let callbacks = @types.OrchestratorCallbacks::noop()
  let rl = @ralph.RalphLoop::new(config, mgr, backends, callbacks)

  rl.run()

  let history = builder_mock.get_history()
  assert_true(history.length() == 4)
  let (initial_task_1, _) = history[0]
  let (initial_task_2, _) = history[1]
  let (rework_task_1, _) = history[2]
  let (rework_task_2, _) = history[3]
  inspect(initial_task_1, content="Implement login flow")
  inspect(initial_task_2, content="Add audit logging")
  assert_true(rework_task_1.contains("Implement login flow"))
  assert_true(
    rework_task_1.contains(
      "Feedback from verifier:\n- [Security] general quality issues",
    ),
  )
  assert_true(rework_task_2.contains("Add audit logging"))
  assert_true(
    rework_task_2.contains(
      "Feedback from verifier:\n- [Security] general quality issues",
    ),
  )
  assert_true(mgr.milestones[0].tasks[0].result.unwrap().contains("REWORKED"))
  assert_true(mgr.milestones[0].tasks[1].result.unwrap().contains("REWORKED"))
}

///|
test "rework_tasks distributes per-task feedback without cross-contamination" {
  let config = make_ralph_config()
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "Build auth", "status": "pending",
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "Implement login flow", "wave": 0, "status": "pending" },
    #|        { "id": "m1-t2", "description": "Add audit logging", "wave": 0, "status": "pending" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let planner_mock = @agent.MockBackend::new(default_response="unused")
  let builder_mock = @agent.MockBackend::new(default_response="Done v1")
  builder_mock.add_response(
    "[CodeQuality] add validation", "Done v2 REWORKED-T1",
  )
  builder_mock.add_response(
    "[Security] missing edge cases", "Done v2 REWORKED-T2",
  )
  let verifier_mock = @agent.MockBackend::new(
    default_response="<wave_approved>",
  )
  verifier_mock.add_response(
    "### Task: m1-t1\nDone v1\n\n### Task: m1-t2\nDone v1\n\n## Review Focus: Code Quality",
    "<needs_rework>m1-t1: add validation</needs_rework>",
  )
  verifier_mock.add_response(
    "### Task: m1-t1\nDone v1\n\n### Task: m1-t2\nDone v1\n\n## Review Focus: Security",
    "<needs_rework>m1-t2: missing edge cases</needs_rework>",
  )
  verifier_mock.add_response("REWORKED", "<wave_approved>")
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["planner"] = planner_mock.boxed()
  backends["builder"] = builder_mock.boxed()
  backends["verifier"] = verifier_mock.boxed()
  let callbacks = @types.OrchestratorCallbacks::noop()
  let rl = @ralph.RalphLoop::new(config, mgr, backends, callbacks)

  rl.run()

  let history = builder_mock.get_history()
  assert_true(history.length() == 4)
  let (initial_task_1, _) = history[0]
  let (initial_task_2, _) = history[1]
  let (rework_task_1, _) = history[2]
  let (rework_task_2, _) = history[3]
  inspect(initial_task_1, content="Implement login flow")
  inspect(initial_task_2, content="Add audit logging")
  assert_true(rework_task_1.contains("Implement login flow"))
  assert_true(rework_task_1.contains("[CodeQuality] add validation"))
  assert_true(not(rework_task_1.contains("missing edge cases")))
  assert_true(rework_task_2.contains("Add audit logging"))
  assert_true(rework_task_2.contains("[Security] missing edge cases"))
  assert_true(not(rework_task_2.contains("add validation")))
  inspect(
    mgr.milestones[0].tasks[0].result.unwrap(),
    content="Done v2 REWORKED-T1",
  )
  inspect(
    mgr.milestones[0].tasks[1].result.unwrap(),
    content="Done v2 REWORKED-T2",
  )
}

///|
test "rework prompt has correct format with description and feedback" {
  let config = make_ralph_config()
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "Build auth", "status": "pending",
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "implement feature X", "wave": 0, "status": "pending" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let planner_mock = @agent.MockBackend::new(default_response="unused")
  let builder_mock = @agent.MockBackend::new(default_response="Done v1")
  builder_mock.add_response("Feedback from verifier", "Done v2 REWORKED")
  let verifier_mock = @agent.MockBackend::new(
    default_response="<wave_approved>",
  )
  verifier_mock.add_response(
    "### Task: m1-t1\nDone v1\n\n## Review Focus: Code Quality", "<needs_rework>m1-t1: add input validation</needs_rework>",
  )
  verifier_mock.add_response("REWORKED", "<wave_approved>")
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["planner"] = planner_mock.boxed()
  backends["builder"] = builder_mock.boxed()
  backends["verifier"] = verifier_mock.boxed()
  let callbacks = @types.OrchestratorCallbacks::noop()
  let rl = @ralph.RalphLoop::new(config, mgr, backends, callbacks)

  rl.run()

  let history = builder_mock.get_history()
  assert_true(history.length() == 2)
  let (rework_task, _) = history[1]
  let expected_prompt = "implement feature X\n\nFeedback from verifier:\n- [CodeQuality] add input validation\n"
  inspect(rework_task, content=expected_prompt)
  inspect(
    mgr.milestones[0].tasks[0].result.unwrap(),
    content="Done v2 REWORKED",
  )
}

///|
test "rework_tasks matches space-delimited feedback (no colon)" {
  let config = make_ralph_config()
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "Build auth", "status": "pending",
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "Implement login flow", "wave": 0, "status": "pending" },
    #|        { "id": "m1-t2", "description": "Add audit logging", "wave": 0, "status": "pending" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let planner_mock = @agent.MockBackend::new(default_response="unused")
  let builder_mock = @agent.MockBackend::new(default_response="Done v1")
  builder_mock.add_response("Feedback from verifier", "Done v2 REWORKED")
  let verifier_mock = @agent.MockBackend::new(
    default_response="<wave_approved>",
  )
  verifier_mock.add_response(
    "### Task: m1-t1\nDone v1\n\n### Task: m1-t2\nDone v1\n\n## Review Focus: Security",
    "<needs_rework>m1-t1 needs better validation</needs_rework>",
  )
  verifier_mock.add_response("REWORKED", "<wave_approved>")
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["planner"] = planner_mock.boxed()
  backends["builder"] = builder_mock.boxed()
  backends["verifier"] = verifier_mock.boxed()
  let callbacks = @types.OrchestratorCallbacks::noop()
  let rl = @ralph.RalphLoop::new(config, mgr, backends, callbacks)

  rl.run()

  let history = builder_mock.get_history()
  assert_true(history.length() == 3)
  let (initial_task_1, _) = history[0]
  let (initial_task_2, _) = history[1]
  let (rework_task, _) = history[2]
  inspect(initial_task_1, content="Implement login flow")
  inspect(initial_task_2, content="Add audit logging")
  assert_true(rework_task.contains("Implement login flow"))
  assert_true(
    rework_task.contains(
      "Feedback from verifier:\n- [Security] needs better validation",
    ),
  )
  assert_true(not(rework_task.contains("Add audit logging")))
  assert_true(mgr.milestones[0].tasks[0].result.unwrap().contains("REWORKED"))
  inspect(mgr.milestones[0].tasks[1].result.unwrap(), content="Done v1")
}
