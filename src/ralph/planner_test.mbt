///|
test "PlannerAgent::build_plan_prompt includes milestone info" {
  let planner = @ralph.PlannerAgent::new()
  let milestone : @types.Milestone = {
    id: "m1",
    goal: "Build authentication system",
    status: @types.MilestoneStatus::Pending,
    tasks: [],
    current_wave: 0,
  }
  let prompt = planner.build_plan_prompt(milestone, "Node.js project")
  assert_true(prompt.contains("m1"))
  assert_true(prompt.contains("Build authentication system"))
  assert_true(prompt.contains("Node.js project"))
  assert_true(prompt.contains("WAVE"))
}

///|
test "PlannerAgent::build_plan_prompt lang=ja" {
  let planner = @ralph.PlannerAgent::new(lang="ja")
  let milestone : @types.Milestone = {
    id: "m1",
    goal: "Build auth",
    status: @types.MilestoneStatus::Pending,
    tasks: [],
    current_wave: 0,
  }
  let prompt = planner.build_plan_prompt(milestone, "")
  assert_true(prompt.contains("Japanese"))
}

///|
test "PlannerAgent::parse_plan delegates to MilestoneManager" {
  let planner = @ralph.PlannerAgent::new()
  let mgr = @ralph.MilestoneManager::new()
  let output =
    #|WAVE 0:
    #|1. Set up database
    #|
    #|WAVE 1:
    #|1. Create API routes
  let tasks = planner.parse_plan(output, "m1", mgr)
  assert_true(tasks.length() == 2)
  inspect(tasks[0].wave, content="0")
  inspect(tasks[1].wave, content="1")
}

///|
test "PlannerAgent::build_milestone_design_prompt includes context" {
  let planner = @ralph.PlannerAgent::new()
  let prompt = planner.build_milestone_design_prompt(
    "Node.js project with auth",
  )
  assert_true(prompt.contains("Node.js project with auth"))
  assert_true(prompt.contains("MILESTONE"))
  assert_true(prompt.contains("3-7 milestones"))
}

///|
test "PlannerAgent::build_milestone_design_prompt lang=ja" {
  let planner = @ralph.PlannerAgent::new(lang="ja")
  let prompt = planner.build_milestone_design_prompt("")
  assert_true(prompt.contains("Japanese"))
  assert_true(prompt.contains("MILESTONE"))
}

///|
test "PlannerAgent::build_milestone_design_prompt empty context" {
  let planner = @ralph.PlannerAgent::new()
  let prompt = planner.build_milestone_design_prompt("")
  assert_true(!(prompt.contains("## Project Context")))
  assert_true(prompt.contains("MILESTONE"))
}

///|
test "PlannerAgent::design_milestones with mock backend" {
  let planner = @ralph.PlannerAgent::new()
  let mgr = @ralph.MilestoneManager::new()
  let mock = @agent.MockBackend::new(
    default_response="MILESTONE m1: Build authentication system\nMILESTONE m2: Add API endpoints\nMILESTONE m3: Write integration tests",
  )
  let backend = mock.boxed()
  let milestones = planner.design_milestones(backend, "test project", mgr)
  assert_true(milestones.length() == 3)
  inspect(milestones[0].id, content="m1")
  inspect(milestones[0].goal, content="Build authentication system")
  inspect(milestones[1].id, content="m2")
  inspect(milestones[2].id, content="m3")
}

///|
test "PlannerAgent::plan with mock backend" {
  let planner = @ralph.PlannerAgent::new()
  let mgr = @ralph.MilestoneManager::new()
  let mock = @agent.MockBackend::new(
    default_response="WAVE 0:\n1. Create schema\n2. Write migrations\n\nWAVE 1:\n1. Build handlers",
  )
  let backend = mock.boxed()
  let milestone : @types.Milestone = {
    id: "m1",
    goal: "Build auth",
    status: @types.MilestoneStatus::Pending,
    tasks: [],
    current_wave: 0,
  }
  let tasks = planner.plan(milestone, backend, "", mgr)
  assert_true(tasks.length() == 3)
  inspect(tasks[0].description, content="Create schema")
  inspect(tasks[2].wave, content="1")
}
