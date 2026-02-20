///| Review perspective
pub(all) enum ReviewPerspective {
  CodeQuality
  Performance
  Security
} derive(Eq, Show)

///| ReviewAgent parses review verdicts from LLM output
pub struct ReviewAgent {
  reviewer_id : String
  lang : String
}

///| Create a new ReviewAgent
pub fn ReviewAgent::new(reviewer_id : String, lang : String) -> ReviewAgent {
  { reviewer_id, lang }
}

///| All review perspectives in order
pub fn ReviewAgent::perspectives(
  _self : ReviewAgent,
) -> Array[ReviewPerspective] {
  [CodeQuality, Performance, Security]
}

///| Build review prompt for a specific perspective
pub fn ReviewAgent::build_prompt(
  self : ReviewAgent,
  perspective : ReviewPerspective,
  task_description : String,
  agent_output : String,
  context : String,
) -> String {
  let buf = StringBuilder::new()
  if self.lang == "ja" {
    buf.write_string("以下の開発作業をレビューしてください。\n\n")
  } else {
    buf.write_string("Review the following development work.\n\n")
  }
  // Context section (git log, diff, etc.)
  if not(context.is_empty()) {
    if self.lang == "ja" {
      buf.write_string("## 直近のコンテキスト\n")
    } else {
      buf.write_string("## Recent Context\n")
    }
    buf.write_string(context)
    buf.write_string("\n\n")
  }
  if self.lang == "ja" {
    buf.write_string("## タスク\n")
  } else {
    buf.write_string("## Task\n")
  }
  buf.write_string(task_description)
  if self.lang == "ja" {
    buf.write_string("\n\n## エージェント出力\n")
  } else {
    buf.write_string("\n\n## Agent Output\n")
  }
  buf.write_string(agent_output)
  buf.write_string("\n\n")
  // Perspective-specific instructions
  if self.lang == "ja" {
    match perspective {
      CodeQuality => {
        buf.write_string("## レビュー観点: コード品質\n")
        buf.write_string("以下の観点で評価してください:\n")
        buf.write_string("- 可読性と命名規約\n")
        buf.write_string("- 関心の分離\n")
        buf.write_string("- エラーハンドリングの網羅性\n")
        buf.write_string("- テストカバレッジと正確性\n")
        buf.write_string("- コードの重複と不必要な複雑さ\n")
        buf.write_string("- API 設計と公開インターフェースの明確さ\n")
      }
      Performance => {
        buf.write_string("## レビュー観点: パフォーマンス\n")
        buf.write_string("以下の観点で評価してください:\n")
        buf.write_string("- アルゴリズムの計算量（時間・空間）\n")
        buf.write_string("- 不要なメモリ確保やコピー\n")
        buf.write_string("- N+1 クエリや冗長な I/O\n")
        buf.write_string("- キャッシュの活用機会\n")
        buf.write_string("- ホットパスの最適化\n")
      }
      Security => {
        buf.write_string("## レビュー観点: セキュリティ\n")
        buf.write_string("以下の観点で評価してください:\n")
        buf.write_string("- 入力値のバリデーションとサニタイズ\n")
        buf.write_string("- インジェクション脆弱性（コマンド、SQL、XSS）\n")
        buf.write_string("- 認証・認可の不備\n")
        buf.write_string("- 機密データの露出（シークレット、トークン、個人情報）\n")
        buf.write_string("- 依存関係の安全性\n")
      }
    }
  } else {
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
  }
  // TODO.md instruction — reviewer must NOT attempt to fix issues
  buf.write_string("\n\n")
  if self.lang == "ja" {
    buf.write_string("## 重要な指示\n")
    buf.write_string("あなたの仕事は問題点を特定し TODO リストとして書き出すことです。タスクの解決は行わないでください。\n\n")
  } else {
    buf.write_string("## Important\n")
    buf.write_string("Your job is to identify issues and write them as a TODO list — do NOT attempt to fix or resolve the issues yourself.\n\n")
  }
  if self.lang == "ja" {
    buf.write_string("## 指示\n")
    buf.write_string(
      "この観点に基づき、以下のタグのいずれか1つだけを使って回答してください:\n",
    )
  } else {
    buf.write_string("## Instructions\n")
    buf.write_string(
      "Respond with EXACTLY ONE of these tags based on this perspective:\n",
    )
  }
  buf.write_string("- <approved> if no issues found\n")
  buf.write_string(
    "- <needs_changes>item1, item2</needs_changes> if changes are needed\n",
  )
  buf.write_string(
    "- <rejected>reason</rejected> if the work has critical issues\n\n",
  )
  if self.lang == "ja" {
    buf.write_string("その後、発見事項の簡潔な要約を記述してください。\n")
  } else {
    buf.write_string("Then provide a brief summary of your findings.\n")
  }
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
      // Only return NeedsChanges if there are actual feedback items;
      // empty <needs_changes></needs_changes> falls through to Approved
      if not(items.is_empty()) {
        return @types.ReviewVerdict::NeedsChanges(items)
      }
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
  on_event~ : (@types.AgentEvent) -> Unit = fn(_) {  },
) -> @types.ReviewResult {
  let task_output = task.result.unwrap_or("")
  let prompt = self.build_prompt(perspective, task.description, task_output, context)
  let system = if self.lang == "ja" {
    "あなたは \{perspective} に焦点を当てたコードレビュアーです。簡潔かつ具体的に指摘してください。問題の修正は行わず、TODO リストとして書き出してください。"
  } else {
    "You are a code reviewer focusing on \{perspective}. Be concise and actionable. Do NOT fix issues — list them as TODOs."
  }
  let output = backend.run(prompt, system, on_event)
  // If the review backend failed, reject rather than silently approving
  let verdict = match output.status {
    Failed(err) =>
      @types.ReviewVerdict::Rejected("Review backend failed: \{err}")
    _ => self.parse_verdict(output.content)
  }
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
  on_event~ : (@types.AgentEvent) -> Unit = fn(_) {  },
) -> @types.ReviewResult {
  let all_items : Array[String] = []
  let summaries = StringBuilder::new()
  let mut rejected_reason : String? = None
  let perspectives = self.perspectives()
  for perspective in perspectives {
    let result = self.review_perspective(
      perspective, task, backend, context, on_event=on_event,
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

///| Extract content between XML-style tags.
///| Searches for the close tag starting from after the open tag,
///| preventing cross-tag mismatches when close tag appears before open tag.
fn extract_tag_content(text : String, tag_name : String) -> String? {
  let open_tag = "<\{tag_name}>"
  let close_tag = "</\{tag_name}>"
  let open_idx = text.find(open_tag)
  match open_idx {
    Some(start) => {
      let content_start = start + open_tag.length()
      // Search for close tag only in the text after the open tag
      let remaining = text
        .view(start_offset=content_start)
        .to_string()
      let close_idx = remaining.find(close_tag)
      match close_idx {
        Some(rel_end) =>
          Some(
            text
              .view(
                start_offset=content_start,
                end_offset=content_start + rel_end,
              )
              .to_string(),
          )
        None => None
      }
    }
    None => None
  }
}
