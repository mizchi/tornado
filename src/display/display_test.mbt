// === truncate ===

test "truncate short string unchanged" {
  let result = @display.truncate("hello", 10)
  inspect(result, content="hello")
}

test "truncate at exact max length unchanged" {
  let result = @display.truncate("12345", 5)
  inspect(result, content="12345")
}

test "truncate long string adds ellipsis" {
  let result = @display.truncate("hello world", 5)
  inspect(result, content="hello...")
}

test "truncate empty string unchanged" {
  let result = @display.truncate("", 10)
  inspect(result, content="")
}

// === count_lines ===

test "count_lines empty string returns 0" {
  inspect(@display.count_lines(""), content="0")
}

test "count_lines single line no newline" {
  inspect(@display.count_lines("hello"), content="1")
}

test "count_lines single line with trailing newline" {
  inspect(@display.count_lines("hello\n"), content="1")
}

test "count_lines multiple lines" {
  inspect(@display.count_lines("a\nb\nc"), content="3")
}

test "count_lines multiple lines with trailing newline" {
  inspect(@display.count_lines("a\nb\nc\n"), content="3")
}

test "count_lines only newlines" {
  inspect(@display.count_lines("\n\n"), content="2")
}

// === format_tool_call ===

test "format_tool_call Read extracts file_path" {
  let input = "{\"file_path\":\"/src/main.mbt\"}"
  let result = @display.format_tool_call("Read", input)
  inspect(result, content="Read(/src/main.mbt)")
}

test "format_tool_call Edit shows path and old/new" {
  let input = "{\"file_path\":\"/src/main.mbt\",\"old_string\":\"hello\",\"new_string\":\"world\"}"
  let result = @display.format_tool_call("Edit", input)
  assert_true(result.contains("Edit(/src/main.mbt)"))
  assert_true(result.contains("old: hello"))
  assert_true(result.contains("new: world"))
}

test "format_tool_call Write shows path and char count" {
  let input = "{\"file_path\":\"/src/out.mbt\",\"content\":\"hello world\"}"
  let result = @display.format_tool_call("Write", input)
  inspect(result, content="Write(/src/out.mbt, 11 chars)")
}

test "format_tool_call Bash shows command" {
  let input = "{\"command\":\"moon test\"}"
  let result = @display.format_tool_call("Bash", input)
  inspect(result, content="Bash(moon test)")
}

test "format_tool_call Glob shows pattern" {
  let input = "{\"pattern\":\"**/*.mbt\"}"
  let result = @display.format_tool_call("Glob", input)
  inspect(result, content="Glob(**/*.mbt)")
}

test "format_tool_call Grep shows pattern and path" {
  let input = "{\"pattern\":\"TODO\",\"path\":\"/src\"}"
  let result = @display.format_tool_call("Grep", input)
  inspect(result, content="Grep(TODO in /src)")
}

test "format_tool_call Grep without path" {
  let input = "{\"pattern\":\"TODO\"}"
  let result = @display.format_tool_call("Grep", input)
  inspect(result, content="Grep(TODO)")
}

test "format_tool_call Task shows agent and description" {
  let input = "{\"subagent_type\":\"Explore\",\"description\":\"find files\"}"
  let result = @display.format_tool_call("Task", input)
  inspect(result, content="Task(Explore: find files)")
}

test "format_tool_call unknown tool falls back to truncated json" {
  let input = "{\"key\":\"value\"}"
  let result = @display.format_tool_call("Unknown", input)
  inspect(result, content="Unknown({\"key\":\"value\"})")
}

test "format_tool_call invalid JSON falls back gracefully" {
  let input = "not json at all"
  let result = @display.format_tool_call("Read", input)
  inspect(result, content="Read(not json at all)")
}

test "format_tool_call missing fields shows ?" {
  let input = "{}"
  let result = @display.format_tool_call("Read", input)
  inspect(result, content="Read(?)")
}

// === format_tool_result ===

test "format_tool_result Read shows line count" {
  let output = "line1\nline2\nline3"
  let result = @display.format_tool_result("Read", output)
  inspect(result, content="Read: 3 lines")
}

test "format_tool_result Read empty output shows 0 lines" {
  let result = @display.format_tool_result("Read", "")
  inspect(result, content="Read: 0 lines")
}

test "format_tool_result Edit truncates output" {
  let result = @display.format_tool_result("Edit", "success")
  inspect(result, content="Edit: success")
}

test "format_tool_result Write truncates output" {
  let result = @display.format_tool_result("Write", "ok")
  inspect(result, content="Write: ok")
}

test "format_tool_result Bash short output shown inline" {
  let result = @display.format_tool_result("Bash", "ok")
  inspect(result, content="Bash: ok")
}

test "format_tool_result Bash multi-line shows line count" {
  let output = "line1\nline2\nline3\nline4\nline5"
  let result = @display.format_tool_result("Bash", output)
  inspect(result, content="Bash: 5 lines")
}

test "format_tool_result Glob truncates" {
  let result = @display.format_tool_result("Glob", "a.mbt\nb.mbt")
  inspect(result, content="Glob: a.mbt\nb.mbt")
}

test "format_tool_result Grep truncates" {
  let result = @display.format_tool_result("Grep", "match found")
  inspect(result, content="Grep: match found")
}

test "format_tool_result unknown tool" {
  let result = @display.format_tool_result("WebSearch", "results...")
  inspect(result, content="WebSearch: results...")
}
