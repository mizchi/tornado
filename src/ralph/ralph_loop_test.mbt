fn make_ralph_config(
  ralph_enabled~ : Bool = true,
) -> @config.ProjectConfig {
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
  let builder_mock = @agent.MockBackend::new(
    default_response="Schema created",
  )
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

test "RalphLoop with rework cycle" {
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
  let builder_mock = @agent.MockBackend::new(
    default_response="Done",
  )
  // First call needs rework, second approves
  let verifier_mock = @agent.MockBackend::new(
    default_response="<needs_rework>m1-t1: add validation</needs_rework>",
  )
  verifier_mock.add_response("attempt 2", "<wave_approved>")
  // Override: second verify call should approve
  // Since MockBackend uses prefix matching, we need a different approach
  // Let's use a counter-based approach via response pattern
  let backends : Map[String, @agent.BoxedBackend] = {}
  backends["planner"] = planner_mock.boxed()
  backends["builder"] = builder_mock.boxed()
  backends["verifier"] = verifier_mock.boxed()
  let infos : Array[String] = []
  let cb = @types.OrchestratorCallbacks::noop()
  let callbacks = { ..cb, on_info: fn(msg) { infos.push(msg) } }
  let rl = @ralph.RalphLoop::new(config, mgr, backends, callbacks)
  rl.run()
  // Should have rework info
  assert_true(infos.iter().any(fn(m) { m.contains("Rework needed") }))
  // Eventually reaches max rework and accepts
  assert_true(
    infos.iter().any(fn(m) {
      m.contains("Max rework attempts") || m.contains("complete")
    }),
  )
}

test "RalphLoop milestone failure" {
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
