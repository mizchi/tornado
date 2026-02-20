///| Orchestrator manages the full session lifecycle
pub struct Orchestrator {
  config : @config.ProjectConfig
  task_manager : @task.TaskManager
  review_agent : @review.ReviewAgent?
  backends : Map[String, @agent.BoxedBackend]
  callbacks : @types.OrchestratorCallbacks
  mut review_cycles : Int
}

///| Create a new Orchestrator
pub fn Orchestrator::new(
  config : @config.ProjectConfig,
  backends : Map[String, @agent.BoxedBackend],
  callbacks : @types.OrchestratorCallbacks,
) -> Orchestrator {
  let review_agent : @types.AgentConfig? = config.agents
    .iter()
    .find_first(fn(a) { a.role == Review })
  let ra : @review.ReviewAgent? = match review_agent {
    Some(a) => Some(@review.ReviewAgent::new(a.id))
    None => None
  }
  {
    config,
    task_manager: @task.TaskManager::new(),
    review_agent: ra,
    backends,
    callbacks,
    review_cycles: 0,
  }
}

///| Run the full orchestration cycle
pub fn Orchestrator::run(
  self : Orchestrator,
  session : @types.Session,
) -> Unit {
  // Phase: Decomposing
  self.transition(session, @types.OrchestratorPhase::Decomposing)
  self.decompose_tasks(session)
  // Phase: Assigning
  self.transition(session, @types.OrchestratorPhase::Assigning)
  self.assign_tasks(session)
  // Phase: Executing
  self.transition(session, @types.OrchestratorPhase::Executing)
  self.execute_tasks(session)
  // Phase: Reviewing
  if self.review_agent is Some(_) {
    self.transition(session, @types.OrchestratorPhase::Reviewing)
    self.review_tasks(session)
    // Phase: Iterating (if needed)
    while self.needs_iteration(session) &&
          self.review_cycles < self.config.max_review_cycles {
      self.transition(session, @types.OrchestratorPhase::Iterating)
      self.iterate_tasks(session)
      self.transition(session, @types.OrchestratorPhase::Reviewing)
      self.review_tasks(session)
    }
  }
  // Phase: Finalizing
  self.transition(session, @types.OrchestratorPhase::Finalizing)
  session.status = @types.SessionStatus::Completed
  (self.callbacks.on_session_complete)(session.id)
}

///| Transition to a new phase
fn Orchestrator::transition(
  self : Orchestrator,
  session : @types.Session,
  phase : @types.OrchestratorPhase,
) -> Unit {
  session.current_phase = phase
  (self.callbacks.on_phase_change)(session.id, phase)
}

///| Decompose the user task into sub-tasks
fn Orchestrator::decompose_tasks(
  self : Orchestrator,
  session : @types.Session,
) -> Unit {
  let decomposer = self.find_backend_for_role(@types.AgentRole::Dev)
  match decomposer {
    Some((id, backend)) => {
      (self.callbacks.on_info)("Decomposing task with agent \{id}...")
      let prompt =
        "Break down the following task into concrete sub-tasks (one per line):\n\n\{session.user_task}"
      let result = backend.run(prompt, "You are a task decomposer.", fn(event) {
        match event {
          @types.AgentEvent::OutputLine(line) =>
            (self.callbacks.on_agent_output)(id, line)
          _ => ()
        }
      })
      match result.status {
        Failed(err) => {
          (self.callbacks.on_info)(
            "Decomposition failed: \{err}",
          )
          (self.callbacks.on_info)(
            "Falling back to single task",
          )
          let task = self.task_manager.add_task(session.user_task)
          session.tasks.push(task)
        }
        _ => {
          let tasks = self.task_manager.parse_tasks(result.content)
          if tasks.is_empty() {
            (self.callbacks.on_info)(
              "No sub-tasks parsed, using original task",
            )
            let task = self.task_manager.add_task(session.user_task)
            session.tasks.push(task)
          } else {
            (self.callbacks.on_info)(
              "Decomposed into \{tasks.length()} sub-tasks",
            )
            for task in tasks {
              session.tasks.push(task)
            }
          }
          (self.callbacks.on_agent_complete)(id, result.content)
        }
      }
    }
    None => {
      (self.callbacks.on_info)("No decomposer available, using task as-is")
      let task = self.task_manager.add_task(session.user_task)
      session.tasks.push(task)
    }
  }
}

///| Assign tasks to dev agents using round-robin
fn Orchestrator::assign_tasks(
  self : Orchestrator,
  session : @types.Session,
) -> Unit {
  let dev_agents : Array[@types.AgentConfig] = session.agents
    .iter()
    .filter(fn(a) { a.role == Dev })
    .collect()
  if dev_agents.is_empty() {
    (self.callbacks.on_info)("No dev agents available for assignment")
    return
  }
  let mut agent_idx = 0
  for task in session.tasks {
    if task.is_pending() {
      let agent = dev_agents[agent_idx % dev_agents.length()]
      task.assign(agent.id)
      (self.callbacks.on_task_assign)(task.id, agent.id)
      agent_idx += 1
    }
  }
}

///| Execute all assigned tasks
fn Orchestrator::execute_tasks(
  self : Orchestrator,
  session : @types.Session,
) -> Unit {
  let total = session.tasks.length()
  let mut done = 0
  for task in session.tasks {
    match task.status {
      InProgress(agent_id) => {
        done += 1
        (self.callbacks.on_task_start)(task.id, task.description, agent_id)
        let backend = self.backends.get(agent_id)
        match backend {
          Some(b) => {
            let result = b.run(task.description, "", fn(event) {
              match event {
                @types.AgentEvent::OutputLine(line) =>
                  (self.callbacks.on_agent_output)(agent_id, line)
                _ => ()
              }
            })
            match result.status {
              Completed => {
                task.complete(result.content)
                (self.callbacks.on_task_complete)(task.id, "done")
                (self.callbacks.on_agent_complete)(agent_id, result.content)
                (self.callbacks.on_info)(
                  "Progress: \{done}/\{total} tasks completed",
                )
              }
              Failed(err) => {
                task.fail(err)
                (self.callbacks.on_task_complete)(task.id, "failed: \{err}")
              }
              _ => ()
            }
          }
          None => {
            task.fail("Backend not found: \{agent_id}")
            (self.callbacks.on_task_complete)(
              task.id,
              "failed: backend not found",
            )
          }
        }
      }
      _ => ()
    }
  }
}

///| Review all completed tasks
fn Orchestrator::review_tasks(
  self : Orchestrator,
  session : @types.Session,
) -> Unit {
  self.review_cycles += 1
  (self.callbacks.on_info)(
    "Review cycle \{self.review_cycles}/\{self.config.max_review_cycles}",
  )
  match self.review_agent {
    Some(ra) => {
      let review_backend_id = self.find_review_backend_id()
      match review_backend_id {
        Some(bid) =>
          match self.backends.get(bid) {
            Some(backend) =>
              for task in session.tasks {
                if task.is_done() && task.review is None {
                  (self.callbacks.on_review_start)(task.id, ra.reviewer_id)
                  let review = ra.review(task, backend)
                  (self.callbacks.on_review_complete)(task.id, review.verdict)
                }
              }
            None =>
              (self.callbacks.on_info)(
                "Review backend \{bid} not found, skipping review",
              )
          }
        None =>
          (self.callbacks.on_info)("No review backend configured, skipping")
      }
    }
    None => ()
  }
}

///| Check if any tasks need rework
fn Orchestrator::needs_iteration(
  _self : Orchestrator,
  session : @types.Session,
) -> Bool {
  session.tasks.iter().any(fn(t) {
    match t.review {
      Some(r) => r.verdict is NeedsChanges(_)
      None => false
    }
  })
}

///| Re-execute tasks that need changes
fn Orchestrator::iterate_tasks(
  self : Orchestrator,
  session : @types.Session,
) -> Unit {
  for task in session.tasks {
    match task.review {
      Some(r) =>
        match r.verdict {
          NeedsChanges(items) => {
            let feedback = items.iter().fold(init="", fn(acc, item) {
              acc + "- " + item + "\n"
            })
            (self.callbacks.on_info)(
              "Re-working \{task.id} with feedback",
            )
            let new_desc = "\{task.description}\n\nFeedback from review:\n\{feedback}"
            task.status = @types.TaskStatus::Pending
            task.result = None
            task.review = None
            let mut agent_id = ""
            for agent in session.agents {
              if agent.role == Dev {
                agent_id = agent.id
                break
              }
            }
            if not(agent_id.is_empty()) {
              task.assign(agent_id)
              (self.callbacks.on_task_start)(task.id, new_desc, agent_id)
              match self.backends.get(agent_id) {
                Some(b) => {
                  let result = b.run(new_desc, "", fn(event) {
                    match event {
                      @types.AgentEvent::OutputLine(line) =>
                        (self.callbacks.on_agent_output)(agent_id, line)
                      _ => ()
                    }
                  })
                  match result.status {
                    Completed => {
                      task.complete(result.content)
                      (self.callbacks.on_task_complete)(task.id, "done")
                      (self.callbacks.on_agent_complete)(
                        agent_id,
                        result.content,
                      )
                    }
                    Failed(err) => {
                      task.fail(err)
                      (self.callbacks.on_task_complete)(
                        task.id,
                        "failed: \{err}",
                      )
                    }
                    _ => ()
                  }
                }
                None => ()
              }
            }
          }
          _ => ()
        }
      None => ()
    }
  }
}

///| Find a backend for a given role
fn Orchestrator::find_backend_for_role(
  self : Orchestrator,
  role : @types.AgentRole,
) -> (String, @agent.BoxedBackend)? {
  for agent in self.config.agents {
    if agent.role == role {
      match self.backends.get(agent.id) {
        Some(b) => return Some((agent.id, b))
        None => ()
      }
    }
  }
  for entry in self.backends {
    let (id, b) = entry
    return Some((id, b))
  }
  None
}

///| Find the review backend id
fn Orchestrator::find_review_backend_id(self : Orchestrator) -> String? {
  for agent in self.config.agents {
    if agent.role == Review {
      return Some(agent.id)
    }
  }
  None
}

///| Get the task manager
pub fn Orchestrator::get_task_manager(
  self : Orchestrator,
) -> @task.TaskManager {
  self.task_manager
}
