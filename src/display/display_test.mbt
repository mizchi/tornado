// === truncate ===

///|
test "truncate short string unchanged" {
  let result = @display.truncate("hello", 10)
  inspect(result, content="hello")
}

///|
test "truncate at exact max length unchanged" {
  let result = @display.truncate("12345", 5)
  inspect(result, content="12345")
}

///|
test "truncate long string adds ellipsis" {
  let result = @display.truncate("hello world", 5)
  inspect(result, content="hello...")
}

///|
test "truncate empty string unchanged" {
  let result = @display.truncate("", 10)
  inspect(result, content="")
}

// === format_agent_output_line ===

///|
test "format_agent_output_line strips Claude marker" {
  let result = @display.format_agent_output_line(
    "⏺ 分析結果をまとめます。",
  )
  inspect(result, content="Some(\"分析結果をまとめます。\")")
}

///|
test "format_agent_output_line strips Codex bullet marker" {
  let result = @display.format_agent_output_line(
    "• Ran \"/bin/zsh -lc 'moon check --target js'\"",
  )
  inspect(
    result,
    content="Some(\"Ran \\\"/bin/zsh -lc 'moon check --target js'\\\"\")",
  )
}

///|
test "format_agent_output_line strips tree marker" {
  let result = @display.format_agent_output_line(
    "  └ Finished. moon: ran 86 tasks, now up to date",
  )
  inspect(
    result,
    content="Some(\"Finished. moon: ran 86 tasks, now up to date\")",
  )
}

///|
test "format_agent_output_line hides separator line" {
  let result = @display.format_agent_output_line(
    "────────────────────────────────────",
  )
  inspect(result, content="None")
}

///|
test "format_agent_output_line keeps plain line" {
  let result = @display.format_agent_output_line("検証は通りました。")
  inspect(result, content="Some(\"検証は通りました。\")")
}

///|
test "format_agent_panel_entry prefixes normalized line" {
  let result = @display.format_agent_panel_entry(
    "dev-1", "• Ran \"/bin/zsh -lc 'moon check --target js'\"",
  )
  inspect(
    result,
    content="Some(\"  [dev-1] Ran \\\"/bin/zsh -lc 'moon check --target js'\\\"\")",
  )
}

///|
test "format_agent_panel_entry hides separator line" {
  let result = @display.format_agent_panel_entry(
    "dev-1", "────────────────────────",
  )
  inspect(result, content="None")
}

// === orchestrator/status line helpers ===

///|
test "format_task_start_line renders task banner" {
  let result = @display.format_task_start_line("t1", "build API")
  inspect(result, content="[t1] Starting: build API")
}

///|
test "format_task_assign_line renders assignment banner" {
  let result = @display.format_task_assign_line("t2")
  inspect(result, content="[t2] Assigned")
}

///|
test "format_review_start_line renders review banner" {
  let result = @display.format_review_start_line("t1")
  inspect(result, content="[t1] Review starting")
}

///|
test "format_task_complete_line renders phase log line" {
  let result = @display.format_task_complete_line("t1", "done")
  inspect(result, content="Task t1 -> done")
}

///|
test "format_review_complete_line renders verdict line" {
  let result = @display.format_review_complete_line("t1", "APPROVED")
  inspect(result, content="Review t1: APPROVED")
}

///|
test "format_phase_change_line renders phase line" {
  let result = @display.format_phase_change_line("Executing")
  inspect(result, content="Phase: Executing")
}

///|
test "format_session_complete_line renders completion line" {
  let result = @display.format_session_complete_line()
  inspect(result, content="[session complete]")
}

// === format_cli_log_line ===

///|
test "format_cli_log_line keeps info plain" {
  let result = @display.format_cli_log_line("INFO", "Task t1 -> done")
  inspect(result, content="Task t1 -> done")
}

///|
test "format_cli_log_line keeps heartbeat plain" {
  let result = @display.format_cli_log_line("HEARTBEAT", "=== Iteration 3 ===")
  inspect(result, content="=== Iteration 3 ===")
}

///|
test "format_cli_log_line prefixes warning" {
  let result = @display.format_cli_log_line("WARN", "Plan file is empty")
  inspect(result, content="Warning: Plan file is empty")
}

///|
test "format_cli_log_line prefixes error" {
  let result = @display.format_cli_log_line("ERROR", "Backend not found")
  inspect(result, content="Error: Backend not found")
}

///|
test "format_cli_log_line prefixes usage" {
  let result = @display.format_cli_log_line("USAGE", "Iter 1: 10in/5out")
  inspect(result, content="Usage: Iter 1: 10in/5out")
}

///|
test "format_cli_log_line falls back to level tag" {
  let result = @display.format_cli_log_line("OTHER", "message")
  inspect(result, content="[OTHER] message")
}

// === count_lines ===

///|
test "count_lines empty string returns 0" {
  inspect(@display.count_lines(""), content="0")
}

///|
test "count_lines single line no newline" {
  inspect(@display.count_lines("hello"), content="1")
}

///|
test "count_lines single line with trailing newline" {
  inspect(@display.count_lines("hello\n"), content="1")
}

///|
test "count_lines multiple lines" {
  inspect(@display.count_lines("a\nb\nc"), content="3")
}

///|
test "count_lines multiple lines with trailing newline" {
  inspect(@display.count_lines("a\nb\nc\n"), content="3")
}

///|
test "count_lines only newlines" {
  inspect(@display.count_lines("\n\n"), content="2")
}

// === format_tool_call ===

///|
test "format_tool_call Read extracts file_path" {
  let input = "{\"file_path\":\"/src/main.mbt\"}"
  let result = @display.format_tool_call("Read", input)
  inspect(result, content="Read(/src/main.mbt)")
}

///|
test "format_tool_call Edit shows path and old/new" {
  let input = "{\"file_path\":\"/src/main.mbt\",\"old_string\":\"hello\",\"new_string\":\"world\"}"
  let result = @display.format_tool_call("Edit", input)
  assert_true(result.contains("Edit(/src/main.mbt)"))
  assert_true(result.contains("old: hello"))
  assert_true(result.contains("new: world"))
}

///|
test "format_tool_call Write shows path and char count" {
  let input = "{\"file_path\":\"/src/out.mbt\",\"content\":\"hello world\"}"
  let result = @display.format_tool_call("Write", input)
  inspect(result, content="Write(/src/out.mbt, 11 chars)")
}

///|
test "format_tool_call Bash shows command" {
  let input = "{\"command\":\"moon test\"}"
  let result = @display.format_tool_call("Bash", input)
  inspect(result, content="Bash(moon test)")
}

///|
test "format_tool_call Glob shows pattern" {
  let input = "{\"pattern\":\"**/*.mbt\"}"
  let result = @display.format_tool_call("Glob", input)
  inspect(result, content="Glob(**/*.mbt)")
}

///|
test "format_tool_call Grep shows pattern and path" {
  let input = "{\"pattern\":\"TODO\",\"path\":\"/src\"}"
  let result = @display.format_tool_call("Grep", input)
  inspect(result, content="Grep(TODO in /src)")
}

///|
test "format_tool_call Grep without path" {
  let input = "{\"pattern\":\"TODO\"}"
  let result = @display.format_tool_call("Grep", input)
  inspect(result, content="Grep(TODO)")
}

///|
test "format_tool_call Task shows agent and description" {
  let input = "{\"subagent_type\":\"Explore\",\"description\":\"find files\"}"
  let result = @display.format_tool_call("Task", input)
  inspect(result, content="Task(Explore: find files)")
}

///|
test "format_tool_call unknown tool falls back to truncated json" {
  let input = "{\"key\":\"value\"}"
  let result = @display.format_tool_call("Unknown", input)
  inspect(result, content="Unknown({\"key\":\"value\"})")
}

///|
test "format_tool_call invalid JSON falls back gracefully" {
  let input = "not json at all"
  let result = @display.format_tool_call("Read", input)
  inspect(result, content="Read(not json at all)")
}

///|
test "format_tool_call missing fields shows ?" {
  let input = "{}"
  let result = @display.format_tool_call("Read", input)
  inspect(result, content="Read(?)")
}

// === format_tool_result ===

///|
test "format_tool_result Read shows line count" {
  let output = "line1\nline2\nline3"
  let result = @display.format_tool_result("Read", output)
  inspect(result, content="Read: 3 lines")
}

///|
test "format_tool_result Read empty output shows 0 lines" {
  let result = @display.format_tool_result("Read", "")
  inspect(result, content="Read: 0 lines")
}

///|
test "format_tool_result Edit truncates output" {
  let result = @display.format_tool_result("Edit", "success")
  inspect(result, content="Edit: success")
}

///|
test "format_tool_result Write truncates output" {
  let result = @display.format_tool_result("Write", "ok")
  inspect(result, content="Write: ok")
}

///|
test "format_tool_result Bash short output shown inline" {
  let result = @display.format_tool_result("Bash", "ok")
  inspect(result, content="Bash: ok")
}

///|
test "format_tool_result Bash multi-line shows line count" {
  let output = "line1\nline2\nline3\nline4\nline5"
  let result = @display.format_tool_result("Bash", output)
  inspect(result, content="Bash: 5 lines")
}

///|
test "format_tool_result Glob truncates" {
  let result = @display.format_tool_result("Glob", "a.mbt\nb.mbt")
  inspect(result, content="Glob: a.mbt\nb.mbt")
}

///|
test "format_tool_result Grep truncates" {
  let result = @display.format_tool_result("Grep", "match found")
  inspect(result, content="Grep: match found")
}

///|
test "format_tool_result unknown tool" {
  let result = @display.format_tool_result("WebSearch", "results...")
  inspect(result, content="WebSearch: results...")
}
