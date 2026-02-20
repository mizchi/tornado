// ── Session state file: .tornado/session.json ──

let session_file : String = ".tornado/session.json"

fn main {
  let args = @sys.get_cli_args()
  let command = @cli.parse_cli_args(args, is_existing_file)
  match command {
    @cli.CliCommand::Run(
      config_path=config_path,
      plan_path=plan_path,
      dev_kind=dev_kind,
      review_kind=review_kind,
      review_interval=review_interval,
      rlm=rlm,
      warnings=warnings,
    ) => {
      for w in warnings {
        log("WARN", w)
      }
      let initial_task = load_plan_task(plan_path)
      run_repl(
        config_path,
        plan_path,
        rlm,
        initial_task,
        dev_kind,
        review_kind,
        review_interval,
      )
    }
    @cli.CliCommand::Validate(path) =>
      match path {
        Some(config_path) => run_validate(config_path)
        None => println("Usage: tornado validate <config.json>")
      }
    @cli.CliCommand::Help => print_usage()
  }
}

///|
fn print_usage() -> Unit {
  println("tornado - multi-agent development orchestrator")
  println("")
  println("Usage:")
  println(
    "  tornado <plan.md> [--dev=codex] [--review=claude]  # start from plan file",
  )
  println(
    "  tornado --config=tornado.json [--dev=codex] [--review=claude]",
  )
  println(
    "  tornado                    # start with preset (dev:claude-code, review:codex)",
  )
  println("  tornado --dev=codex --review=claude")
  println("  tornado --review-interval=3          # review every 3 dev iterations")
  println("  tornado --rlm TODO.md                # improvement loop mode")
  println("  tornado validate <config>  # validate config file")
  println("")
  println("Agent kind options: claude | claude-code | codex | api | mock")
  println("")
  println("Options:")
  println("  --review-interval=N  Run N dev iterations per review (default: 1)")
  println("  --rlm                Enable improvement loop mode (measure→improve→verify→commit/revert)")
  println("")
  println("Autonomous heartbeat: dev runs → reviewer reviews →")
  println("dev continues with next task → forever until Ctrl+C.")
  println("Session auto-saved to .tornado/session.json for resume.")
}

fn is_existing_file(path : String) -> Bool {
  let content = read_file_sync(path)
  not(content.has_prefix("ERROR:"))
}

fn load_plan_task(plan_path : String?) -> String? {
  match plan_path {
    Some(path) => {
      // Verify the file exists and is readable
      let content = read_file_sync(path)
      if content.has_prefix("ERROR:") {
        log("WARN", "Failed to read plan file \{path}: \{content}")
        None
      } else if content.trim().to_string().is_empty() {
        log("WARN", "Plan file is empty: \{path}")
        None
      } else {
        log("BOOT", "Using plan file: \{path}")
        Some(build_plan_file_task(path, ""))
      }
    }
    None => None
  }
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

///| Timestamped log with ANSI color coding by level
fn log(level : String, msg : String) -> Unit {
  let ts = now_timestamp()
  let color = match level {
    "CALL" => "\u001b[90m"
    "DONE" => "\u001b[36m"
    "ERROR" => "\u001b[31m"
    "WARN" => "\u001b[33m"
    "HEARTBEAT" => "\u001b[1m"
    _ => ""
  }
  if color.is_empty() {
    println("[\{ts}] [\{level}] \{msg}")
  } else {
    println("\{color}[\{ts}] [\{level}] \{msg}\u001b[0m")
  }
}

///| Delegate to @display module
fn truncate(s : String, max : Int) -> String {
  @display.truncate(s, max)
}

///| Delegate to @display module
fn format_tool_call(name : String, input_json : String) -> String {
  @display.format_tool_call(name, input_json)
}

///| Delegate to @display module
fn format_tool_result(name : String, output : String) -> String {
  @display.format_tool_result(name, output)
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
    println("  review_interval: \{config.review_interval}")
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
  dev_since_review : Int
  accumulated_dev_outputs : Array[String]
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
  obj["dev_since_review"] = state.dev_since_review.to_json()
  obj["accumulated_dev_outputs"] = state.accumulated_dev_outputs.to_json()
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
      let dev_since_review = match map.get("dev_since_review") {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
      let accumulated_dev_outputs : Array[String] = []
      match map.get("accumulated_dev_outputs") {
        Some(Array(arr)) =>
          for item in arr {
            match item {
              String(s) => accumulated_dev_outputs.push(s)
              _ => ()
            }
          }
        _ => ()
      }
      Some(
        {
          iteration,
          phase,
          task,
          dev_output,
          review_summary,
          agent_sessions,
          dev_since_review,
          accumulated_dev_outputs,
        },
      )
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

// ── Plan file task builder ───────────────────────────────────

///| Derive archive path: "TODO.md" → "TODO.archive.md", "plan" → "plan.archive.md"
fn derive_archive_path(plan_path : String) -> String {
  if plan_path.has_suffix(".md") && plan_path.length() > 3 {
    let buf = StringBuilder::new()
    let mut i = 0
    let stop = plan_path.length() - 3
    for ch in plan_path {
      if i >= stop {
        break
      }
      buf.write_char(ch)
      i += 1
    }
    buf.write_string(".archive.md")
    buf.to_string()
  } else {
    plan_path + ".archive.md"
  }
}

///| Build a task prompt that directs the agent to read/write the plan file
fn build_plan_file_task(plan_path : String, review_summary : String) -> String {
  let context = gather_review_context()
  let buf = StringBuilder::new()
  buf.write_string(
    "You are in an autonomous development loop.\n\n",
  )
  buf.write_string("## Plan File: \{plan_path}\n")
  buf.write_string("Read this file to see your current task list.\n\n")
  buf.write_string("## Instructions\n")
  buf.write_string("1. Read `\{plan_path}` to understand the current tasks\n")
  buf.write_string(
    "2. Pick the highest-priority uncompleted task and implement it\n",
  )
  buf.write_string(
    "3. After completing work, update `\{plan_path}` to mark the task as done\n",
  )
  // Derive archive path: foo.md → foo.archive.md, other → other.archive.md
  let archive_path = derive_archive_path(plan_path)
  buf.write_string(
    "4. If the file has many completed items (10+), archive them to `\{archive_path}`\n\n",
  )
  if not(review_summary.is_empty()) {
    buf.write_string("## Review Feedback\n")
    buf.write_string(truncate(review_summary, 2000))
    buf.write_string("\n\n")
  }
  if not(context.is_empty()) {
    buf.write_string("## Current Project State\n")
    buf.write_string(context)
  }
  buf.to_string()
}

// ── Join accumulated dev outputs ─────────────────────────────

///| Combine multiple dev outputs into a structured summary
fn join_dev_outputs(outputs : Array[String]) -> String {
  let buf = StringBuilder::new()
  let mut i = 0
  for output in outputs {
    i += 1
    buf.write_string("### Dev Iteration \{i}\n")
    buf.write_string(output)
    buf.write_string("\n\n")
  }
  buf.to_string()
}

// ── Improvement loop task builder (RLM) ─────────────────────

///| Build improvement loop prompt for --rlm mode
fn build_improvement_task(
  prev_output : String,
  current_step : Int,
  total_steps : Int,
  cycle_summary~ : String = "",
) -> String {
  let context = gather_review_context()
  let buf = StringBuilder::new()
  buf.write_string("You are in an autonomous IMPROVEMENT loop.\n")
  buf.write_string(
    "Budget: iteration \{current_step}/\{total_steps} before next review.\n\n",
  )
  if not(cycle_summary.is_empty()) {
    buf.write_string("## Previous Cycle Summary\n")
    buf.write_string(cycle_summary)
    buf.write_string("\n\n")
  }
  if not(context.is_empty()) {
    buf.write_string("## Current Project State\n")
    buf.write_string(context)
    buf.write_string("\n")
  }
  if not(prev_output.is_empty()) {
    buf.write_string("## Previous Iteration Output\n")
    buf.write_string(truncate(prev_output, 2000))
    buf.write_string("\n\n")
  }
  buf.write_string("## Improvement Protocol\n")
  buf.write_string(
    "1. **Measure Baseline**: Run tests, record pass/fail counts, build status, coverage\n",
  )
  buf.write_string(
    "2. **Make ONE Focused Improvement**: Choose exactly one of: fix / test / refactor / optimize\n",
  )
  buf.write_string(
    "3. **Validate**: Re-run tests, compare with baseline. No regression + improvement = ACCEPTABLE\n",
  )
  buf.write_string(
    "4. **Commit or Revert**: If acceptable, commit with descriptive message. Otherwise `git checkout .`\n",
  )
  buf.write_string("5. **Report**: Output a structured summary in this format:\n\n")
  buf.write_string("```\n")
  buf.write_string("IMPROVEMENT_REPORT:\n")
  buf.write_string("  type: <fix|test|refactor|optimize>\n")
  buf.write_string("  baseline: tests=N/N, build=ok|fail\n")
  buf.write_string("  result: tests=N/N, build=ok|fail\n")
  buf.write_string("  verdict: committed|reverted\n")
  buf.write_string("  summary: <one-line description of what changed>\n")
  buf.write_string("```\n")
  buf.to_string()
}

// ── Cycle summary builder ────────────────────────────────────

///| Build a human-readable summary of what happened in this cycle
fn build_cycle_summary(
  iteration : Int,
  dev_outputs : Array[String],
  review_summary : String,
) -> String {
  let buf = StringBuilder::new()
  buf.write_string("## Cycle \{iteration} Summary\n\n")
  let mut i = 0
  for output in dev_outputs {
    i += 1
    buf.write_string("### Dev Step \{i}\n")
    buf.write_string(truncate(output, 1000))
    buf.write_string("\n\n")
  }
  if not(review_summary.is_empty()) {
    buf.write_string("### Review\n")
    buf.write_string(truncate(review_summary, 500))
    buf.write_string("\n")
  }
  buf.to_string()
}

// ── Next task router ─────────────────────────────────────────

///| Build the next dev task based on plan/rlm mode
fn build_next_task(
  plan_path : String?,
  rlm : Bool,
  review_summary : String,
  prev_output : String,
  current_step~ : Int = 1,
  total_steps~ : Int = 1,
  cycle_summary~ : String = "",
) -> String {
  match (plan_path, rlm) {
    (Some(path), true) => {
      let base = build_plan_file_task(path, review_summary)
      let improvement = build_improvement_task(
        prev_output, current_step, total_steps, cycle_summary~,
      )
      base + "\n\n" + improvement
    }
    (Some(path), false) => build_plan_file_task(path, review_summary)
    (None, true) =>
      build_improvement_task(
        prev_output, current_step, total_steps, cycle_summary~,
      )
    (None, false) => build_continuation_task(prev_output, review_summary)
  }
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
fn run_repl(
  config_path : String?,
  plan_path : String?,
  rlm : Bool,
  initial_task : String?,
  dev_kind : @types.AgentKind?,
  review_kind : @types.AgentKind?,
  review_interval : Int?,
) -> Unit {
  let loaded_config = load_config(config_path)
  let config = @cli.apply_overrides(
    loaded_config,
    dev_kind~,
    review_kind~,
    review_interval~,
  )
  println("")
  println("  tornado - autonomous development orchestrator")
  println("")
  match dev_kind {
    Some(kind) => log("BOOT", "Override: dev=\{@cli.kind_name(kind)}")
    None => ()
  }
  match review_kind {
    Some(kind) => log("BOOT", "Override: review=\{@cli.kind_name(kind)}")
    None => ()
  }
  log("BOOT", "Agents:")
  for agent in config.agents {
    log("BOOT", "  \{agent.id} (\{agent.kind}, \{agent.role})")
  }
  log("BOOT", "Max review cycles: \{config.max_review_cycles}")
  log("BOOT", "Review interval: every \{config.review_interval} dev iteration(s)")
  if rlm {
    log("BOOT", "RLM improvement loop mode: enabled")
  }
  println("")
  let backends = @agent.create_backends(config.agents)
  let dev_id = find_agent_id(config.agents, @types.AgentRole::Dev)
  let reviewer_id = find_agent_id(config.agents, @types.AgentRole::Review)
  let agent_sessions : Map[String, String] = {}
  let mut iteration = 0
  let mut next_task : String = ""
  let mut last_review_summary : String = ""
  let mut dev_since_review = 0
  let accumulated_dev_outputs : Array[String] = []
  let mut last_cycle_summary : String = ""
  // ── Token usage tracking ──
  let mut total_input_tokens = 0
  let mut total_output_tokens = 0
  let mut total_cache_read = 0
  let mut total_cache_write = 0
  let mut total_cost_usd = 0.0
  // ── Check for saved session ──
  if initial_task is None {
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
          dev_since_review = saved.dev_since_review
          for output in saved.accumulated_dev_outputs {
            accumulated_dev_outputs.push(output)
          }
          match saved.phase {
            "dev" | "review" => next_task = saved.task
            _ => {
              // idle → previous iteration done, build continuation
              next_task = match plan_path {
                Some(path) =>
                  build_plan_file_task(path, saved.review_summary)
                None =>
                  build_continuation_task(
                    saved.task, saved.review_summary,
                  )
              }
            }
          }
        }
      }
      None => ()
    }
  } else {
    log("BOOT", "Plan file mode: skip session resume")
  }
  // ── Get initial task if needed ──
  if next_task.is_empty() {
    match initial_task {
      Some(task) => {
        next_task = task
        log("HEARTBEAT", "Starting from provided plan file")
      }
      None => {
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
        dev_since_review,
        accumulated_dev_outputs,
      },
    )
    // Per-iteration usage tracking
    let mut iter_input_tokens = 0
    let mut iter_output_tokens = 0
    let mut iter_cache_read = 0
    let mut iter_cache_write = 0
    let mut iter_cost_usd = 0.0
    let on_usage : (Int, Int, Int, Int, Double) -> Unit = fn(
      it, ot, cr, cw, cost
    ) {
      iter_input_tokens += it
      iter_output_tokens += ot
      iter_cache_read += cr
      iter_cache_write += cw
      iter_cost_usd += cost
      total_input_tokens += it
      total_output_tokens += ot
      total_cache_read += cr
      total_cache_write += cw
      total_cost_usd += cost
    }
    let dev_result = run_dev(
      dev_id, backends, next_task, agent_sessions, on_usage~,
    )
    dev_since_review += 1
    accumulated_dev_outputs.push(truncate(dev_result, 5000))
    // ── Check for user interrupt after dev ──
    let post_dev_interrupt = check_interrupt()
    if not(post_dev_interrupt.is_empty()) {
      log(
        "USER",
        "User instructions for review: \{truncate(post_dev_interrupt, 100)}",
      )
    }
    // ── Skip review if dev produced no output (likely failed) ──
    if dev_result.trim().is_empty() {
      log("HEARTBEAT", "Dev produced no output, skipping review")
      last_review_summary = "Dev agent produced no output - likely failed"
      save_session(
        {
          iteration,
          phase: "idle",
          task: next_task,
          dev_output: dev_result,
          review_summary: last_review_summary,
          agent_sessions,
          dev_since_review,
          accumulated_dev_outputs,
        },
      )
      continue
    }
    // ── review_interval check: only review after N dev iterations ──
    if dev_since_review < config.review_interval {
      log(
        "HEARTBEAT",
        "Dev \{dev_since_review}/\{config.review_interval} before review",
      )
      log("SUMMARY", "Dev output: \{truncate(dev_result, 300)}")
      log("HEARTBEAT", "=== Iteration \{iteration} complete (no review) ===")
      log(
        "USAGE",
        "Iter \{iteration}: \{iter_input_tokens}in/\{iter_output_tokens}out (cache: \{iter_cache_read}r/\{iter_cache_write}w), $\{iter_cost_usd}",
      )
      log(
        "USAGE",
        "Total: \{total_input_tokens}in/\{total_output_tokens}out (cache: \{total_cache_read}r/\{total_cache_write}w), $\{total_cost_usd}",
      )
      save_session(
        {
          iteration,
          phase: "idle",
          task: next_task,
          dev_output: dev_result,
          review_summary: last_review_summary,
          agent_sessions,
          dev_since_review,
          accumulated_dev_outputs,
        },
      )
      // Build next task without review feedback
      let user_input = check_interrupt()
      if not(user_input.is_empty()) {
        log("USER", "Using user instructions: \{truncate(user_input, 100)}")
        next_task = user_input
      } else {
        next_task = build_next_task(
          plan_path,
          rlm,
          "",
          dev_result,
          current_step=dev_since_review,
          total_steps=config.review_interval,
          cycle_summary=last_cycle_summary,
        )
      }
      if not(post_dev_interrupt.is_empty()) {
        next_task = next_task + "\n\n## Additional Instructions from User\n" +
          post_dev_interrupt
      }
      continue
    }
    // ── review phase ──
    let combined_dev_output = join_dev_outputs(accumulated_dev_outputs)
    save_session(
      {
        iteration,
        phase: "review",
        task: next_task,
        dev_output: dev_result,
        review_summary: last_review_summary,
        agent_sessions,
        dev_since_review,
        accumulated_dev_outputs,
      },
    )
    let review_result = match reviewer_id {
      Some(rid) =>
        run_review(
          dev_id,
          rid,
          backends,
          next_task,
          combined_dev_output,
          config.max_review_cycles,
          agent_sessions,
          on_usage~,
        )
      None => {
        log("SKIP", "No reviewer configured")
        ReviewOutcome::Approved("")
      }
    }
    // ── Build cycle summary before clearing ──
    let review_text = match review_result {
      Approved(s) => s
      Rejected(s) => s
    }
    let cycle_summary = build_cycle_summary(
      iteration, accumulated_dev_outputs, review_text,
    )
    last_cycle_summary = cycle_summary
    log("SUMMARY", truncate(cycle_summary, 500))
    // Reset accumulated state after review
    dev_since_review = 0
    accumulated_dev_outputs.clear()
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
            dev_since_review,
            accumulated_dev_outputs,
          },
        )
        log("HEARTBEAT", "=== Iteration \{iteration} complete ===")
        log(
          "USAGE",
          "Iter \{iteration}: \{iter_input_tokens}in/\{iter_output_tokens}out (cache: \{iter_cache_read}r/\{iter_cache_write}w), $\{iter_cost_usd}",
        )
        log(
          "USAGE",
          "Total: \{total_input_tokens}in/\{total_output_tokens}out (cache: \{total_cache_read}r/\{total_cache_write}w), $\{total_cost_usd}",
        )
        // Check for user interrupt → use as next task
        let user_input = check_interrupt()
        if not(user_input.is_empty()) {
          log("USER", "Using user instructions: \{truncate(user_input, 100)}")
          next_task = user_input
        } else {
          // Auto-continue: build next task for dev
          log("HEARTBEAT", "Building next task from project state...")
          next_task = build_next_task(
            plan_path, rlm, summary, dev_result, cycle_summary=cycle_summary,
          )
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
            dev_since_review,
            accumulated_dev_outputs,
          },
        )
        log("HEARTBEAT", "=== Iteration \{iteration} complete (REJECTED) ===")
        log(
          "USAGE",
          "Iter \{iteration}: \{iter_input_tokens}in/\{iter_output_tokens}out (cache: \{iter_cache_read}r/\{iter_cache_write}w), $\{iter_cost_usd}",
        )
        log(
          "USAGE",
          "Total: \{total_input_tokens}in/\{total_output_tokens}out (cache: \{total_cache_read}r/\{total_cache_write}w), $\{total_cost_usd}",
        )
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

///| Run dev agent, return output and call on_usage for token tracking
fn run_dev(
  dev_id : String?,
  backends : Map[String, @agent.BoxedBackend],
  task : String,
  agent_sessions : Map[String, String],
  on_usage~ : (Int, Int, Int, Int, Double) -> Unit = fn(_, _, _, _, _) {  },
) -> String {
  let id = dev_id.unwrap_or("dev")
  match backends.get(id) {
    Some(backend) => {
      match agent_sessions.get(id) {
        Some(sid) => log("DEV", "Starting \{id} (resume: \{sid})...")
        None => log("DEV", "Starting \{id} (new session)...")
      }
      println("")
      let line_active = [false]
      let result = backend.run(task, "", fn(event) {
        match event {
          @types.AgentEvent::OutputLine(text) => {
            let buf = StringBuilder::new()
            for ch in text {
              if not(line_active[0]) {
                buf.write_string("  [\{id}] ")
                line_active[0] = true
              }
              if ch == '\n' {
                buf.write_char('\n')
                line_active[0] = false
              } else {
                buf.write_char(ch)
              }
            }
            let s = buf.to_string()
            if not(s.is_empty()) {
              print_inline(s)
            }
          }
          @types.AgentEvent::Info(msg) => {
            if line_active[0] {
              print_inline("\n")
              line_active[0] = false
            }
            log("INFO", "\{id}: \{msg}")
          }
          @types.AgentEvent::ToolCall(name=tool_name, input=tool_input) => {
            if line_active[0] {
              print_inline("\n")
              line_active[0] = false
            }
            log("CALL", "\{id} \{format_tool_call(tool_name, tool_input)}")
          }
          @types.AgentEvent::ToolResult(name=tool_name, output=tool_output) => {
            if line_active[0] {
              print_inline("\n")
              line_active[0] = false
            }
            log(
              "DONE",
              "\{id} \{format_tool_result(tool_name, tool_output)}",
            )
          }
          @types.AgentEvent::SubAgentStart(
            agent_type=agent_type,
            task=desc,
          ) => {
            if line_active[0] {
              print_inline("\n")
              line_active[0] = false
            }
            log(
              "AGENT",
              "\{id} spawned \{agent_type}: \{truncate(desc, 80)}",
            )
          }
          @types.AgentEvent::SubAgentEnd(agent_type=agent_type) => {
            if line_active[0] {
              print_inline("\n")
              line_active[0] = false
            }
            log("AGENT", "\{id} \{agent_type} completed")
          }
          @types.AgentEvent::StatusChange(status) => {
            if line_active[0] {
              print_inline("\n")
              line_active[0] = false
            }
            log("DEV", "\{id} -> \{status}")
          }
          @types.AgentEvent::SessionId(sid) => {
            if line_active[0] {
              print_inline("\n")
              line_active[0] = false
            }
            agent_sessions[id] = sid
            log("DEV", "\{id} session: \{sid}")
          }
          @types.AgentEvent::Usage(
            input_tokens=it,
            output_tokens=ot,
            cache_read=cr,
            cache_write=cw,
            cost_usd=cost,
          ) => on_usage(it, ot, cr, cw, cost)
        }
      })
      if line_active[0] {
        print_inline("\n")
      }
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
  on_usage~ : (Int, Int, Int, Int, Double) -> Unit = fn(_, _, _, _, _) {  },
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
              "CALL",
              "\{reviewer_id} \{format_tool_call(tool_name, tool_input)}",
            )
          @types.AgentEvent::ToolResult(
            name=tool_name,
            output=tool_output,
          ) =>
            log(
              "DONE",
              "\{reviewer_id} \{format_tool_result(tool_name, tool_output)}",
            )
          @types.AgentEvent::StatusChange(status) =>
            log("REVIEW", "\{reviewer_id} -> \{status}")
          @types.AgentEvent::SessionId(sid) => {
            agent_sessions[reviewer_id] = sid
            log("REVIEW", "\{reviewer_id} session: \{sid}")
          }
          @types.AgentEvent::Usage(
            input_tokens=it,
            output_tokens=ot,
            cache_read=cr,
            cache_write=cw,
            cost_usd=cost,
          ) => on_usage(it, ot, cr, cw, cost)
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
          let mut latest_summary = review.summary
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
              dev_id, backends, rework_task, agent_sessions, on_usage~,
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
                latest_summary = rework_review.summary
              }
              Rejected(reason) => {
                log("REVIEW", "REJECTED: \{reason}")
                return ReviewOutcome::Rejected(reason)
              }
            }
          }
          log("REVIEW", "Max review cycles reached, continuing anyway")
          ReviewOutcome::Approved(latest_summary)
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
