///| Create a BoxedBackend from AgentConfig
pub fn create_backend(config : @types.AgentConfig) -> BoxedBackend {
  match config.kind {
    ClaudeCode => {
      let model = config.model.unwrap_or("")
      SubprocessBackend::new(ClaudeCode, model~).boxed()
    }
    Codex => {
      let model = config.model.unwrap_or("")
      SubprocessBackend::new(Codex, model~).boxed()
    }
    Api => {
      // API backend needs env var for key
      let api_key = @ffi.get_env("ANTHROPIC_API_KEY")
      let model = config.model.unwrap_or(@llm.default_anthropic_model)
      ApiBackend::anthropic(api_key, model~).boxed()
    }
    Mock => MockBackend::new().boxed()
  }
}

///| Create backends map from agent configs
pub fn create_backends(
  agents : Array[@types.AgentConfig],
) -> Map[String, BoxedBackend] {
  let backends : Map[String, BoxedBackend] = {}
  for agent in agents {
    backends[agent.id] = create_backend(agent)
  }
  backends
}
