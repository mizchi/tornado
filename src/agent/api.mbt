///| ApiBackend uses LLM API providers (Anthropic, OpenAI)
pub struct ApiBackend {
  provider : @llm.BoxedProvider
}

///| Create an ApiBackend with an Anthropic provider
pub fn ApiBackend::anthropic(
  api_key : String,
  model? : String = @llm.default_anthropic_model,
) -> ApiBackend {
  let provider = @anthropic.AnthropicProvider::new(api_key, model~)
  { provider: @llm.BoxedProvider::new(provider) }
}

///| Create an ApiBackend with an OpenAI provider
pub fn ApiBackend::openai(
  api_key : String,
  model? : String = @llm.default_openai_model,
) -> ApiBackend {
  let provider = @openai.OpenAIProvider::new(api_key, model~)
  { provider: @llm.BoxedProvider::new(provider) }
}

///| Create an ApiBackend from a BoxedProvider
pub fn ApiBackend::from_provider(provider : @llm.BoxedProvider) -> ApiBackend {
  { provider }
}

///| AgentBackend implementation for ApiBackend
impl AgentBackend for ApiBackend with run(self, task, system_prompt, on_output) {
  on_output(@types.AgentEvent::StatusChange(@types.AgentStatus::Running))
  let messages : Array[@llm.Message] = []
  if not(system_prompt.is_empty()) {
    messages.push(
      { role: System, content: [@llm.ContentBlock::Text(system_prompt)] },
    )
  }
  messages.push(
    { role: User, content: [@llm.ContentBlock::Text(task)] },
  )
  let buf = StringBuilder::new()
  let handler : @llm.StreamHandler = {
    on_event: fn(event) {
      match event {
        TextDelta(s) => {
          buf.write_string(s)
          on_output(@types.AgentEvent::OutputLine(s))
        }
        Error(msg) =>
          on_output(
            @types.AgentEvent::StatusChange(@types.AgentStatus::Failed(msg)),
          )
        _ => ()
      }
    },
  }
  self.provider.stream(messages, [], handler)
  let content = buf.to_string()
  on_output(@types.AgentEvent::StatusChange(@types.AgentStatus::Completed))
  { content, status: Completed, error: None }
}

///| AgentBackend implementation for ApiBackend
impl AgentBackend for ApiBackend with name(_self) {
  "api"
}

///|
impl AgentBackend for ApiBackend with set_session_id(_self, _sid) {  }

///|
impl AgentBackend for ApiBackend with get_session_id(_self) {
  ""
}

///| Wrap in BoxedBackend for dynamic dispatch
pub fn ApiBackend::boxed(self : ApiBackend) -> BoxedBackend {
  BoxedBackend::new(self)
}
