pub(all) enum CliCommand {
  Run(
    config_path~ : String?,
    plan_path~ : String?,
    dev_kind~ : @types.AgentKind?,
    review_kind~ : @types.AgentKind?,
    warnings~ : Array[String],
  )
  Validate(String?)
  Help
}

///| Parse top-level CLI args.
///| file_exists is injected for testability.
pub fn parse_cli_args(
  args : Array[String],
  file_exists : (String) -> Bool,
) -> CliCommand {
  if args.length() < 2 {
    return Run(
      config_path=None,
      plan_path=None,
      dev_kind=None,
      review_kind=None,
      warnings=[],
    )
  }

  let first = args[1]
  match first {
    "help" | "--help" | "-h" => Help
    "validate" => {
      if args.length() >= 3 {
        Validate(Some(args[2]))
      } else {
        Validate(None)
      }
    }
    _ => parse_run_args(drop_prefix(args, 1), file_exists)
  }
}

///| Apply --dev/--review kind overrides to config agents by role.
pub fn apply_kind_overrides(
  config : @config.ProjectConfig,
  dev_kind? : @types.AgentKind? = None,
  review_kind? : @types.AgentKind? = None,
) -> @config.ProjectConfig {
  let agents : Array[@types.AgentConfig] = []
  for agent in config.agents {
    let kind = match agent.role {
      Dev => match dev_kind {
        Some(k) => k
        None => agent.kind
      }
      Review => match review_kind {
        Some(k) => k
        None => agent.kind
      }
      _ => agent.kind
    }
    agents.push(
      {
        id: agent.id,
        kind,
        role: agent.role,
        model: agent.model,
        system_prompt: agent.system_prompt,
        working_dir: agent.working_dir,
        max_iterations: agent.max_iterations,
      },
    )
  }
  {
    project_dir: config.project_dir,
    review_dir: config.review_dir,
    max_review_cycles: config.max_review_cycles,
    agents,
    parse_warnings: config.parse_warnings,
  }
}

///| Human-readable kind label for logs/usage.
pub fn kind_name(kind : @types.AgentKind) -> String {
  match kind {
    ClaudeCode => "claude-code"
    Codex => "codex"
    Api => "api"
    Mock => "mock"
  }
}

fn parse_run_args(
  args : Array[String],
  file_exists : (String) -> Bool,
) -> CliCommand {
  let mut config_path : String? = None
  let mut plan_path : String? = None
  let mut dev_kind : @types.AgentKind? = None
  let mut review_kind : @types.AgentKind? = None
  let warnings : Array[String] = []

  let mut i = 0
  let len = args.length()
  while i < len {
    let token = args[i]
    if token.has_prefix("--dev=") {
      let raw = token.view(start_offset="--dev=".length()).to_string()
      match parse_kind_alias(raw) {
        Some(kind) => dev_kind = Some(kind)
        None => warnings.push("Unknown --dev kind: \{raw}")
      }
      i += 1
      continue
    }

    if token.has_prefix("--review=") {
      let raw = token.view(start_offset="--review=".length()).to_string()
      match parse_kind_alias(raw) {
        Some(kind) => review_kind = Some(kind)
        None => warnings.push("Unknown --review kind: \{raw}")
      }
      i += 1
      continue
    }

    if token.has_prefix("--config=") {
      let path = token.view(start_offset="--config=".length()).to_string()
      if path.is_empty() {
        warnings.push("Missing value for --config")
      } else {
        config_path = Some(path)
      }
      i += 1
      continue
    }

    if token == "--config" {
      if i + 1 < len {
        let path = args[i + 1]
        if path.has_prefix("--") {
          warnings.push("Missing value for --config")
          i += 1
        } else {
          config_path = Some(path)
          i += 2
        }
      } else {
        warnings.push("Missing value for --config")
        i += 1
      }
      continue
    }

    if token.has_prefix("--") {
      warnings.push("Unknown option: \{token}")
      i += 1
      continue
    }

    // First positional file is treated as plan path.
    if plan_path is None {
      if file_exists(token) {
        plan_path = Some(token)
      } else {
        warnings.push(
          "Positional argument must be an existing plan file: \{token} (use --config=<path> for config)",
        )
      }
    } else {
      warnings.push("Unexpected argument: \{token}")
    }
    i += 1
  }

  Run(config_path~, plan_path~, dev_kind~, review_kind~, warnings~)
}

fn parse_kind_alias(raw : String) -> @types.AgentKind? {
  match raw {
    "claude" | "claude-code" | "claudecode" => Some(ClaudeCode)
    "codex" => Some(Codex)
    "api" => Some(Api)
    "mock" => Some(Mock)
    _ => None
  }
}

fn drop_prefix(args : Array[String], start : Int) -> Array[String] {
  let result : Array[String] = []
  let len = args.length()
  let mut i = start
  while i < len {
    result.push(args[i])
    i += 1
  }
  result
}
