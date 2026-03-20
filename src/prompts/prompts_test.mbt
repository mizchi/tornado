test "code_quality_checklist en contains Readability" {
  let content = @prompts.code_quality_checklist("en")
  assert_true(content.contains("Readability"))
}

test "code_quality_checklist ja contains 可読性" {
  let content = @prompts.code_quality_checklist("ja")
  assert_true(content.contains("可読性"))
}

test "performance_checklist en contains Algorithmic complexity" {
  let content = @prompts.performance_checklist("en")
  assert_true(content.contains("Algorithmic complexity"))
}

test "security_checklist en contains Injection vulnerabilities" {
  let content = @prompts.security_checklist("en")
  assert_true(content.contains("Injection vulnerabilities"))
}
