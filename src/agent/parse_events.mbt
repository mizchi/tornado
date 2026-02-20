///| Parse tool_use blocks from an assistant message JSON object
pub fn parse_tool_calls(
  map : Map[String, Json],
  on_output : (@types.AgentEvent) -> Unit,
) -> Unit {
  let message = match map.get("message") {
    Some(Object(m)) => m
    _ => return
  }
  let content = match message.get("content") {
    Some(Array(arr)) => arr
    _ => return
  }
  for block in content {
    match block {
      Object(b) =>
        match b.get("type") {
          Some(String(block_type)) =>
            if block_type == "tool_use" {
              let tool_name = match b.get("name") {
                Some(String(n)) => n
                _ => "unknown"
              }
              let tool_input = match b.get("input") {
                Some(input) => input
                _ => Json::null()
              }
              let input_str = tool_input.stringify()
              on_output(
                @types.AgentEvent::ToolCall(name=tool_name, input=input_str),
              )
              // Detect subagent launches (Task tool)
              if tool_name == "Task" {
                let agent_type = match tool_input {
                  Object(m) =>
                    match m.get("subagent_type") {
                      Some(String(t)) => t
                      _ => "unknown"
                    }
                  _ => "unknown"
                }
                let task_desc = match tool_input {
                  Object(m) =>
                    match m.get("description") {
                      Some(String(d)) => d
                      _ => ""
                    }
                  _ => ""
                }
                on_output(
                  @types.AgentEvent::SubAgentStart(
                    agent_type=agent_type,
                    task=task_desc,
                  ),
                )
              }
            }
          _ => ()
        }
      _ => ()
    }
  }
}

///| Parse tool_result events from a JSON object
pub fn parse_tool_result(
  map : Map[String, Json],
  on_output : (@types.AgentEvent) -> Unit,
) -> Unit {
  let tool_name = match map.get("tool_name") {
    Some(String(n)) => n
    _ =>
      match map.get("name") {
        Some(String(n)) => n
        _ => "unknown"
      }
  }
  let output = match map.get("content") {
    Some(String(s)) => s
    Some(other) => other.stringify()
    _ => ""
  }
  on_output(@types.AgentEvent::ToolResult(name=tool_name, output=output))
  // Detect subagent completion
  if tool_name == "Task" {
    on_output(@types.AgentEvent::SubAgentEnd(agent_type="Task"))
  }
}

///| Parse system init event (model, tools, session)
pub fn parse_system_event(
  map : Map[String, Json],
  on_output : (@types.AgentEvent) -> Unit,
) -> Unit {
  let subtype = match map.get("subtype") {
    Some(String(s)) => s
    _ => ""
  }
  if subtype == "init" {
    let model = match map.get("model") {
      Some(String(m)) => m
      _ => "unknown"
    }
    let tools_count = match map.get("tools") {
      Some(Array(arr)) => arr.length()
      _ => 0
    }
    on_output(
      @types.AgentEvent::Info(
        "Session initialized: model=\{model}, tools=\{tools_count}",
      ),
    )
  }
}

///| Parse content_block_start (tool_use start, text start, thinking)
pub fn parse_content_block_start(
  map : Map[String, Json],
  on_output : (@types.AgentEvent) -> Unit,
) -> Unit {
  let block = match map.get("content_block") {
    Some(Object(b)) => b
    _ => return
  }
  match block.get("type") {
    Some(String(block_type)) =>
      match block_type {
        "tool_use" => {
          let name = match block.get("name") {
            Some(String(n)) => n
            _ => "unknown"
          }
          on_output(@types.AgentEvent::Info("Using tool: \{name}"))
        }
        "thinking" => on_output(@types.AgentEvent::Info("Thinking..."))
        "text" =>
          on_output(@types.AgentEvent::Info("Generating response..."))
        _ => ()
      }
    _ => ()
  }
}

///| Parse result event (cost, duration, token usage)
pub fn parse_result_event(
  map : Map[String, Json],
  on_output : (@types.AgentEvent) -> Unit,
) -> Unit {
  let subtype = match map.get("subtype") {
    Some(String(s)) => s
    _ => ""
  }
  let buf = StringBuilder::new()
  buf.write_string("Result: \{subtype}")
  match map.get("cost_usd") {
    Some(Number(n, ..)) => buf.write_string(", cost=$\{n}")
    _ => ()
  }
  match map.get("duration_ms") {
    Some(Number(n, ..)) => {
      let secs = n / 1000.0
      buf.write_string(", duration=\{secs}s")
    }
    _ => ()
  }
  match map.get("duration_api_ms") {
    Some(Number(n, ..)) => {
      let secs = n / 1000.0
      buf.write_string(", api=\{secs}s")
    }
    _ => ()
  }
  match map.get("usage") {
    Some(Object(usage)) => {
      let input_tokens = match usage.get("input_tokens") {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
      let output_tokens = match usage.get("output_tokens") {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
      if input_tokens > 0 || output_tokens > 0 {
        buf.write_string(", tokens=\{input_tokens}in/\{output_tokens}out")
      }
    }
    _ => ()
  }
  on_output(@types.AgentEvent::Info(buf.to_string()))
}
