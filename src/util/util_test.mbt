///|
test "extract_tag_content returns content between tags" {
  let result = @util.extract_tag_content(
    "<approved>looks good</approved>", "approved",
  )
  inspect(result, content="Some(\"looks good\")")
}

///|
test "extract_tag_content returns None when tag not found" {
  let result = @util.extract_tag_content("no tags here", "approved")
  inspect(result, content="None")
}

///|
test "extract_tag_content returns None when no close tag" {
  let result = @util.extract_tag_content(
    "<needs_changes>fix this", "needs_changes",
  )
  inspect(result, content="None")
}

///|
test "extract_tag_content with close before open" {
  let result = @util.extract_tag_content(
    "</needs_changes>content<needs_changes>", "needs_changes",
  )
  // No valid open/close pair, should return None
  inspect(result, content="None")
}

///|
test "extract_tag_content finds close tag after open, not before" {
  let result = @util.extract_tag_content(
    "preamble </needs_changes>noise <needs_changes>fix naming</needs_changes>", "needs_changes",
  )
  inspect(result, content="Some(\"fix naming\")")
}

///|
test "extract_tag_content with rejected tag nested in text" {
  let result = @util.extract_tag_content(
    "Some analysis... </rejected>stale<rejected>real issue</rejected> more text",
    "rejected",
  )
  inspect(result, content="Some(\"real issue\")")
}

///|
test "extract_tag_content with empty content" {
  let result = @util.extract_tag_content(
    "<needs_changes></needs_changes>", "needs_changes",
  )
  inspect(result, content="Some(\"\")")
}

///|
test "extract_tag_content with surrounding noise" {
  let result = @util.extract_tag_content(
    "I reviewed.\n\n<needs_changes>add error handling, improve naming</needs_changes>\n\nOverall needs work.",
    "needs_changes",
  )
  inspect(result, content="Some(\"add error handling, improve naming\")")
}

///|
test "extract_tag_content with multiline content" {
  let result = @util.extract_tag_content(
    "<needs_rework>m1-t1: fix error handling\nm1-t2: add tests</needs_rework>", "needs_rework",
  )
  inspect(
    result,
    content="Some(\"m1-t1: fix error handling\\nm1-t2: add tests\")",
  )
}
