test "VerifierAgent::parse_verdict approved" {
  let v = @ralph.VerifierAgent::new()
  let verdict = v.parse_verdict("All looks good. <wave_approved>")
  inspect(verdict, content="Approved")
}

test "VerifierAgent::parse_verdict needs_rework" {
  let v = @ralph.VerifierAgent::new()
  let verdict = v.parse_verdict(
    "Some issues found.\n<needs_rework>m1-t1: fix error handling\nm1-t2: add tests</needs_rework>",
  )
  match verdict {
    NeedsRework(items) => {
      assert_true(items.length() == 2)
      assert_true(items[0].contains("m1-t1"))
      assert_true(items[1].contains("m1-t2"))
    }
    _ => panic()
  }
}

test "VerifierAgent::parse_verdict milestone_failed" {
  let v = @ralph.VerifierAgent::new()
  let verdict = v.parse_verdict(
    "<milestone_failed>Critical dependency missing</milestone_failed>",
  )
  match verdict {
    MilestoneFailed(reason) => assert_true(reason.contains("Critical"))
    _ => panic()
  }
}

test "VerifierAgent::parse_verdict defaults to approved" {
  let v = @ralph.VerifierAgent::new()
  let verdict = v.parse_verdict("Everything looks fine")
  inspect(verdict, content="Approved")
}

test "VerifierAgent::build_verify_prompt includes milestone and results" {
  let v = @ralph.VerifierAgent::new()
  let milestone : @types.Milestone = {
    id: "m1",
    goal: "Build auth",
    status: @types.MilestoneStatus::InProgress,
    tasks: [],
    current_wave: 0,
  }
  let results : Array[(String, String)] = [("m1-t1", "Created schema file")]
  let prompt = v.build_verify_prompt(milestone, 0, results, "")
  assert_true(prompt.contains("m1"))
  assert_true(prompt.contains("Build auth"))
  assert_true(prompt.contains("Created schema file"))
  assert_true(prompt.contains("wave_approved"))
}

test "VerifierAgent::verify with mock backend approved" {
  let v = @ralph.VerifierAgent::new()
  let mock = @agent.MockBackend::new(
    default_response="All tasks verified. <wave_approved>",
  )
  let backend = mock.boxed()
  let milestone : @types.Milestone = {
    id: "m1",
    goal: "Build auth",
    status: @types.MilestoneStatus::InProgress,
    tasks: [],
    current_wave: 0,
  }
  let verdict = v.verify(milestone, 0, [], backend, "")
  inspect(verdict, content="Approved")
}

test "VerifierAgent::verify with mock backend needs_rework" {
  let v = @ralph.VerifierAgent::new()
  let mock = @agent.MockBackend::new(
    default_response="<needs_rework>t1: missing tests</needs_rework>",
  )
  let backend = mock.boxed()
  let milestone : @types.Milestone = {
    id: "m1",
    goal: "Build auth",
    status: @types.MilestoneStatus::InProgress,
    tasks: [],
    current_wave: 0,
  }
  let verdict = v.verify(milestone, 0, [], backend, "")
  match verdict {
    NeedsRework(items) => {
      assert_true(items.length() == 1)
      assert_true(items[0].contains("missing tests"))
    }
    _ => panic()
  }
}
