// === resolve_lang ===

///|
test "resolve_lang with None returns detect_lang result" {
  // When cli_lang is None, resolve_lang delegates to detect_fn
  let result = @helpers.resolve_lang(None, fn() { "ja" })
  inspect(result, content="ja")
}

///|
test "resolve_lang with auto returns detect_fn result" {
  let result = @helpers.resolve_lang(Some("auto"), fn() { "en" })
  inspect(result, content="en")
}

///|
test "resolve_lang with explicit lang returns it" {
  let result = @helpers.resolve_lang(Some("ja"), fn() { "en" })
  inspect(result, content="ja")
}

///|
test "resolve_lang with explicit en returns en" {
  let result = @helpers.resolve_lang(Some("en"), fn() { "ja" })
  inspect(result, content="en")
}

// === extract_event_ts ===

///|
test "extract_event_ts with TS prefix" {
  let (ts, msg) = @helpers.extract_event_ts("[TS:12:34:56] hello world", fn() {
    "00:00:00"
  })
  inspect(ts, content="12:34:56")
  inspect(msg, content="hello world")
}

///|
test "extract_event_ts without TS prefix" {
  let (ts, msg) = @helpers.extract_event_ts("hello world", fn() { "09:30:00" })
  inspect(ts, content="09:30:00")
  inspect(msg, content="hello world")
}

///|
test "extract_event_ts with empty message after TS" {
  let (ts, msg) = @helpers.extract_event_ts("[TS:01:02:03] ", fn() {
    "00:00:00"
  })
  inspect(ts, content="01:02:03")
  inspect(msg, content="")
}

///|
test "extract_event_ts with partial TS prefix no closing bracket" {
  let (ts, msg) = @helpers.extract_event_ts("[TS:12:34:56", fn() { "11:11:11" })
  inspect(ts, content="11:11:11")
  inspect(msg, content="[TS:12:34:56")
}

// === derive_archive_path ===

///|
test "derive_archive_path with .md extension" {
  let result = @helpers.derive_archive_path("TODO.md")
  inspect(result, content="TODO.archive.md")
}

///|
test "derive_archive_path with plan.md" {
  let result = @helpers.derive_archive_path("plan.md")
  inspect(result, content="plan.archive.md")
}

///|
test "derive_archive_path without .md extension" {
  let result = @helpers.derive_archive_path("TODO")
  inspect(result, content="TODO.archive.md")
}

///|
test "derive_archive_path with nested path" {
  let result = @helpers.derive_archive_path("docs/plan.md")
  inspect(result, content="docs/plan.archive.md")
}

///|
test "derive_archive_path short .md name" {
  // Edge case: ".md" alone (3 chars, length == 3 so goes to else branch)
  let result = @helpers.derive_archive_path(".md")
  inspect(result, content=".md.archive.md")
}

// === join_dev_outputs ===

///|
test "join_dev_outputs with empty array" {
  let result = @helpers.join_dev_outputs([])
  inspect(result, content="")
}

///|
test "join_dev_outputs with single output" {
  let result = @helpers.join_dev_outputs(["Fixed bug in parser"])
  assert_true(result.contains("### Dev Iteration 1"))
  assert_true(result.contains("Fixed bug in parser"))
}

///|
test "join_dev_outputs with multiple outputs" {
  let result = @helpers.join_dev_outputs(["output1", "output2", "output3"])
  assert_true(result.contains("### Dev Iteration 1"))
  assert_true(result.contains("### Dev Iteration 2"))
  assert_true(result.contains("### Dev Iteration 3"))
  assert_true(result.contains("output1"))
  assert_true(result.contains("output2"))
  assert_true(result.contains("output3"))
}

// === build_cycle_summary ===

///|
test "build_cycle_summary basic" {
  let result = @helpers.build_cycle_summary(1, ["dev output 1"], "review ok")
  assert_true(result.contains("## Cycle 1 Summary"))
  assert_true(result.contains("### Dev Step 1"))
  assert_true(result.contains("dev output 1"))
  assert_true(result.contains("### Review"))
  assert_true(result.contains("review ok"))
}

///|
test "build_cycle_summary with empty review" {
  let result = @helpers.build_cycle_summary(2, ["output"], "")
  assert_true(result.contains("## Cycle 2 Summary"))
  assert_true(result.contains("### Dev Step 1"))
  assert_false(result.contains("### Review"))
}

///|
test "build_cycle_summary with multiple dev outputs" {
  let result = @helpers.build_cycle_summary(3, ["a", "b"], "ok")
  assert_true(result.contains("### Dev Step 1"))
  assert_true(result.contains("### Dev Step 2"))
  assert_true(result.contains("a"))
  assert_true(result.contains("b"))
}

// === build_plan_file_task ===

///|
test "build_plan_file_task basic" {
  let result = @helpers.build_plan_file_task("TODO.md", "", "")
  assert_true(result.contains("## Plan File: TODO.md"))
  assert_true(result.contains("Read `TODO.md`"))
  assert_true(result.contains("TODO.archive.md"))
}

///|
test "build_plan_file_task with review summary" {
  let result = @helpers.build_plan_file_task("plan.md", "needs more tests", "")
  assert_true(result.contains("## Review Feedback"))
  assert_true(result.contains("needs more tests"))
}

///|
test "build_plan_file_task with context" {
  let result = @helpers.build_plan_file_task("plan.md", "", "git log context")
  assert_true(result.contains("## Current Project State"))
  assert_true(result.contains("git log context"))
}

///|
test "build_plan_file_task with empty review does not show section" {
  let result = @helpers.build_plan_file_task("plan.md", "", "")
  assert_false(result.contains("## Review Feedback"))
}

// === build_improvement_task ===

///|
test "build_improvement_task basic" {
  let result = @helpers.build_improvement_task("prev output", 1, 3, "", "")
  assert_true(result.contains("autonomous IMPROVEMENT loop"))
  assert_true(result.contains("iteration 1/3"))
  assert_true(result.contains("## Previous Iteration Output"))
  assert_true(result.contains("prev output"))
  assert_true(result.contains("## Improvement Protocol"))
}

///|
test "build_improvement_task with cycle summary" {
  let result = @helpers.build_improvement_task("", 2, 5, "summary of cycle", "")
  assert_true(result.contains("## Previous Cycle Summary"))
  assert_true(result.contains("summary of cycle"))
}

///|
test "build_improvement_task with empty prev output hides section" {
  let result = @helpers.build_improvement_task("", 1, 1, "", "")
  assert_false(result.contains("## Previous Iteration Output"))
}

///|
test "build_improvement_task with context" {
  let result = @helpers.build_improvement_task("", 1, 1, "", "some context")
  assert_true(result.contains("## Current Project State"))
  assert_true(result.contains("some context"))
}

// === SessionState JSON roundtrip ===

///|
test "session_state_to_json basic roundtrip" {
  let state : @helpers.SessionState = {
    iteration: 5,
    phase: "dev",
    task: "implement feature",
    dev_output: "done",
    review_summary: "approved",
    agent_sessions: { "dev1": "sid-123", "reviewer": "sid-456" },
    dev_since_review: 2,
    accumulated_dev_outputs: ["output1", "output2"],
  }
  let json = @helpers.session_to_json(state)
  let loaded = @helpers.session_from_json(json)
  match loaded {
    Some(s) => {
      inspect(s.iteration, content="5")
      inspect(s.phase, content="dev")
      inspect(s.task, content="implement feature")
      inspect(s.dev_output, content="done")
      inspect(s.review_summary, content="approved")
      inspect(s.dev_since_review, content="2")
      inspect(s.agent_sessions.get("dev1"), content="Some(\"sid-123\")")
      inspect(s.agent_sessions.get("reviewer"), content="Some(\"sid-456\")")
      inspect(s.accumulated_dev_outputs.length(), content="2")
      inspect(s.accumulated_dev_outputs[0], content="output1")
      inspect(s.accumulated_dev_outputs[1], content="output2")
    }
    None => panic()
  }
}

///|
test "session_from_json with empty object returns defaults" {
  let loaded = @helpers.session_from_json("{}")
  match loaded {
    Some(s) => {
      inspect(s.iteration, content="0")
      inspect(s.phase, content="idle")
      inspect(s.task, content="")
      inspect(s.dev_output, content="")
      inspect(s.review_summary, content="")
      inspect(s.dev_since_review, content="0")
      assert_true(s.agent_sessions.is_empty())
      assert_true(s.accumulated_dev_outputs.is_empty())
    }
    None => panic()
  }
}

///|
test "session_from_json with invalid json returns None" {
  let loaded = @helpers.session_from_json("not json")
  inspect(loaded, content="None")
}

///|
test "session_from_json with non-object json returns None" {
  let loaded = @helpers.session_from_json("[1,2,3]")
  inspect(loaded, content="None")
}

///|
test "session_state roundtrip with empty fields" {
  let state : @helpers.SessionState = {
    iteration: 0,
    phase: "idle",
    task: "",
    dev_output: "",
    review_summary: "",
    agent_sessions: {},
    dev_since_review: 0,
    accumulated_dev_outputs: [],
  }
  let json = @helpers.session_to_json(state)
  let loaded = @helpers.session_from_json(json)
  match loaded {
    Some(s) => {
      inspect(s.iteration, content="0")
      inspect(s.phase, content="idle")
      assert_true(s.task.is_empty())
      assert_true(s.agent_sessions.is_empty())
      assert_true(s.accumulated_dev_outputs.is_empty())
    }
    None => panic()
  }
}

// === find_agent_id ===

///|
test "find_agent_id finds dev agent" {
  let agents = [
    @helpers.SimpleAgent::{ id: "dev1", kind: "claude-code", role: "dev" },
    @helpers.SimpleAgent::{ id: "rev1", kind: "claude", role: "review" },
  ]
  let result = @helpers.find_agent_id(agents, "dev")
  inspect(result, content="Some(\"dev1\")")
}

///|
test "find_agent_id finds review agent" {
  let agents = [
    @helpers.SimpleAgent::{ id: "dev1", kind: "claude-code", role: "dev" },
    @helpers.SimpleAgent::{ id: "rev1", kind: "claude", role: "review" },
  ]
  let result = @helpers.find_agent_id(agents, "review")
  inspect(result, content="Some(\"rev1\")")
}

///|
test "find_agent_id returns None when not found" {
  let agents : Array[@helpers.SimpleAgent] = [
    @helpers.SimpleAgent::{ id: "dev1", kind: "claude-code", role: "dev" },
  ]
  let result = @helpers.find_agent_id(agents, "review")
  inspect(result, content="None")
}

///|
test "find_agent_id with empty array" {
  let agents : Array[@helpers.SimpleAgent] = []
  let result = @helpers.find_agent_id(agents, "dev")
  inspect(result, content="None")
}
