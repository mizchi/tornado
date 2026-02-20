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

test "TuiState::make_callbacks logs events" {
  let state = @tui.TuiState::new()
  let cb = state.make_callbacks()
  (cb.on_agent_output)("a1", "hello")
  let logs = state.get_logs("a1")
  assert_true(logs.length() == 1)
  inspect(logs[0], content="hello")
  (cb.on_phase_change)("s1", @types.OrchestratorPhase::Executing)
  assert_true(state.phase_log.length() == 1)
  // New callback fields don't crash
  (cb.on_task_start)("t1", "desc", "a1")
  (cb.on_task_complete)("t1", "done")
  (cb.on_task_assign)("t1", "a1")
  (cb.on_review_start)("t1", "r1")
  (cb.on_info)("hello")
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
