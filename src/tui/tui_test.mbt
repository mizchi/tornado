test "TuiState::new starts empty" {
  let state = @tui.TuiState::new()
  assert_true(state.active_session() is None)
}

test "TuiState::add_session" {
  let state = @tui.TuiState::new()
  let session = @types.Session::new("s1", "task", [])
  state.add_session(session)
  assert_true(state.active_session() is Some(_))
}

test "TuiState::append_log and get_logs" {
  let state = @tui.TuiState::new()
  state.append_log("agent-1", "line 1")
  state.append_log("agent-1", "line 2")
  let logs = state.get_logs("agent-1")
  assert_true(logs.length() == 2)
  inspect(logs[0], content="line 1")
  inspect(logs[1], content="line 2")
}

test "TuiState::get_logs respects max_lines" {
  let state = @tui.TuiState::new()
  for i = 0; i < 30; i = i + 1 {
    state.append_log("a1", "line \{i}")
  }
  let logs = state.get_logs("a1", max_lines=5)
  assert_true(logs.length() == 5)
  inspect(logs[0], content="line 25")
}

test "TuiState::next_tab and prev_tab" {
  let state = @tui.TuiState::new()
  let agents : Array[@types.AgentConfig] = [
    {
      id: "a1",
      kind: Mock,
      role: Dev,
      model: None,
      system_prompt: None,
      working_dir: ".",
      max_iterations: 10,
    },
    {
      id: "a2",
      kind: Mock,
      role: Dev,
      model: None,
      system_prompt: None,
      working_dir: ".",
      max_iterations: 10,
    },
  ]
  let session = @types.Session::new("s1", "task", agents)
  state.add_session(session)
  assert_true(state.active_tab == 0)
  state.next_tab()
  assert_true(state.active_tab == 1)
  state.next_tab()
  assert_true(state.active_tab == 0) // wrap around
  state.prev_tab()
  assert_true(state.active_tab == 1) // wrap around backwards
}

test "TuiState::make_callbacks logs all events" {
  let state = @tui.TuiState::new()
  let cb = state.make_callbacks()
  // on_agent_output → agent logs
  (cb.on_agent_output)("a1", "hello")
  let logs = state.get_logs("a1")
  assert_true(logs.length() == 1)
  inspect(logs[0], content="hello")
  // on_phase_change → phase_log
  (cb.on_phase_change)("s1", @types.OrchestratorPhase::Executing)
  assert_true(state.phase_log.length() == 1)
  // on_task_start → agent logs
  (cb.on_task_start)("t1", "build API", "a1")
  let logs2 = state.get_logs("a1")
  assert_true(logs2.length() == 2)
  assert_true(logs2[1].contains("[t1]"))
  assert_true(logs2[1].contains("build API"))
  // on_task_complete → phase_log
  (cb.on_task_complete)("t1", "done")
  assert_true(state.phase_log.iter().any(fn(e) { e.contains("Task t1") }))
  // on_task_assign → agent logs
  (cb.on_task_assign)("t2", "a1")
  let logs3 = state.get_logs("a1")
  assert_true(logs3.iter().any(fn(e) { e.contains("[t2]") && e.contains("Assigned") }))
  // on_review_start → reviewer logs
  (cb.on_review_start)("t1", "r1")
  let rlogs = state.get_logs("r1")
  assert_true(rlogs.iter().any(fn(e) { e.contains("Review starting") }))
  // on_info → phase_log
  (cb.on_info)("something happened")
  assert_true(state.phase_log.iter().any(fn(e) { e.contains("something happened") }))
}

test "TuiState::make_callbacks surfaces task failure" {
  let state = @tui.TuiState::new()
  let cb = state.make_callbacks()
  // Simulate a task failure
  (cb.on_task_start)("t1", "deploy", "dev-1")
  (cb.on_task_complete)("t1", "failed: connection refused")
  // Task failure should be visible in phase_log
  assert_true(
    state.phase_log.iter().any(fn(e) {
      e.contains("failed") && e.contains("t1")
    }),
  )
  // Agent log should show the task started
  let logs = state.get_logs("dev-1")
  assert_true(logs.iter().any(fn(e) { e.contains("deploy") }))
}

test "render_app with no session" {
  let state = @tui.TuiState::new()
  let node = @tui.render_app(state)
  let output = @vnode.render_vnode_once(80, 24, node)
  assert_true(output.length() > 0)
}

test "render_app with session" {
  let state = @tui.TuiState::new()
  let agents : Array[@types.AgentConfig] = [
    {
      id: "dev-1",
      kind: ClaudeCode,
      role: Dev,
      model: None,
      system_prompt: None,
      working_dir: ".",
      max_iterations: 10,
    },
  ]
  let session = @types.Session::new("s1", "build api", agents)
  state.add_session(session)
  state.append_log("dev-1", "Working on it...")
  let node = @tui.render_app(state)
  let output = @vnode.render_vnode_once(80, 24, node)
  assert_true(output.length() > 0)
}
