///| TaskManager handles task lifecycle and assignment
pub struct TaskManager {
  tasks : Array[@types.Task]
  mut next_id : Int
}

///| Create a new TaskManager
pub fn TaskManager::new() -> TaskManager {
  { tasks: [], next_id: 1 }
}

///| Add a task to the manager
pub fn TaskManager::add_task(
  self : TaskManager,
  description : String,
  parent_id? : String? = None,
) -> @types.Task {
  let id = "task-\{self.next_id}"
  self.next_id += 1
  let task = @types.Task::new(id, description, parent_id~)
  self.tasks.push(task)
  task
}

///| Get a task by id
pub fn TaskManager::get_task(self : TaskManager, id : String) -> @types.Task? {
  for task in self.tasks {
    if task.id == id {
      return Some(task)
    }
  }
  None
}

///| Get all pending tasks
pub fn TaskManager::get_pending(self : TaskManager) -> Array[@types.Task] {
  self.tasks.filter(fn(t) { t.is_pending() })
}

///| Get all completed tasks
pub fn TaskManager::get_completed(self : TaskManager) -> Array[@types.Task] {
  self.tasks.filter(fn(t) { t.is_done() })
}

///| Assign the next pending task to an agent
pub fn TaskManager::assign_next(
  self : TaskManager,
  agent_id : String,
) -> @types.Task? {
  for task in self.tasks {
    if task.is_pending() {
      task.assign(agent_id)
      return Some(task)
    }
  }
  None
}

///| Get total task count
pub fn TaskManager::total(self : TaskManager) -> Int {
  self.tasks.length()
}

///| Get completed task count
pub fn TaskManager::completed_count(self : TaskManager) -> Int {
  self.tasks.iter().filter(fn(t) { t.is_done() }).count()
}

///| Check if all tasks are done
pub fn TaskManager::all_done(self : TaskManager) -> Bool {
  self.tasks.iter().all(fn(t) { t.is_done() })
}

///| Parse task descriptions from LLM output
/// Expects format: one task per line, possibly numbered
pub fn TaskManager::parse_tasks(
  self : TaskManager,
  output : String,
  parent_id? : String? = None,
) -> Array[@types.Task] {
  let result : Array[@types.Task] = []
  let lines = output.split("\n")
  for line in lines {
    let trimmed = line.to_string().trim().to_string()
    if trimmed.is_empty() {
      continue
    }
    // Strip leading numbering like "1. " or "- "
    let desc = strip_prefix(trimmed)
    if not(desc.is_empty()) {
      result.push(self.add_task(desc, parent_id~))
    }
  }
  result
}

///| Strip leading numbering from a line
fn strip_prefix(s : String) -> String {
  let chars = s.to_array()
  let len = chars.length()
  if len == 0 {
    return s
  }
  let mut i = 0
  // Skip leading digits
  while i < len && chars[i] >= '0' && chars[i] <= '9' {
    i += 1
  }
  // Skip ". " or ") " after digits
  if i > 0 && i < len && (chars[i] == '.' || chars[i] == ')') {
    i += 1
    if i < len && chars[i] == ' ' {
      i += 1
    }
    return s.view(start_offset=i).to_string().trim().to_string()
  }
  // Skip "- " prefix
  if chars[0] == '-' || chars[0] == '*' {
    return s.view(start_offset=1).to_string().trim().to_string()
  }
  s
}
