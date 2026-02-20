test "ReviewAgent::parse_verdict approved" {
  let ra = @review.ReviewAgent::new("r1")
  let verdict = ra.parse_verdict("The code looks great! <approved>")
  inspect(verdict, content="Approved")
}

test "ReviewAgent::parse_verdict needs_changes" {
  let ra = @review.ReviewAgent::new("r1")
  let verdict = ra.parse_verdict(
    "<needs_changes>fix typo, add tests</needs_changes>",
  )
  match verdict {
    @types.ReviewVerdict::NeedsChanges(items) => {
      assert_true(items.length() == 2)
      inspect(items[0], content="fix typo")
      inspect(items[1], content="add tests")
    }
    _ => fail("Expected NeedsChanges")
  }
}

test "ReviewAgent::parse_verdict rejected" {
  let ra = @review.ReviewAgent::new("r1")
  let verdict = ra.parse_verdict("<rejected>security vulnerability</rejected>")
  inspect(verdict, content="Rejected(\"security vulnerability\")")
}

test "ReviewAgent::parse_verdict defaults to approved" {
  let ra = @review.ReviewAgent::new("r1")
  let verdict = ra.parse_verdict("no tags here")
  inspect(verdict, content="Approved")
}

test "ReviewAgent::build_prompt includes perspective-specific content" {
  let ra = @review.ReviewAgent::new("r1")
  let prompt = ra.build_prompt(
    @review.ReviewPerspective::CodeQuality,
    "build API",
    "done building",
    "",
  )
  assert_true(prompt.contains("build API"))
  assert_true(prompt.contains("done building"))
  assert_true(prompt.contains("Code Quality"))
  assert_true(prompt.contains("<approved>"))
}

test "ReviewAgent::build_prompt performance perspective" {
  let ra = @review.ReviewAgent::new("r1")
  let prompt = ra.build_prompt(
    @review.ReviewPerspective::Performance,
    "optimize query",
    "optimized",
    "",
  )
  assert_true(prompt.contains("Performance"))
  assert_true(prompt.contains("Algorithmic complexity"))
}

test "ReviewAgent::build_prompt security perspective" {
  let ra = @review.ReviewAgent::new("r1")
  let prompt = ra.build_prompt(
    @review.ReviewPerspective::Security,
    "add auth",
    "added auth",
    "",
  )
  assert_true(prompt.contains("Security"))
  assert_true(prompt.contains("Injection vulnerabilities"))
}

test "ReviewAgent::build_prompt includes context when provided" {
  let ra = @review.ReviewAgent::new("r1")
  let prompt = ra.build_prompt(
    @review.ReviewPerspective::CodeQuality,
    "task",
    "output",
    "### Recent Commits\nabc123 fix bug",
  )
  assert_true(prompt.contains("Recent Commits"))
  assert_true(prompt.contains("abc123 fix bug"))
}

test "ReviewAgent::review merges 3 perspectives - all approved" {
  let mock = @agent.MockBackend::new(
    default_response="<approved> looks good",
  )
  let backend = mock.boxed()
  let ra = @review.ReviewAgent::new("r1")
  let task = @types.Task::new("t1", "implement feature")
  task.complete("feature implemented")
  let result = ra.review(task, backend)
  inspect(result.verdict, content="Approved")
  inspect(result.reviewer_id, content="r1")
  assert_true(task.review is Some(_))
}

test "ReviewAgent::review merges needs_changes with perspective tags" {
  let mock = @agent.MockBackend::new(
    default_response="<needs_changes>fix this</needs_changes>",
  )
  let backend = mock.boxed()
  let ra = @review.ReviewAgent::new("r1")
  let task = @types.Task::new("t1", "implement feature")
  task.complete("done")
  let result = ra.review(task, backend)
  match result.verdict {
    @types.ReviewVerdict::NeedsChanges(items) => {
      // Each perspective returns 1 item, tagged with perspective name
      assert_true(items.length() == 3)
      assert_true(items[0].contains("[CodeQuality]"))
      assert_true(items[1].contains("[Performance]"))
      assert_true(items[2].contains("[Security]"))
    }
    _ => fail("Expected NeedsChanges")
  }
}

test "ReviewAgent::review stops on rejected" {
  let mock = @agent.MockBackend::new(
    default_response="<rejected>critical flaw</rejected>",
  )
  let backend = mock.boxed()
  let ra = @review.ReviewAgent::new("r1")
  let task = @types.Task::new("t1", "feature")
  task.complete("done")
  let result = ra.review(task, backend)
  match result.verdict {
    @types.ReviewVerdict::Rejected(reason) =>
      assert_true(reason.contains("[CodeQuality]"))
    _ => fail("Expected Rejected")
  }
}

test "ReviewAgent::perspectives returns 3" {
  let ra = @review.ReviewAgent::new("r1")
  assert_true(ra.perspectives().length() == 3)
}

test "ReviewAgent::format_review approved" {
  let ra = @review.ReviewAgent::new("r1")
  let task = @types.Task::new("t1", "build API")
  let review : @types.ReviewResult = {
    reviewer_id: "r1",
    verdict: @types.ReviewVerdict::Approved,
    summary: "Good work",
    file_path: "",
  }
  let md = ra.format_review(task, review)
  assert_true(md.contains("**APPROVED**"))
  assert_true(md.contains("build API"))
  assert_true(md.contains("Good work"))
}

test "ReviewAgent::format_review needs_changes" {
  let ra = @review.ReviewAgent::new("r1")
  let task = @types.Task::new("t1", "build API")
  let review : @types.ReviewResult = {
    reviewer_id: "r1",
    verdict: @types.ReviewVerdict::NeedsChanges(["fix tests", "add docs"]),
    summary: "Almost there",
    file_path: "",
  }
  let md = ra.format_review(task, review)
  assert_true(md.contains("**NEEDS CHANGES**"))
  assert_true(md.contains("- fix tests"))
  assert_true(md.contains("- add docs"))
}

test "ReviewAgent::parse_verdict prefers approved over needs_changes" {
  let ra = @review.ReviewAgent::new("r1")
  // <approved> appears before <needs_changes>, so approved wins
  let verdict = ra.parse_verdict(
    "<approved> but also <needs_changes>fix</needs_changes>",
  )
  inspect(verdict, content="Approved")
}

test "ReviewAgent::parse_verdict handles malformed close tag" {
  let ra = @review.ReviewAgent::new("r1")
  // Open tag without matching close tag
  let verdict = ra.parse_verdict("<needs_changes>fix this")
  // Falls through to default Approved since no close tag
  inspect(verdict, content="Approved")
}

test "ReviewAgent::parse_verdict treats empty needs_changes as approved" {
  let ra = @review.ReviewAgent::new("r1")
  let verdict = ra.parse_verdict("<needs_changes></needs_changes>")
  // Empty tag should fall through to Approved, not trigger spurious rework
  inspect(verdict, content="Approved")
}

test "ReviewAgent::parse_verdict treats whitespace-only needs_changes as approved" {
  let ra = @review.ReviewAgent::new("r1")
  let verdict = ra.parse_verdict("<needs_changes>   ,  , </needs_changes>")
  // All items are whitespace/empty after trim — should be Approved
  inspect(verdict, content="Approved")
}

test "extract_tag_content with close before open" {
  let ra = @review.ReviewAgent::new("r1")
  // close tag appears but no proper open/close pair
  let verdict = ra.parse_verdict(
    "</needs_changes>content<needs_changes>",
  )
  // No valid tag extraction, falls to default
  inspect(verdict, content="Approved")
}

test "extract_tag_content finds close tag after open, not before" {
  let ra = @review.ReviewAgent::new("r1")
  // Close tag first, then a real open/close pair — should extract from the real pair
  let verdict = ra.parse_verdict(
    "preamble </needs_changes>noise <needs_changes>fix naming</needs_changes>",
  )
  match verdict {
    @types.ReviewVerdict::NeedsChanges(items) => {
      assert_true(items.length() == 1)
      inspect(items[0], content="fix naming")
    }
    _ => fail("Expected NeedsChanges, got \{verdict}")
  }
}

test "extract_tag_content with rejected tag nested in text" {
  let ra = @review.ReviewAgent::new("r1")
  let verdict = ra.parse_verdict(
    "Some analysis... </rejected>stale<rejected>real issue</rejected> more text",
  )
  match verdict {
    @types.ReviewVerdict::Rejected(reason) =>
      inspect(reason, content="real issue")
    _ => fail("Expected Rejected, got \{verdict}")
  }
}

test "parse_verdict with surrounding noise extracts correctly" {
  let ra = @review.ReviewAgent::new("r1")
  let input = "I reviewed the code carefully.\n\n<needs_changes>add error handling, improve naming</needs_changes>\n\nOverall the code needs work."
  let verdict = ra.parse_verdict(input)
  match verdict {
    @types.ReviewVerdict::NeedsChanges(items) => {
      assert_true(items.length() == 2)
      inspect(items[0], content="add error handling")
      inspect(items[1], content="improve naming")
    }
    _ => fail("Expected NeedsChanges")
  }
}

test "review_perspective propagates backend failure instead of silent approval" {
  // When the review backend fails, review_perspective should NOT return Approved.
  // Previously, a failing backend returned empty content, and parse_verdict("")
  // defaulted to Approved — silently approving without any actual review.
  let failing = @agent.FailingMockBackend::new(error_msg="API rate limit exceeded")
  let backend = failing.boxed()
  let ra = @review.ReviewAgent::new("r1")
  let task = @types.Task::new("t1", "implement auth")
  task.complete("some code")
  let result = ra.review_perspective(
    @review.ReviewPerspective::CodeQuality,
    task,
    backend,
    "",
  )
  // The verdict should indicate failure, NOT silently approve
  match result.verdict {
    @types.ReviewVerdict::Rejected(reason) => {
      assert_true(reason.contains("API rate limit exceeded"))
    }
    other => fail("Expected Rejected on backend failure, got \{other}")
  }
}

test "review merges correctly when one perspective backend fails" {
  // When a backend fails during multi-perspective review, the merged result
  // should reflect the failure rather than silently approving.
  let failing = @agent.FailingMockBackend::new(error_msg="connection timeout")
  let backend = failing.boxed()
  let ra = @review.ReviewAgent::new("r1")
  let task = @types.Task::new("t1", "implement feature")
  task.complete("done")
  let result = ra.review(task, backend)
  // Should be Rejected since the review backend failed, not silently Approved
  match result.verdict {
    @types.ReviewVerdict::Rejected(reason) => {
      assert_true(reason.contains("connection timeout"))
    }
    other => fail("Expected Rejected on backend failure, got \{other}")
  }
}
