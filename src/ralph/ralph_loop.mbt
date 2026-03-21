///| Main ralph loop state machine
pub struct RalphLoop {
  config : @config.ProjectConfig
  milestone_manager : MilestoneManager
  planner : PlannerAgent?
  verifier : VerifierAgent?
  backends : Map[String, @agent.BoxedBackend]
  callbacks : @types.OrchestratorCallbacks
  mut current_phase : @types.RalphPhase
  max_rework_attempts : Int
  mut session_pool : Array[String]
}

///| Create a new ralph loop
pub fn RalphLoop::new(
  config : @config.ProjectConfig,
  milestone_manager : MilestoneManager,
  backends : Map[String, @agent.BoxedBackend],
  callbacks : @types.OrchestratorCallbacks,
  lang~ : String = "en",
) -> RalphLoop {
  let planner_id = find_agent_id(config, @types.AgentRole::Planner)
  let verifier_id = find_agent_id(config, @types.AgentRole::Verifier)
  let planner : PlannerAgent? = match planner_id {
    Some(id) => Some(PlannerAgent::new(agent_id=id, lang~))
    None => None
  }
  let verifier : VerifierAgent? = match verifier_id {
    Some(id) => Some(VerifierAgent::new(agent_id=id, lang~))
    None => None
  }
  {
    config,
    milestone_manager,
    planner,
    verifier,
    backends,
    callbacks,
    current_phase: @types.RalphPhase::LoadingMilestones,
    max_rework_attempts: config.max_rework_attempts,
    session_pool: [],
  }
}

///| Run the ralph loop to completion
pub fn RalphLoop::run(self : RalphLoop) -> Unit {
  self.current_phase = LoadingMilestones
  emit_info(self, "Ralph loop started")
  while true {
    // Get next pending milestone
    let milestone = self.milestone_manager.next_pending_milestone()
    match milestone {
      None => {
        self.current_phase = AllComplete
        emit_info(self, "All milestones complete")
        return
      }
      Some(m) => {
        let success = self.run_milestone(m)
        if not(success) {
          emit_info(self, "Milestone \{m.id} failed")
        }
      }
    }
  }
}

///| Run a single milestone through planning, execution, and verification
fn RalphLoop::run_milestone(
  self : RalphLoop,
  milestone : @types.Milestone,
) -> Bool {
  // Plan if no tasks
  if milestone.tasks.is_empty() {
    match self.planner {
      Some(planner) => {
        self.current_phase = Planning(milestone.id)
        emit_info(self, "Planning milestone: \{milestone.id}")
        let planner_backend = find_backend(
          self.backends, planner.agent_id,
        )
        match planner_backend {
          Some(backend) => {
            let tasks = planner.plan(
              milestone,
              backend,
              self.milestone_manager.brief,
              self.milestone_manager.milestones,
              self.milestone_manager,
              on_event=fn(e) { handle_event(self, planner.agent_id, e) },
            )
            if tasks.is_empty() {
              emit_info(self, "Planner produced no tasks for \{milestone.id}")
              milestone.status = Failed("No tasks planned")
              return false
            }
            milestone.tasks = tasks
          }
          None => {
            emit_info(self, "No backend found for planner")
            milestone.status = Failed("No planner backend")
            return false
          }
        }
      }
      None => {
        emit_info(self, "No planner configured, skipping planning")
      }
    }
  }
  // Execute waves
  milestone.status = @types.MilestoneStatus::InProgress
  while self.milestone_manager.has_undone_tasks(milestone) {
    let wave = self.milestone_manager.next_wave_number(milestone)
    match wave {
      None => break
      Some(wave_num) => {
        let success = self.run_wave(milestone, wave_num)
        if not(success) {
          milestone.status = Failed("Wave \{wave_num} failed")
          return false
        }
      }
    }
  }
  let all_results = collect_all_task_results(milestone)
  let goal_ok = self.verify_goal_alignment(milestone, all_results, 0)
  if not(goal_ok) {
    match milestone.status {
      Failed(_) => ()
      _ => milestone.status = Failed("Goal alignment verification failed")
    }
    return false
  }
  milestone.summary = generate_milestone_summary(milestone)
  milestone.status = Done
  self.current_phase = MilestoneComplete(milestone.id)
  emit_info(self, "Milestone \{milestone.id} complete")
  true
}

///| Run a single wave: execute tasks, then verify
fn RalphLoop::run_wave(
  self : RalphLoop,
  milestone : @types.Milestone,
  wave : Int,
) -> Bool {
  self.current_phase = ExecutingWave(milestone.id, wave)
  emit_info(self, "Executing wave \{wave} of \{milestone.id}")
  let tasks = self.milestone_manager.get_wave_tasks(milestone, wave)
  // Find builder backend (first Dev agent)
  let builder_id = find_agent_id(self.config, @types.AgentRole::Dev)
  let builder_backend = match builder_id {
    Some(id) => find_backend(self.backends, id)
    None => None
  }
  match builder_backend {
    None => {
      emit_info(self, "No builder backend found")
      return false
    }
    Some(backend) => {
      let bid = builder_id.unwrap()
      let builder_system_prompt = build_builder_system_prompt(
        self.milestone_manager.brief,
      )
      let builder_tasks : Array[(String, String)] = []
      for task in tasks {
        task.status = InProgress(bid)
        emit_info(self, "Running task \{task.id}: \{task.description}")
        builder_tasks.push((task.description, builder_system_prompt))
      }
      let results = @agent.run_parallel(
        backend,
        builder_tasks,
        fn(e) { handle_event(self, bid, e) },
        session_ids=self.session_pool,
      )
      // Update session pool with returned session IDs for reuse
      self.session_pool = results.map(fn(r) { r.session_id })
      for i in 0..<tasks.length() {
        let task = tasks[i]
        let result = results[i]
        match result.status {
          Completed => {
            task.status = Done
            task.result = Some(result.content)
            emit_info(self, "Task \{task.id} completed")
          }
          _ => {
            let err = result.error.unwrap_or("unknown error")
            task.status = Failed(err)
            task.result = Some(result.content)
            emit_info(self, "Task \{task.id} failed: \{err}")
          }
        }
      }
    }
  }
  // Verify wave
  let wave_results = collect_wave_results(tasks)
  self.verify_wave(milestone, wave, wave_results, 0)
}

///| Verify a wave with rework loop
fn RalphLoop::verify_wave(
  self : RalphLoop,
  milestone : @types.Milestone,
  wave : Int,
  wave_results : Array[(String, String)],
  attempt : Int,
) -> Bool {
  match self.verifier {
    None => {
      // No verifier configured, auto-approve
      true
    }
    Some(verifier) => {
      self.current_phase = Verifying(milestone.id, wave)
      emit_info(
        self,
        "Verifying wave \{wave} of \{milestone.id} (attempt \{attempt + 1})",
      )
      let verifier_backend = find_backend(
        self.backends, verifier.agent_id,
      )
      match verifier_backend {
        None => {
          emit_info(self, "No verifier backend found, auto-approving")
          true
        }
        Some(backend) => {
          let verdict = verifier.verify(
            milestone,
            wave,
            wave_results,
            backend,
            "",
            perspectives=[CodeQuality, Performance, Security],
            on_event=fn(e) { handle_event(self, verifier.agent_id, e) },
          )
          match verdict {
            Approved => {
              emit_info(self, "Wave \{wave} approved")
              true
            }
            NeedsRework(items) => {
              if attempt >= self.max_rework_attempts {
                emit_info(
                  self,
                  "Max rework attempts reached for wave \{wave}, accepting as-is",
                )
                return true
              }
              self.current_phase = Reworking(milestone.id, wave)
              emit_info(
                self,
                "Rework needed for wave \{wave}: \{items.length()} issues",
              )
              // Re-execute failed tasks
              let reworked = self.rework_tasks(milestone, wave, items)
              self.verify_wave(milestone, wave, reworked, attempt + 1)
            }
            MilestoneFailed(reason) => {
              emit_info(self, "Milestone failed: \{reason}")
              milestone.status = Failed(reason)
              false
            }
          }
        }
      }
    }
  }
}

///| Verify overall milestone goal alignment after all waves are complete
fn RalphLoop::verify_goal_alignment(
  self : RalphLoop,
  milestone : @types.Milestone,
  all_results : Array[(String, String)],
  attempt : Int,
) -> Bool {
  match self.verifier {
    None => true
    Some(verifier) => {
      let verification_wave = last_wave_number(milestone)
      self.current_phase = Verifying(milestone.id, verification_wave)
      emit_info(
        self,
        "Verifying goal alignment for \{milestone.id} (attempt \{attempt + 1})",
      )
      let verifier_backend = find_backend(
        self.backends, verifier.agent_id,
      )
      match verifier_backend {
        None => {
          emit_info(self, "No verifier backend found, auto-approving")
          true
        }
        Some(backend) => {
          let verdict = verifier.verify(
            milestone,
            verification_wave,
            all_results,
            backend,
            "",
            perspectives=[GoalAlignment],
            on_event=fn(e) { handle_event(self, verifier.agent_id, e) },
          )
          match verdict {
            Approved => {
              emit_info(self, "Goal alignment approved for \{milestone.id}")
              true
            }
            NeedsRework(items) => {
              if attempt >= self.max_rework_attempts {
                emit_info(
                  self,
                  "Max rework attempts reached for goal alignment, accepting as-is",
                )
                return true
              }
              self.current_phase = Reworking(milestone.id, verification_wave)
              emit_info(
                self,
                "Goal alignment rework needed for \{milestone.id}: \{items.length()} issues",
              )
              let reworked = self.rework_milestone_tasks(milestone, items)
              self.verify_goal_alignment(milestone, reworked, attempt + 1)
            }
            MilestoneFailed(reason) => {
              emit_info(self, "Milestone failed: \{reason}")
              milestone.status = Failed(reason)
              false
            }
          }
        }
      }
    }
  }
}

fn strip_task_feedback_prefix(item : String, task_id : String) -> String {
  let colon_prefix = task_id + ":"
  if item.has_prefix(colon_prefix) {
    return item
      .view(start_offset=colon_prefix.length())
      .to_string()
      .trim()
      .to_string()
  }
  let space_prefix = task_id + " "
  if item.has_prefix(space_prefix) {
    return item
      .view(start_offset=space_prefix.length())
      .to_string()
      .trim()
      .to_string()
  }
  item
}

///| Re-execute tasks that need rework
fn RalphLoop::rework_tasks(
  self : RalphLoop,
  milestone : @types.Milestone,
  wave : Int,
  feedback : Array[String],
) -> Array[(String, String)] {
  let tasks = self.milestone_manager.get_wave_tasks(milestone, wave)
  self.rework_task_list(tasks, feedback)
  collect_wave_results(tasks)
}

///| Re-execute milestone tasks that need rework
fn RalphLoop::rework_milestone_tasks(
  self : RalphLoop,
  milestone : @types.Milestone,
  feedback : Array[String],
) -> Array[(String, String)] {
  let tasks = milestone.tasks
  self.rework_task_list(tasks, feedback)
  collect_all_task_results(milestone)
}

fn RalphLoop::rework_task_list(
  self : RalphLoop,
  tasks : Array[@types.RalphTask],
  feedback : Array[String],
) -> Unit {
  let mut matched_any = false
  for item in feedback {
    for task in tasks {
      if item.has_prefix(task.id + ":") || item.has_prefix(task.id + " ") {
        task.status = Pending
        matched_any = true
      }
    }
  }
  if not(matched_any) && not(feedback.is_empty()) {
    for task in tasks {
      match task.status {
        Done => task.status = Pending
        _ => ()
      }
    }
  }

  let builder_id = find_agent_id(self.config, @types.AgentRole::Dev)
  let builder_backend = match builder_id {
    Some(id) => find_backend(self.backends, id)
    None => None
  }
  match builder_backend {
    None => ()
    Some(backend) => {
      let bid = builder_id.unwrap()
      let builder_system_prompt = build_builder_system_prompt(
        self.milestone_manager.brief,
      )
      let rework_tasks : Array[@types.RalphTask] = []
      let builder_tasks : Array[(String, String)] = []
      for task in tasks {
        match task.status {
          Failed(_) | Pending => {
            task.status = InProgress(bid)
            let task_feedback = StringBuilder::new()
            for item in feedback {
              if item.has_prefix(task.id + ":") || item.has_prefix(task.id + " ") {
                let task_feedback_item = strip_task_feedback_prefix(item, task.id)
                task_feedback.write_string("- ")
                task_feedback.write_string(task_feedback_item)
                task_feedback.write_string("\n")
              }
            }
            let task_feedback_str = task_feedback.to_string()
            let feedback_str = if task_feedback_str.is_empty() {
              feedback.iter().fold(
                init="",
                fn(acc, item) { acc + "- " + item + "\n" },
              )
            } else {
              task_feedback_str
            }
            let rework_prompt = task.description +
              "\n\nFeedback from verifier:\n" + feedback_str
            emit_info(self, "Reworking task \{task.id}")
            rework_tasks.push(task)
            builder_tasks.push((rework_prompt, builder_system_prompt))
          }
          _ => ()
        }
      }
      let results = @agent.run_parallel(
        backend,
        builder_tasks,
        fn(e) { handle_event(self, bid, e) },
        session_ids=self.session_pool,
      )
      // Update session pool with returned session IDs for reuse
      self.session_pool = results.map(fn(r) { r.session_id })
      for i in 0..<rework_tasks.length() {
        let task = rework_tasks[i]
        let result = results[i]
        match result.status {
          Completed => {
            task.status = Done
            task.result = Some(result.content)
          }
          _ => {
            let err = result.error.unwrap_or("rework failed")
            task.status = Failed(err)
            task.result = Some(result.content)
          }
        }
      }
    }
  }
}

// --- Internal helpers ---

///| Build system prompt for Planner: brief + completed milestone summaries
fn build_planner_system_prompt(
  brief : String,
  milestones : Array[@types.Milestone],
) -> String {
  let buf = StringBuilder::new()
  buf.write_string(
    "You are a planning agent that breaks down milestones into executable tasks.\n\n",
  )
  if not(brief.is_empty()) {
    buf.write_string("## Brief\n")
    buf.write_string(brief)
    buf.write_string("\n\n")
  }
  let mut has_completed = false
  for m in milestones {
    if m.status == @types.MilestoneStatus::Done && not(m.summary.is_empty()) {
      if not(has_completed) {
        buf.write_string("## Completed Milestones\n")
        has_completed = true
      }
      buf.write_string("- ")
      buf.write_string(m.id)
      buf.write_string(": ")
      buf.write_string(m.summary)
      buf.write_string("\n")
    }
  }
  if has_completed {
    buf.write_string("\n")
  }
  buf.to_string()
}

///| Build system prompt for Builder/Rework: brief only
fn build_builder_system_prompt(brief : String) -> String {
  if brief.is_empty() {
    return ""
  }
  "## Brief\n" + brief + "\n"
}

///| Generate milestone summary from completed task descriptions
fn generate_milestone_summary(milestone : @types.Milestone) -> String {
  let parts : Array[String] = []
  for task in milestone.tasks {
    if task.status == @types.TaskStatus::Done {
      parts.push(task.description)
    }
  }
  if parts.is_empty() {
    return milestone.goal
  }
  join_strings(parts, "; ")
}

fn find_agent_id(
  config : @config.ProjectConfig,
  role : @types.AgentRole,
) -> String? {
  for agent in config.agents {
    if agent.role == role {
      return Some(agent.id)
    }
  }
  None
}

fn find_backend(
  backends : Map[String, @agent.BoxedBackend],
  id : String,
) -> @agent.BoxedBackend? {
  backends.get(id)
}

fn collect_wave_results(
  tasks : Array[@types.RalphTask],
) -> Array[(String, String)] {
  let results : Array[(String, String)] = []
  for task in tasks {
    let content = match task.result {
      Some(r) => r
      None => "(no output)"
    }
    results.push((task.id, content))
  }
  results
}

fn collect_all_task_results(
  milestone : @types.Milestone,
) -> Array[(String, String)] {
  let results : Array[(String, String)] = []
  for task in milestone.tasks {
    let content = match task.result {
      Some(r) => r
      None => "(no output)"
    }
    results.push((task.id, content))
  }
  results
}

fn last_wave_number(milestone : @types.Milestone) -> Int {
  let mut wave = 0
  for task in milestone.tasks {
    if task.wave > wave {
      wave = task.wave
    }
  }
  wave
}

fn handle_event(
  rl : RalphLoop,
  agent_id : String,
  event : @types.AgentEvent,
) -> Unit {
  match event {
    OutputLine(line) => (rl.callbacks.on_agent_output)(agent_id, line)
    Info(msg) => (rl.callbacks.on_info)(msg)
    _ => ()
  }
}

fn emit_info(rl : RalphLoop, msg : String) -> Unit {
  (rl.callbacks.on_info)(msg)
}
