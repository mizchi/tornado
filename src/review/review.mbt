///| Review perspective
pub(all) enum ReviewPerspective {
  CodeQuality
  Performance
  Security
} derive(Eq, Show)

///| ReviewAgent parses review verdicts from LLM output
pub struct ReviewAgent {
  reviewer_id : String
}

///| Create a new ReviewAgent
pub fn ReviewAgent::new(reviewer_id : String) -> ReviewAgent {
  { reviewer_id, }
}

///| All review perspectives in order
pub fn ReviewAgent::perspectives(
  _self : ReviewAgent,
) -> Array[ReviewPerspective] {
  [CodeQuality, Performance, Security]
}

///| Build review prompt for a specific perspective
pub fn ReviewAgent::build_prompt(
  _self : ReviewAgent,
  perspective : ReviewPerspective,
  task_description : String,
  agent_output : String,
  context : String,
) -> String {
  let buf = StringBuilder::new()
  buf.write_string("Review the following development work.\n\n")
  // Context section (git log, diff, etc.)
  if not(context.is_empty()) {
    buf.write_string("## Recent Context\n")
    buf.write_string(context)
    buf.write_string("\n\n")
  }
  buf.write_string("## Task\n")
  buf.write_string(task_description)
  buf.write_string("\n\n## Agent Output\n")
  buf.write_string(agent_output)
  buf.write_string("\n\n")
  // Perspective-specific instructions
  match perspective {
    CodeQuality => {
      buf.write_string("## Review Focus: Code Quality\n")
      buf.write_string("Evaluate the following aspects:\n")
      buf.write_string("- Readability and naming conventions\n")
      buf.write_string("- Proper separation of concerns\n")
      buf.write_string("- Error handling completeness\n")
      buf.write_string("- Test coverage and correctness\n")
      buf.write_string("- Code duplication and unnecessary complexity\n")
      buf.write_string("- API design and public interface clarity\n")
    }
    Performance => {
      buf.write_string("## Review Focus: Performance\n")
      buf.write_string("Evaluate the following aspects:\n")
      buf.write_string("- Algorithmic complexity (time and space)\n")
      buf.write_string("- Unnecessary allocations or copies\n")
      buf.write_string("- N+1 queries or redundant I/O\n")
      buf.write_string("- Caching opportunities\n")
      buf.write_string("- Hot path optimization\n")
    }
    Security => {
      buf.write_string("## Review Focus: Security\n")
      buf.write_string("Evaluate the following aspects:\n")
      buf.write_string("- Input validation and sanitization\n")
      buf.write_string("- Injection vulnerabilities (command, SQL, XSS)\n")
      buf.write_string("- Authentication and authorization gaps\n")
      buf.write_string("- Sensitive data exposure (secrets, tokens, PII)\n")
      buf.write_string("- Dependency safety\n")
    }
  }
  buf.write_string("\n\n## Instructions\n")
  buf.write_string(
    "Respond with EXACTLY ONE of these tags based on this perspective:\n",
  )
  buf.write_string("- <approved> if no issues found\n")
  buf.write_string(
    "- <needs_changes>item1, item2</needs_changes> if changes are needed\n",
  )
  buf.write_string(
    "- <rejected>reason</rejected> if the work has critical issues\n\n",
  )
  buf.write_string("Then provide a brief summary of your findings.\n")
  buf.to_string()
}

///| Parse review verdict from LLM output
pub fn ReviewAgent::parse_verdict(
  _self : ReviewAgent,
  output : String,
) -> @types.ReviewVerdict {
  if output.contains("<approved>") {
    return @types.ReviewVerdict::Approved
  }
  match extract_tag_content(output, "needs_changes") {
    Some(content) => {
      let items : Array[String] = []
      for part in content.split(",") {
        let trimmed = part.to_string().trim().to_string()
        if not(trimmed.is_empty()) {
          items.push(trimmed)
        }
      }
      return @types.ReviewVerdict::NeedsChanges(items)
    }
    None => ()
  }
  match extract_tag_content(output, "rejected") {
    Some(reason) =>
      return @types.ReviewVerdict::Rejected(reason.trim().to_string())
    None => ()
  }
  @types.ReviewVerdict::Approved
}

///| Run a single-perspective review on a completed task
pub fn ReviewAgent::review_perspective(
  self : ReviewAgent,
  perspective : ReviewPerspective,
  task : @types.Task,
  backend : @agent.BoxedBackend,
  context : String,
) -> @types.ReviewResult {
  let task_output = task.result.unwrap_or("")
  let prompt = self.build_prompt(perspective, task.description, task_output, context)
  let system = "You are a code reviewer focusing on \{perspective}. Be concise and actionable."
  let output = backend.run(prompt, system, fn(_) {  })
  let verdict = self.parse_verdict(output.content)
  let result : @types.ReviewResult = {
    reviewer_id: self.reviewer_id,
    verdict,
    summary: output.content,
    file_path: "",
  }
  result
}

///| Run all three perspectives in order, return merged result
pub fn ReviewAgent::review(
  self : ReviewAgent,
  task : @types.Task,
  backend : @agent.BoxedBackend,
  context~ : String = "",
) -> @types.ReviewResult {
  let all_items : Array[String] = []
  let summaries = StringBuilder::new()
  let mut rejected_reason : String? = None
  let perspectives = self.perspectives()
  for perspective in perspectives {
    let result = self.review_perspective(
      perspective, task, backend, context,
    )
    summaries.write_string("### \{perspective}\n")
    summaries.write_string(result.summary)
    summaries.write_string("\n\n")
    match result.verdict {
      Rejected(reason) => {
        rejected_reason = Some("[\{perspective}] \{reason}")
        break
      }
      NeedsChanges(items) =>
        for item in items {
          all_items.push("[\{perspective}] \{item}")
        }
      Approved => ()
    }
  }
  // Determine final merged verdict
  let verdict = match rejected_reason {
    Some(reason) => @types.ReviewVerdict::Rejected(reason)
    None =>
      if all_items.is_empty() {
        @types.ReviewVerdict::Approved
      } else {
        @types.ReviewVerdict::NeedsChanges(all_items)
      }
  }
  let merged : @types.ReviewResult = {
    reviewer_id: self.reviewer_id,
    verdict,
    summary: summaries.to_string(),
    file_path: "",
  }
  task.review = Some(merged)
  merged
}

///| Build review file content as markdown
pub fn ReviewAgent::format_review(
  _self : ReviewAgent,
  task : @types.Task,
  review : @types.ReviewResult,
) -> String {
  let buf = StringBuilder::new()
  buf.write_string("# Review: \{task.id}\n\n")
  buf.write_string("## Task\n")
  buf.write_string(task.description)
  buf.write_string("\n\n## Verdict\n")
  match review.verdict {
    Approved => buf.write_string("**APPROVED**\n")
    NeedsChanges(items) => {
      buf.write_string("**NEEDS CHANGES**\n")
      for item in items {
        buf.write_string("- \{item}\n")
      }
    }
    Rejected(reason) => buf.write_string("**REJECTED**: \{reason}\n")
  }
  buf.write_string("\n## Summary\n")
  buf.write_string(review.summary)
  buf.write_string("\n")
  buf.to_string()
}

///| Extract content between XML-style tags
fn extract_tag_content(text : String, tag_name : String) -> String? {
  let open_tag = "<\{tag_name}>"
  let close_tag = "</\{tag_name}>"
  let open_idx = text.find(open_tag)
  match open_idx {
    Some(start) => {
      let content_start = start + open_tag.length()
      let close_idx = text.find(close_tag)
      match close_idx {
        Some(end) =>
          if end > content_start {
            Some(
              text.view(start_offset=content_start, end_offset=end).to_string(),
            )
          } else {
            None
          }
        None => None
      }
    }
    None => None
  }
}
