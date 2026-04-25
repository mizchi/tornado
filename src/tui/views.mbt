///|
/// Render the header bar
pub fn render_header(
  session : @types.Session,
  agent_count : Int,
) -> @vnode.TuiNode {
  @vnode.row(border="single", border_color="rgb(100,100,255)", padding_x=1.0, [
    @vnode.text("tornado", fg="rgb(100,200,255)", bold=true),
    @vnode.text(" | Session: \{session.id}", fg="rgb(200,200,200)"),
    @vnode.text(" | Phase: \{session.current_phase}", fg="rgb(255,200,100)"),
    @vnode.text(" | \{agent_count} agents", fg="rgb(200,200,200)"),
  ])
}

///|
/// Render tab bar for agent selection
pub fn render_tabs(
  agents : Array[@types.AgentConfig],
  active_tab : Int,
) -> @vnode.TuiNode {
  let tabs : Array[@vnode.TuiNode] = []
  for i, agent in agents {
    let is_active = i == active_tab
    let fg = if is_active { "rgb(255,255,255)" } else { "rgb(150,150,150)" }
    let label = if is_active { "[\{agent.id}]" } else { " \{agent.id} " }
    tabs.push(@vnode.text(label, fg~))
  }
  let orchestrator_active = active_tab == agents.length()
  let orchestrator_fg = if orchestrator_active {
    "rgb(255,255,255)"
  } else {
    "rgb(150,150,150)"
  }
  let orchestrator_label = if orchestrator_active {
    "[orchestrator]"
  } else {
    " orchestrator "
  }
  if !(tabs.is_empty()) {
    tabs.push(@vnode.text(" | ", fg="rgb(100,100,100)"))
  }
  tabs.push(@vnode.text(orchestrator_label, fg=orchestrator_fg))
  @vnode.row(padding_x=1.0, gap=1.0, tabs)
}

///|
/// Render agent detail panel
pub fn render_agent_panel(
  agent : @types.AgentConfig,
  logs : Array[String],
  tasks : Array[@types.Task],
) -> @vnode.TuiNode {
  let children : Array[@vnode.TuiNode] = []
  // Agent info
  let kind_str = agent.kind.to_string()
  children.push(
    @vnode.text(
      "Agent: \{agent.id} (\{kind_str}) - Role: \{agent.role}",
      fg="rgb(100,200,100)",
      bold=true,
    ),
  )
  // Tasks for this agent
  for task in tasks {
    match task.status {
      InProgress(aid) =>
        if aid == agent.id {
          children.push(
            @vnode.text("  Task: \{task.description}", fg="rgb(255,200,100)"),
          )
        }
      _ => ()
    }
  }
  // Logs
  children.push(@vnode.text("--- Output ---", fg="rgb(100,100,100)"))
  for line in logs {
    children.push(@vnode.text("  \{line}", fg="rgb(200,200,200)"))
  }
  if logs.is_empty() {
    children.push(@vnode.text("  (no output yet)", fg="rgb(100,100,100)"))
  }
  @vnode.column(
    border="single",
    border_color="rgb(80,80,80)",
    flex_grow=1.0,
    padding=1.0,
    children,
  )
}

///|
/// Render the orchestrator detail panel
fn render_orchestrator_panel(logs : Array[String]) -> @vnode.TuiNode {
  let children : Array[@vnode.TuiNode] = [
    @vnode.text("Orchestrator", fg="rgb(100,200,255)", bold=true),
    @vnode.text("--- Progress ---", fg="rgb(100,100,100)"),
  ]
  for line in logs {
    children.push(@vnode.text("  \{line}", fg="rgb(200,200,200)"))
  }
  if logs.is_empty() {
    children.push(@vnode.text("  (no activity yet)", fg="rgb(100,100,100)"))
  }
  @vnode.column(
    border="single",
    border_color="rgb(80,80,80)",
    flex_grow=1.0,
    padding=1.0,
    children,
  )
}

///|
/// Render the status bar
pub fn render_status_bar(session : @types.Session) -> @vnode.TuiNode {
  let total = session.tasks.length()
  let done = session.tasks.iter().filter(fn(t) { t.is_done() }).count()
  let status_text = "Tasks: \{done}/\{total} | Status: \{session.status}"
  @vnode.row(border="single", border_color="rgb(80,80,80)", padding_x=1.0, [
    @vnode.text(status_text, fg="rgb(200,200,200)"),
  ])
}

///|
/// Render the full TUI view
pub fn render_app(state : TuiState) -> @vnode.TuiNode {
  match state.active_session() {
    Some(session) => {
      let children : Array[@vnode.TuiNode] = []
      // Header
      children.push(render_header(session, session.agents.length()))
      // Tabs
      children.push(render_tabs(session.agents, state.active_tab))
      // Agent or orchestrator panel
      if state.active_tab < session.agents.length() {
        let agent = session.agents[state.active_tab]
        let logs = state.get_logs(agent.id)
        children.push(render_agent_panel(agent, logs, session.tasks))
      } else {
        children.push(render_orchestrator_panel(state.phase_log))
      }
      // Status bar
      children.push(render_status_bar(session))
      @vnode.column(flex_grow=1.0, children)
    }
    None =>
      @vnode.column([@vnode.text("No active session", fg="rgb(200,100,100)")])
  }
}
