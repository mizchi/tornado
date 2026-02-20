test "Task::new creates pending task" {
  let t = @types.Task::new("t1", "do something")
  inspect(t.status, content="Pending")
  inspect(t.result, content="None")
  inspect(t.parent_id, content="None")
}

test "Task::assign sets InProgress" {
  let t = @types.Task::new("t1", "do something")
  t.assign("agent-1")
  inspect(t.status, content="InProgress(\"agent-1\")")
  assert_true(not(t.is_pending()))
  assert_true(not(t.is_done()))
}

test "Task::complete sets Done" {
  let t = @types.Task::new("t1", "do something")
  t.assign("agent-1")
  t.complete("result here")
  inspect(t.status, content="Done")
  inspect(t.result, content="Some(\"result here\")")
  assert_true(t.is_done())
}

test "Task::fail sets Failed" {
  let t = @types.Task::new("t1", "do something")
  t.fail("error occurred")
  inspect(t.status, content="Failed(\"error occurred\")")
}

test "Session::new creates active session" {
  let s = @types.Session::new("s1", "build api", [])
  inspect(s.status, content="Active")
  inspect(s.current_phase, content="Decomposing")
  assert_true(s.tasks.is_empty())
}

test "OrchestratorCallbacks::noop does not panic" {
  let cb = @types.OrchestratorCallbacks::noop()
  (cb.on_agent_output)("a1", "line")
  (cb.on_agent_complete)("a1", "done")
  (cb.on_review_complete)("t1", @types.ReviewVerdict::Approved)
  (cb.on_phase_change)("s1", @types.OrchestratorPhase::Executing)
  (cb.on_session_complete)("s1")
}

test "AgentKind show" {
  inspect(@types.AgentKind::ClaudeCode, content="ClaudeCode")
  inspect(@types.AgentKind::Codex, content="Codex")
  inspect(@types.AgentKind::Api, content="Api")
  inspect(@types.AgentKind::Mock, content="Mock")
}

test "AgentRole show" {
  inspect(@types.AgentRole::Dev, content="Dev")
  inspect(@types.AgentRole::Review, content="Review")
  inspect(@types.AgentRole::Orchestrator, content="Orchestrator")
}

test "ReviewVerdict show" {
  inspect(@types.ReviewVerdict::Approved, content="Approved")
  inspect(
    @types.ReviewVerdict::NeedsChanges(["fix typo"]),
    content="NeedsChanges([\"fix typo\"])",
  )
  inspect(
    @types.ReviewVerdict::Rejected("bad code"),
    content="Rejected(\"bad code\")",
  )
}

test "Task with parent_id" {
  let t = @types.Task::new("t2", "sub-task", parent_id=Some("t1"))
  inspect(t.parent_id, content="Some(\"t1\")")
}
