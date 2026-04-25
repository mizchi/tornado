///|
test "MilestoneManager::new creates empty manager" {
  let mgr = @ralph.MilestoneManager::new()
  assert_true(mgr.milestones.is_empty())
  assert_true(mgr.all_milestones_done())
}

///|
test "MilestoneManager::load_from_json roundtrip" {
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1",
    #|      "goal": "Build auth",
    #|      "status": "pending",
    #|      "current_wave": 0,
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "Create schema", "wave": 0, "status": "pending" },
    #|        { "id": "m1-t2", "description": "Build handlers", "wave": 1, "status": "pending" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  assert_true(mgr.milestones.length() == 1)
  inspect(mgr.milestones[0].id, content="m1")
  inspect(mgr.milestones[0].goal, content="Build auth")
  assert_true(mgr.milestones[0].tasks.length() == 2)
  // Roundtrip
  let serialized = mgr.to_json()
  let mgr2 = @ralph.MilestoneManager::load_from_json(serialized)
  assert_true(mgr2.milestones.length() == 1)
  inspect(mgr2.milestones[0].id, content="m1")
  assert_true(mgr2.milestones[0].tasks.length() == 2)
}

///|
test "next_pending_milestone returns first pending" {
  let json =
    #|{
    #|  "milestones": [
    #|    { "id": "m1", "goal": "A", "status": "done", "tasks": [] },
    #|    { "id": "m2", "goal": "B", "status": "pending", "tasks": [] },
    #|    { "id": "m3", "goal": "C", "status": "pending", "tasks": [] }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let next = mgr.next_pending_milestone()
  assert_true(next is Some(_))
  inspect(next.unwrap().id, content="m2")
}

///|
test "next_pending_milestone returns None when all done" {
  let json =
    #|{
    #|  "milestones": [
    #|    { "id": "m1", "goal": "A", "status": "done", "tasks": [] }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  assert_true(mgr.next_pending_milestone() is None)
}

///|
test "get_wave_tasks filters by wave" {
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "A", "status": "pending",
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "a", "wave": 0, "status": "pending" },
    #|        { "id": "m1-t2", "description": "b", "wave": 0, "status": "pending" },
    #|        { "id": "m1-t3", "description": "c", "wave": 1, "status": "pending" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let wave0 = mgr.get_wave_tasks(mgr.milestones[0], 0)
  assert_true(wave0.length() == 2)
  let wave1 = mgr.get_wave_tasks(mgr.milestones[0], 1)
  assert_true(wave1.length() == 1)
  inspect(wave1[0].id, content="m1-t3")
}

///|
test "has_undone_tasks detects pending tasks" {
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "A", "status": "pending",
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "a", "wave": 0, "status": "done" },
    #|        { "id": "m1-t2", "description": "b", "wave": 0, "status": "pending" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  assert_true(mgr.has_undone_tasks(mgr.milestones[0]))
}

///|
test "has_undone_tasks returns false when all done" {
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "A", "status": "pending",
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "a", "wave": 0, "status": "done" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  assert_true(!(mgr.has_undone_tasks(mgr.milestones[0])))
}

///|
test "next_wave_number finds lowest pending wave" {
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "A", "status": "pending",
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "a", "wave": 0, "status": "done" },
    #|        { "id": "m1-t2", "description": "b", "wave": 1, "status": "pending" },
    #|        { "id": "m1-t3", "description": "c", "wave": 2, "status": "pending" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  inspect(mgr.next_wave_number(mgr.milestones[0]), content="Some(1)")
}

///|
test "parse_planner_output parses WAVE format" {
  let mgr = @ralph.MilestoneManager::new()
  let output =
    #|WAVE 0:
    #|1. Create database schema
    #|2. Write migration scripts
    #|
    #|WAVE 1:
    #|1. Build API handlers
    #|2. Add authentication
  let tasks = mgr.parse_planner_output(output, "m1")
  assert_true(tasks.length() == 4)
  inspect(tasks[0].wave, content="0")
  inspect(tasks[0].description, content="Create database schema")
  inspect(tasks[1].wave, content="0")
  inspect(tasks[1].description, content="Write migration scripts")
  inspect(tasks[2].wave, content="1")
  inspect(tasks[2].description, content="Build API handlers")
  inspect(tasks[3].wave, content="1")
  inspect(tasks[3].description, content="Add authentication")
}

///|
test "parse_planner_output with dash items" {
  let mgr = @ralph.MilestoneManager::new()
  let output =
    #|WAVE 0:
    #|- Set up project structure
    #|- Install dependencies
  let tasks = mgr.parse_planner_output(output, "m1")
  assert_true(tasks.length() == 2)
  inspect(tasks[0].description, content="Set up project structure")
}

///|
test "gen_task_id generates unique ids" {
  let mgr = @ralph.MilestoneManager::new()
  let id1 = mgr.gen_task_id("m1")
  let id2 = mgr.gen_task_id("m1")
  assert_true(id1 != id2)
  inspect(id1, content="m1-t1")
  inspect(id2, content="m1-t2")
}

///|
test "all_milestones_done with mixed statuses" {
  let json =
    #|{
    #|  "milestones": [
    #|    { "id": "m1", "goal": "A", "status": "done", "tasks": [] },
    #|    { "id": "m2", "goal": "B", "status": "pending", "tasks": [] }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  assert_true(!(mgr.all_milestones_done()))
}

///|
test "parse_milestone_design parses MILESTONE format" {
  let mgr = @ralph.MilestoneManager::new()
  let output =
    #|MILESTONE m1: Build authentication system
    #|MILESTONE m2: Add API endpoints
    #|MILESTONE m3: Write integration tests
  let milestones = mgr.parse_milestone_design(output)
  assert_true(milestones.length() == 3)
  inspect(milestones[0].id, content="m1")
  inspect(milestones[0].goal, content="Build authentication system")
  inspect(milestones[1].id, content="m2")
  inspect(milestones[1].goal, content="Add API endpoints")
  inspect(milestones[2].id, content="m3")
  inspect(milestones[2].goal, content="Write integration tests")
}

///|
test "parse_milestone_design ignores non-milestone lines" {
  let mgr = @ralph.MilestoneManager::new()
  let output =
    #|Here are the milestones:
    #|
    #|MILESTONE m1: First goal
    #|Some extra explanation
    #|MILESTONE m2: Second goal
  let milestones = mgr.parse_milestone_design(output)
  assert_true(milestones.length() == 2)
  inspect(milestones[0].id, content="m1")
  inspect(milestones[1].id, content="m2")
}

///|
test "parse_milestone_design empty output" {
  let mgr = @ralph.MilestoneManager::new()
  let milestones = mgr.parse_milestone_design("")
  assert_true(milestones.is_empty())
}

///|
test "parse_milestone_design milestones have pending status" {
  let mgr = @ralph.MilestoneManager::new()
  let output = "MILESTONE m1: Do something"
  let milestones = mgr.parse_milestone_design(output)
  assert_true(milestones.length() == 1)
  assert_true(milestones[0].status == @types.MilestoneStatus::Pending)
  assert_true(milestones[0].tasks.is_empty())
  inspect(milestones[0].current_wave, content="0")
}

///|
test "add_milestones appends to existing" {
  let json =
    #|{
    #|  "milestones": [
    #|    { "id": "m1", "goal": "A", "status": "done", "tasks": [] }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  assert_true(mgr.milestones.length() == 1)
  let new_milestones : Array[@types.Milestone] = [
    {
      id: "m2",
      goal: "B",
      status: @types.MilestoneStatus::Pending,
      tasks: [],
      current_wave: 0,
    },
    {
      id: "m3",
      goal: "C",
      status: @types.MilestoneStatus::Pending,
      tasks: [],
      current_wave: 0,
    },
  ]
  mgr.add_milestones(new_milestones)
  assert_true(mgr.milestones.length() == 3)
  inspect(mgr.milestones[1].id, content="m2")
  inspect(mgr.milestones[2].id, content="m3")
}

///|
test "load_from_json sets next_task_id correctly" {
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "A", "status": "pending",
    #|      "tasks": [
    #|        { "id": "m1-t5", "description": "a", "wave": 0, "status": "pending" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  let new_id = mgr.gen_task_id("m1")
  inspect(new_id, content="m1-t6")
}

///|
test "has_undone_tasks treats failed tasks as undone" {
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "A", "status": "pending",
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "a", "wave": 0, "status": "done" },
    #|        { "id": "m1-t2", "description": "b", "wave": 0, "status": "failed" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  // Failed tasks should be considered undone so they can be retried
  assert_true(mgr.has_undone_tasks(mgr.milestones[0]))
}

///|
test "next_wave_number includes waves with failed tasks" {
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "A", "status": "pending",
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "a", "wave": 0, "status": "done" },
    #|        { "id": "m1-t2", "description": "b", "wave": 1, "status": "failed" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  // Wave 1 has a failed task, should be returned as next wave
  inspect(mgr.next_wave_number(mgr.milestones[0]), content="Some(1)")
}

///|
test "milestone serialization roundtrip preserves failure reason" {
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "A", "status": "failed",
    #|      "failure_reason": "Architecture fundamentally flawed",
    #|      "current_wave": 0,
    #|      "tasks": [
    #|        { "id": "m1-t1", "description": "a", "wave": 0, "status": "failed",
    #|          "failure_reason": "API rate limit exceeded" }
    #|      ]
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  // Verify original failure reasons are loaded
  match mgr.milestones[0].status {
    @types.MilestoneStatus::Failed(reason) =>
      inspect(reason, content="Architecture fundamentally flawed")
    _ => fail("Expected Failed status")
  }
  match mgr.milestones[0].tasks[0].status {
    @types.TaskStatus::Failed(reason) =>
      inspect(reason, content="API rate limit exceeded")
    _ => fail("Expected Failed task status")
  }
  // Roundtrip: serialize and reload
  let serialized = mgr.to_json()
  let mgr2 = @ralph.MilestoneManager::load_from_json(serialized)
  match mgr2.milestones[0].status {
    @types.MilestoneStatus::Failed(reason) =>
      inspect(reason, content="Architecture fundamentally flawed")
    _ => fail("Expected Failed status after roundtrip")
  }
  match mgr2.milestones[0].tasks[0].status {
    @types.TaskStatus::Failed(reason) =>
      inspect(reason, content="API rate limit exceeded")
    _ => fail("Expected Failed task status after roundtrip")
  }
}

///|
test "milestone serialization roundtrip preserves special characters" {
  // Test that json_escape handles \n, \t, quotes via a milestone with special chars in goal
  let mgr = @ralph.MilestoneManager::new()
  let milestones : Array[@types.Milestone] = [
    {
      id: "m1",
      goal: "Build \"auth\" with\nnewlines\tand\ttabs",
      status: @types.MilestoneStatus::Pending,
      tasks: [],
      current_wave: 0,
    },
  ]
  mgr.add_milestones(milestones)
  // Serialize and reload
  let serialized = mgr.to_json()
  let mgr2 = @ralph.MilestoneManager::load_from_json(serialized)
  inspect(
    mgr2.milestones[0].goal,
    content="Build \"auth\" with\nnewlines\tand\ttabs",
  )
}

///|
test "milestone serialization roundtrip with carriage return" {
  let json =
    #|{
    #|  "milestones": [
    #|    {
    #|      "id": "m1", "goal": "test", "status": "failed",
    #|      "failure_reason": "error with\r\nwindows newlines",
    #|      "current_wave": 0,
    #|      "tasks": []
    #|    }
    #|  ]
    #|}
  let mgr = @ralph.MilestoneManager::load_from_json(json)
  match mgr.milestones[0].status {
    @types.MilestoneStatus::Failed(reason) =>
      assert_true(reason.contains("windows newlines"))
    _ => fail("Expected Failed status")
  }
  // Roundtrip
  let serialized = mgr.to_json()
  let mgr2 = @ralph.MilestoneManager::load_from_json(serialized)
  match mgr2.milestones[0].status {
    @types.MilestoneStatus::Failed(reason) =>
      assert_true(reason.contains("windows newlines"))
    _ => fail("Expected Failed status after roundtrip")
  }
}
