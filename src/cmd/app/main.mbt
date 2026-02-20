// ── Session state file: .tornado/session.json ──

let session_file : String = ".tornado/session.json"

fn main {
  let args = @sys.get_cli_args()
  if args.length() < 2 {
    run_repl(None)
    return
  }
  let command = args[1]
  match command {
    "run" => {
      let config_path : String? = if args.length() >= 3 {
        Some(args[2])
      } else {
        None
      }
      run_repl(config_path)
    }
    "validate" => {
      if args.length() < 3 {
        println("Usage: tornado validate <config.json>")
        return
      }
      run_validate(args[2])
    }
    "help" | "--help" | "-h" => print_usage()
    _ => run_repl(Some(command))
  }
}

///|
fn print_usage() -> Unit {
  println("tornado - multi-agent development orchestrator")
  println("")
  println("Usage:")
  println(
    "  tornado                    # start with preset (dev:claude-code, review:codex)",
  )
  println("  tornado run                # same as above")
  println("  tornado run <config.json>  # start with custom config")
  println("  tornado validate <config>  # validate config file")
  println("")
  println("Autonomous heartbeat: dev runs → reviewer reviews →")
  println("dev continues with next task → forever until Ctrl+C.")
  println("Session auto-saved to .tornado/session.json for resume.")
}

///| Load config from file, or use preset
fn load_config(config_path : String?) -> @config.ProjectConfig {
  match config_path {
    Some(path) => {
      let content = read_file_sync(path)
      if content.has_prefix("ERROR:") {
        log("WARN", "Failed to read \{path}: \{content}")
        log("WARN", "Falling back to preset config")
        return @config.ProjectConfig::preset_default()
      }
      try {
        @config.ProjectConfig::from_json_string(content)
      } catch {
        err => {
          log("WARN", "Invalid config: \{err}, using preset")
          @config.ProjectConfig::preset_default()
        }
      }
    }
    None => @config.ProjectConfig::preset_default()
  }
}

///| Timestamped log
fn log(level : String, msg : String) -> Unit {
  let ts = now_timestamp()
  println("[\{ts}] [\{level}] \{msg}")
}

///| Truncate long text for display
fn truncate(s : String, max : Int) -> String {
  if s.length() <= max {
    s
  } else {
    s.view(start_offset=0, end_offset=max).to_string() + "..."
  }
}

///| Format tool call for display
fn format_tool_call(name : String, input_json : String) -> String {
  let json = @json.parse(input_json) catch { _ => return "\{name}(\{truncate(input_json, 100)})" }
  match json {
    Object(m) =>
      match name {
        "Read" => {
          let path = match m.get("file_path") {
            Some(String(p)) => p
            _ => "?"
          }
          "Read(\{path})"
        }
        "Edit" => {
          let path = match m.get("file_path") {
            Some(String(p)) => p
            _ => "?"
          }
          let old_str = match m.get("old_string") {
            Some(String(s)) => truncate(s.trim().to_string(), 60)
            _ => ""
          }
          let new_str = match m.get("new_string") {
            Some(String(s)) => truncate(s.trim().to_string(), 60)
            _ => ""
          }
          "Edit(\{path})\n           old: \{old_str}\n           new: \{new_str}"
        }
        "Write" => {
          let path = match m.get("file_path") {
            Some(String(p)) => p
            _ => "?"
          }
          let content_len = match m.get("content") {
            Some(String(s)) => s.length()
            _ => 0
          }
          "Write(\{path}, \{content_len} chars)"
        }
        "Bash" => {
          let cmd = match m.get("command") {
            Some(String(c)) => truncate(c, 120)
            _ => "?"
          }
          "Bash(\{cmd})"
        }
        "Glob" => {
          let pattern = match m.get("pattern") {
            Some(String(p)) => p
            _ => "?"
          }
          "Glob(\{pattern})"
        }
        "Grep" => {
          let pattern = match m.get("pattern") {
            Some(String(p)) => p
            _ => "?"
          }
          let path = match m.get("path") {
            Some(String(p)) => " in \{p}"
            _ => ""
          }
          "Grep(\{pattern}\{path})"
        }
        "Task" => {
          let desc = match m.get("description") {
            Some(String(d)) => d
            _ => ""
          }
          let agent = match m.get("subagent_type") {
            Some(String(t)) => t
            _ => "?"
          }
          "Task(\{agent}: \{desc})"
        }
        _ => "\{name}(\{truncate(input_json, 100)})"
      }
    _ => "\{name}(\{truncate(input_json, 100)})"
  }
}

///| Format tool result for display
fn format_tool_result(name : String, output : String) -> String {
  match name {
    "Read" => {
      let lines = output.split("\n")
      let mut line_count = 0
      for _l in lines {
        line_count += 1
      }
      "Read: \{line_count} lines"
    }
    "Edit" => "Edit: \{truncate(output, 80)}"
    "Write" => "Write: \{truncate(output, 80)}"
    "Bash" => {
      let lines = output.split("\n")
      let mut line_count = 0
      for _l in lines {
        line_count += 1
      }
      if line_count > 3 {
        "Bash: \{line_count} lines"
      } else {
        "Bash: \{truncate(output, 120)}"
      }
    }
    "Glob" => "Glob: \{truncate(output, 120)}"
    "Grep" => "Grep: \{truncate(output, 120)}"
    _ => "\{name}: \{truncate(output, 120)}"
  }
}

///|
fn run_validate(config_path : String) -> Unit {
  let content = read_file_sync(config_path)
  if content.has_prefix("ERROR:") {
    println("Failed to read config: \{content}")
    return
  }
  let config = try {
    @config.ProjectConfig::from_json_string(content)
  } catch {
    err => {
      println("Invalid config: \{err}")
      return
    }
  }
  let errors = config.validate()
  if errors.is_empty() {
    println("Config is valid.")
    println("  project_dir: \{config.project_dir}")
    println("  review_dir: \{config.review_dir}")
    println("  max_review_cycles: \{config.max_review_cycles}")
    println("  agents: \{config.agents.length()}")
    for agent in config.agents {
      println("    - \{agent.id} (\{agent.kind}, \{agent.role})")
    }
  } else {
    println("Config validation errors:")
    for err in errors {
      println("  - \{err}")
    }
  }
}

// ── Session persistence ──────────────────────────────────────

///| Persisted session state
struct SessionState {
  iteration : Int
  phase : String // "dev" | "review" | "idle"
  task : String
  dev_output : String
  review_summary : String
  agent_sessions : Map[String, String]
}

///| Save session state to .tornado/session.json
fn save_session(state : SessionState) -> Unit {
  let sessions_map : Map[String, Json] = {}
  for entry in state.agent_sessions {
    sessions_map[entry.0] = entry.1.to_json()
  }
  let obj : Map[String, Json] = {}
  obj["iteration"] = state.iteration.to_json()
  obj["phase"] = state.phase.to_json()
  obj["task"] = state.task.to_json()
  obj["dev_output"] = state.dev_output.to_json()
  obj["review_summary"] = state.review_summary.to_json()
  obj["agent_sessions"] = Json::object(sessions_map)
  let json = Json::object(obj)
  ignore(exec_sync("mkdir -p .tornado"))
  write_file_sync(session_file, json.stringify())
}

///| Load session state from disk
fn load_session() -> SessionState? {
  let content = read_file_sync(session_file)
  if content.has_prefix("ERROR:") {
    return None
  }
  let json = @json.parse(content) catch { _ => return None }
  match json {
    Object(map) => {
      let iteration = match map.get("iteration") {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
      let phase = match map.get("phase") {
        Some(String(s)) => s
        _ => "idle"
      }
      let task = match map.get("task") {
        Some(String(s)) => s
        _ => ""
      }
      let dev_output = match map.get("dev_output") {
        Some(String(s)) => s
        _ => ""
      }
      let review_summary = match map.get("review_summary") {
        Some(String(s)) => s
        _ => ""
      }
      let agent_sessions : Map[String, String] = {}
      match map.get("agent_sessions") {
        Some(Object(sessions)) =>
          for entry in sessions {
            match entry.1 {
              String(sid) => agent_sessions[entry.0] = sid
              _ => ()
            }
          }
        _ => ()
      }
      Some({ iteration, phase, task, dev_output, review_summary, agent_sessions })
    }
    _ => None
  }
}

///| Clear saved session
fn clear_session() -> Unit {
  ignore(exec_sync("rm -f \{session_file}"))
}

// ── Initial task builder ─────────────────────────────────────

///| Build initial task by reading TODO files in the project
fn build_initial_task_from_todos() -> String {
  let todo_files = [
    "TODO.md",
    "Agents-todo.md",
    "AGENTS-TODO.md",
    "agents-todo.md",
    "TODO",
    "todo.md",
  ]
  let buf = StringBuilder::new()
  buf.write_string(
    "You are starting an autonomous development session for this project.\n\n",
  )
  buf.write_string(
    "First, read the following TODO/task files to understand what needs to be done:\n\n",
  )
  let mut found = false
  for file in todo_files {
    let content = read_file_sync(file)
    if not(content.has_prefix("ERROR:")) && not(content.is_empty()) {
      found = true
      buf.write_string("## \{file}\n```\n")
      buf.write_string(truncate(content, 3000))
      buf.write_string("\n```\n\n")
    }
  }
  if not(found) {
    buf.write_string(
      "(No TODO files found. Look at the project structure, README, and recent git history instead.)\n\n",
    )
  }
  let context = gather_review_context()
  if not(context.is_empty()) {
    buf.write_string("## Current Project State\n")
    buf.write_string(context)
  }
  buf.write_string("## Your Task\n")
  buf.write_string(
    "Based on the TODO files and project state above, pick the highest-priority incomplete task and implement it.\n",
  )
  buf.write_string(
    "Make concrete code changes, run tests, and commit when done. Then move to the next task.\n",
  )
  buf.to_string()
}

// ── Continuation task builder ────────────────────────────────

///| Build a continuation task for the dev agent after review approval
fn build_continuation_task(
  prev_task : String,
  review_summary : String,
) -> String {
  let context = gather_review_context()
  let buf = StringBuilder::new()
  buf.write_string(
    "You are in an autonomous development loop. Your job is to continuously improve this project.\n\n",
  )
  if not(context.is_empty()) {
    buf.write_string("## Current Project State\n")
    buf.write_string(context)
    buf.write_string("\n")
  }
  buf.write_string("## Previous Task (completed)\n")
  buf.write_string(prev_task)
  buf.write_string("\n\n")
  if not(review_summary.is_empty()) {
    buf.write_string("## Review Feedback\n")
    buf.write_string(truncate(review_summary, 2000))
    buf.write_string("\n\n")
  }
  buf.write_string("## Your Task\n")
  buf.write_string(
    "Based on the current project state above (git log, uncommitted changes, previous work), ",
  )
  buf.write_string("identify and implement the single most impactful improvement. ")
  buf.write_string("This could be: fixing bugs, adding tests, improving error handling, ")
  buf.write_string("refactoring, documentation, or implementing a missing feature.\n\n")
  buf.write_string(
    "Look at the actual codebase files, run tests, and make concrete changes. ",
  )
  buf.write_string("Do not just describe what to do — actually do it.\n")
  buf.to_string()
}

// ── REPL + Autonomous heartbeat ──────────────────────────────

///| Autonomous loop: task → dev → review → continue
fn run_repl(config_path : String?) -> Unit {
  let config = load_config(config_path)
  println("")
  println("  tornado - autonomous development orchestrator")
  println("")
  log("BOOT", "Agents:")
  for agent in config.agents {
    log("BOOT", "  \{agent.id} (\{agent.kind}, \{agent.role})")
  }
  log("BOOT", "Max review cycles: \{config.max_review_cycles}")
  println("")
  let backends = @agent.create_backends(config.agents)
  let dev_id = find_agent_id(config.agents, @types.AgentRole::Dev)
  let reviewer_id = find_agent_id(config.agents, @types.AgentRole::Review)
  let agent_sessions : Map[String, String] = {}
  let mut iteration = 0
  let mut next_task : String = ""
  let mut last_review_summary : String = ""
  // ── Check for saved session ──
  match load_session() {
    Some(saved) => {
      log("RESUME", "Found saved session (iteration \{saved.iteration})")
      log("RESUME", "  Phase: \{saved.phase}")
      log("RESUME", "  Task: \{truncate(saved.task, 80)}")
      for entry in saved.agent_sessions {
        log("RESUME", "  Agent \{entry.0}: session \{entry.1}")
        agent_sessions[entry.0] = entry.1
      }
      println("")
      let answer = prompt_sync("Resume this session? [Y/n] ")
      if answer == "n" || answer == "N" || answer == "no" {
        log("RESUME", "Starting fresh")
        clear_session()
      } else {
        log("RESUME", "Resuming...")
        restore_sessions(backends, agent_sessions)
        iteration = saved.iteration
        last_review_summary = saved.review_summary
        match saved.phase {
          "dev" | "review" => next_task = saved.task
          _ => {
            // idle → previous iteration done, build continuation
            next_task = build_continuation_task(
              saved.task, saved.review_summary,
            )
          }
        }
      }
    }
    None => ()
  }
  // ── Get initial task if needed ──
  if next_task.is_empty() {
    println("")
    next_task = prompt_sync("task> ")
    if next_task == "quit" || next_task == "exit" {
      log("EXIT", "Bye.")
      return
    }
    if next_task.is_empty() {
      // No task given → start from TODO files
      next_task = build_initial_task_from_todos()
      log("HEARTBEAT", "No task specified. Starting from project TODO files.")
    }
  }
  // ── Start stdin watcher for user interrupts ──
  start_stdin_watcher()
  log("BOOT", "Type and press Enter anytime to queue instructions.")
  println("")
  // ── Autonomous loop: runs until Ctrl+C ──
  while true {
    iteration += 1
    log("HEARTBEAT", "=== Iteration \{iteration} ===")
    log("HEARTBEAT", "Task: \{truncate(next_task, 120)}")
    // ── Check for user interrupt before dev ──
    let interrupt = check_interrupt()
    if not(interrupt.is_empty()) {
      log("USER", "Applying user instructions: \{truncate(interrupt, 100)}")
      next_task = next_task + "\n\n## Additional Instructions from User\n" +
        interrupt
    }
    // ── dev phase ──
    save_session(
      {
        iteration,
        phase: "dev",
        task: next_task,
        dev_output: "",
        review_summary: last_review_summary,
        agent_sessions,
      },
    )
    let dev_result = run_dev(dev_id, backends, next_task, agent_sessions)
    // ── Check for user interrupt after dev ──
    let post_dev_interrupt = check_interrupt()
    if not(post_dev_interrupt.is_empty()) {
      log(
        "USER",
        "User instructions for review: \{truncate(post_dev_interrupt, 100)}",
      )
    }
    // ── review phase ──
    save_session(
      {
        iteration,
        phase: "review",
        task: next_task,
        dev_output: dev_result,
        review_summary: last_review_summary,
        agent_sessions,
      },
    )
    let review_result = match reviewer_id {
      Some(rid) =>
        run_review(
          dev_id,
          rid,
          backends,
          next_task,
          dev_result,
          config.max_review_cycles,
          agent_sessions,
        )
      None => {
        log("SKIP", "No reviewer configured")
        ReviewOutcome::Approved("")
      }
    }
    // ── determine next task ──
    match review_result {
      Approved(summary) => {
        last_review_summary = summary
        save_session(
          {
            iteration,
            phase: "idle",
            task: next_task,
            dev_output: dev_result,
            review_summary: summary,
            agent_sessions,
          },
        )
        log("HEARTBEAT", "=== Iteration \{iteration} complete ===")
        // Check for user interrupt → use as next task
        let user_input = check_interrupt()
        if not(user_input.is_empty()) {
          log("USER", "Using user instructions: \{truncate(user_input, 100)}")
          next_task = user_input
        } else {
          // Auto-continue: build continuation task for dev
          log("HEARTBEAT", "Building next task from project state...")
          next_task = build_continuation_task(next_task, summary)
        }
        // Also apply any post-dev interrupt that wasn't consumed
        if not(post_dev_interrupt.is_empty()) {
          next_task = next_task + "\n\n## Additional Instructions from User\n" +
            post_dev_interrupt
        }
      }
      Rejected(reason) => {
        last_review_summary = reason
        save_session(
          {
            iteration,
            phase: "idle",
            task: next_task,
            dev_output: dev_result,
            review_summary: reason,
            agent_sessions,
          },
        )
        log("HEARTBEAT", "=== Iteration \{iteration} complete (REJECTED) ===")
        // Check for queued user input first
        let queued = check_interrupt()
        if not(queued.is_empty()) {
          log("USER", "Using queued instructions: \{truncate(queued, 100)}")
          next_task = queued
        } else {
          // Wait for user input via interrupt file
          println("")
          log(
            "HEARTBEAT",
            "Review rejected. Type next task and press Enter (or Ctrl+C to stop).",
          )
          let mut user_input = ""
          while user_input.is_empty() {
            user_input = check_interrupt()
            if user_input.is_empty() {
              sleep_ms(500)
            }
          }
          log("USER", "Received: \{truncate(user_input, 100)}")
          next_task = user_input
        }
      }
    }
  }
}

///| Review outcome for the main loop
enum ReviewOutcome {
  Approved(String) // review summary
  Rejected(String) // reason
}

///| Restore session IDs to backends
fn restore_sessions(
  backends : Map[String, @agent.BoxedBackend],
  agent_sessions : Map[String, String],
) -> Unit {
  for entry in agent_sessions {
    match backends.get(entry.0) {
      Some(backend) => {
        backend.set_session_id(entry.1)
        log("SESSION", "\{entry.0}: restored session \{entry.1}")
      }
      None => ()
    }
  }
}

///| Find agent id by role
fn find_agent_id(
  agents : Array[@types.AgentConfig],
  role : @types.AgentRole,
) -> String? {
  for agent in agents {
    if agent.role == role {
      return Some(agent.id)
    }
  }
  None
}

///| Run dev agent, return output
fn run_dev(
  dev_id : String?,
  backends : Map[String, @agent.BoxedBackend],
  task : String,
  agent_sessions : Map[String, String],
) -> String {
  let id = dev_id.unwrap_or("dev")
  match backends.get(id) {
    Some(backend) => {
      match agent_sessions.get(id) {
        Some(sid) => log("DEV", "Starting \{id} (resume: \{sid})...")
        None => log("DEV", "Starting \{id} (new session)...")
      }
      println("")
      let result = backend.run(task, "", fn(event) {
        match event {
          @types.AgentEvent::OutputLine(line) =>
            println("  [\{id}] \{truncate(line, 140)}")
          @types.AgentEvent::Info(msg) =>
            log("INFO", "\{id}: \{msg}")
          @types.AgentEvent::ToolCall(name=tool_name, input=tool_input) =>
            log("TOOL", "\{id} -> \{format_tool_call(tool_name, tool_input)}")
          @types.AgentEvent::ToolResult(name=tool_name, output=tool_output) =>
            log(
              "TOOL",
              "\{id} <- \{format_tool_result(tool_name, tool_output)}",
            )
          @types.AgentEvent::SubAgentStart(
            agent_type=agent_type,
            task=desc,
          ) =>
            log(
              "AGENT",
              "\{id} spawned \{agent_type}: \{truncate(desc, 80)}",
            )
          @types.AgentEvent::SubAgentEnd(agent_type=agent_type) =>
            log("AGENT", "\{id} \{agent_type} completed")
          @types.AgentEvent::StatusChange(status) =>
            log("DEV", "\{id} -> \{status}")
          @types.AgentEvent::SessionId(sid) => {
            agent_sessions[id] = sid
            log("DEV", "\{id} session: \{sid}")
          }
        }
      })
      println("")
      match result.status {
        Completed => {
          log("DEV", "\{id} finished successfully")
          result.content
        }
        Failed(err) => {
          log("DEV", "\{id} failed: \{truncate(err, 100)}")
          result.content
        }
        _ => {
          log("DEV", "\{id} ended with status: \{result.status}")
          result.content
        }
      }
    }
    None => {
      log("ERROR", "Backend '\{id}' not found")
      ""
    }
  }
}

///| Gather git context for review
fn gather_review_context() -> String {
  let buf = StringBuilder::new()
  let git_log = exec_sync("git log --oneline -10 2>/dev/null")
  if not(git_log.is_empty()) {
    buf.write_string("### Recent Commits\n```\n")
    buf.write_string(git_log)
    buf.write_string("\n```\n\n")
  }
  let git_diff_stat = exec_sync("git diff --stat HEAD 2>/dev/null")
  if not(git_diff_stat.is_empty()) {
    buf.write_string("### Uncommitted Changes\n```\n")
    buf.write_string(git_diff_stat)
    buf.write_string("\n```\n\n")
  }
  let git_staged = exec_sync("git diff --cached --stat 2>/dev/null")
  if not(git_staged.is_empty()) {
    buf.write_string("### Staged Changes\n```\n")
    buf.write_string(git_staged)
    buf.write_string("\n```\n\n")
  }
  buf.to_string()
}

///| Run review, return outcome
fn run_review(
  dev_id : String?,
  reviewer_id : String,
  backends : Map[String, @agent.BoxedBackend],
  task : String,
  dev_output : String,
  max_cycles : Int,
  agent_sessions : Map[String, String],
) -> ReviewOutcome {
  match backends.get(reviewer_id) {
    Some(backend) => {
      let ra = @review.ReviewAgent::new(reviewer_id)
      log("REVIEW", "Gathering git context...")
      let context = gather_review_context()
      let perspectives = ra.perspectives()
      for perspective in perspectives {
        log("REVIEW", "Reviewing: \{perspective}...")
      }
      let review_event_handler : (@types.AgentEvent) -> Unit = fn(event) {
        match event {
          @types.AgentEvent::Info(msg) =>
            log("INFO", "\{reviewer_id}: \{msg}")
          @types.AgentEvent::ToolCall(name=tool_name, input=tool_input) =>
            log(
              "TOOL",
              "\{reviewer_id} -> \{tool_name}(\{truncate(tool_input, 100)})",
            )
          @types.AgentEvent::ToolResult(
            name=tool_name,
            output=tool_output,
          ) =>
            log(
              "TOOL",
              "\{reviewer_id} <- \{tool_name}: \{truncate(tool_output, 120)}",
            )
          @types.AgentEvent::StatusChange(status) =>
            log("REVIEW", "\{reviewer_id} -> \{status}")
          @types.AgentEvent::SessionId(sid) => {
            agent_sessions[reviewer_id] = sid
            log("REVIEW", "\{reviewer_id} session: \{sid}")
          }
          _ => ()
        }
      }
      let review_task = @types.Task::new("review-target", task)
      review_task.complete(dev_output)
      let review = ra.review(
        review_task, backend, context=context, on_event=review_event_handler,
      )
      log("REVIEW", "\{reviewer_id} finished")
      match review.verdict {
        Approved => {
          println("")
          log("REVIEW", "Verdict: APPROVED (all perspectives)")
          ReviewOutcome::Approved(review.summary)
        }
        NeedsChanges(items) => {
          println("")
          log("REVIEW", "Verdict: NEEDS CHANGES")
          for item in items {
            log("REVIEW", "  - \{item}")
          }
          // Auto-rework loop
          let mut cycle = 1
          let mut current_output = dev_output
          let mut current_items = items
          while cycle < max_cycles {
            cycle += 1
            log(
              "HEARTBEAT",
              "Auto-rework cycle \{cycle}/\{max_cycles}",
            )
            let feedback = current_items.iter().fold(
              init="",
              fn(acc, item) { acc + "- " + item + "\n" },
            )
            let rework_task = "\{task}\n\nFeedback from review:\n\{feedback}"
            current_output = run_dev(
              dev_id, backends, rework_task, agent_sessions,
            )
            log("REVIEW", "Re-reviewing after rework (3 perspectives)...")
            let fresh_context = gather_review_context()
            let rework_review_task = @types.Task::new(
              "rework-\{cycle}",
              task,
            )
            rework_review_task.complete(current_output)
            let rework_review = ra.review(
              rework_review_task,
              backend,
              context=fresh_context,
              on_event=review_event_handler,
            )
            match rework_review.verdict {
              Approved => {
                log("REVIEW", "Verdict: APPROVED after \{cycle} cycles")
                return ReviewOutcome::Approved(rework_review.summary)
              }
              NeedsChanges(new_items) => {
                log("REVIEW", "Still needs changes")
                for item in new_items {
                  log("REVIEW", "  - \{item}")
                }
                current_items = new_items
              }
              Rejected(reason) => {
                log("REVIEW", "REJECTED: \{reason}")
                return ReviewOutcome::Rejected(reason)
              }
            }
          }
          log("REVIEW", "Max review cycles reached, continuing anyway")
          ReviewOutcome::Approved(review.summary)
        }
        Rejected(reason) => {
          println("")
          log("REVIEW", "Verdict: REJECTED - \{reason}")
          ReviewOutcome::Rejected(reason)
        }
      }
    }
    None => {
      log("ERROR", "Reviewer backend '\{reviewer_id}' not found")
      ReviewOutcome::Approved("")
    }
  }
}
