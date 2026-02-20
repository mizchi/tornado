fn file_exists_mock(path : String) -> Bool {
  path == "plan.md" || path == "tasks.txt"
}

test "parse_cli_args flags only" {
  let args = ["tornado", "--dev=codex", "--review=claude"]
  let parsed = @cli.parse_cli_args(args, file_exists_mock)
  match parsed {
    Run(
      config_path=config,
      plan_path=plan,
      dev_kind=dev,
      review_kind=review,
      warnings=warnings,
    ) => {
      inspect(config, content="None")
      inspect(plan, content="None")
      inspect(dev, content="Some(Codex)")
      inspect(review, content="Some(ClaudeCode)")
      assert_true(warnings.is_empty())
    }
    _ => panic()
  }
}

test "parse_cli_args first positional file is plan" {
  let args = ["tornado", "plan.md", "--dev=codex"]
  let parsed = @cli.parse_cli_args(args, file_exists_mock)
  match parsed {
    Run(
      config_path=config,
      plan_path=plan,
      dev_kind=dev,
      review_kind=review,
      warnings=warnings,
    ) => {
      inspect(config, content="None")
      inspect(plan, content="Some(\"plan.md\")")
      inspect(dev, content="Some(Codex)")
      inspect(review, content="None")
      assert_true(warnings.is_empty())
    }
    _ => panic()
  }
}

test "parse_cli_args supports --config=value" {
  let args = ["tornado", "--config=config.json", "--review=codex"]
  let parsed = @cli.parse_cli_args(args, file_exists_mock)
  match parsed {
    Run(
      config_path=config,
      plan_path=plan,
      dev_kind=dev,
      review_kind=review,
      warnings=warnings,
    ) => {
      inspect(config, content="Some(\"config.json\")")
      inspect(plan, content="None")
      inspect(dev, content="None")
      inspect(review, content="Some(Codex)")
      assert_true(warnings.is_empty())
    }
    _ => panic()
  }
}

test "parse_cli_args supports --config <value>" {
  let args = ["tornado", "--config", "config.json", "--review=codex"]
  let parsed = @cli.parse_cli_args(args, file_exists_mock)
  match parsed {
    Run(
      config_path=config,
      plan_path=plan,
      dev_kind=dev,
      review_kind=review,
      warnings=warnings,
    ) => {
      inspect(config, content="Some(\"config.json\")")
      inspect(plan, content="None")
      inspect(dev, content="None")
      inspect(review, content="Some(Codex)")
      assert_true(warnings.is_empty())
    }
    _ => panic()
  }
}

test "parse_cli_args validate command" {
  let args = ["tornado", "validate", "config.json"]
  let parsed = @cli.parse_cli_args(args, file_exists_mock)
  match parsed {
    Validate(path) => inspect(path, content="Some(\"config.json\")")
    _ => panic()
  }
}

test "parse_cli_args warns on non-file positional argument" {
  let args = ["tornado", "config.json"]
  let parsed = @cli.parse_cli_args(args, file_exists_mock)
  match parsed {
    Run(
      config_path=config,
      plan_path=plan,
      dev_kind=_dev,
      review_kind=_review,
      warnings=warnings,
    ) => {
      inspect(config, content="None")
      inspect(plan, content="None")
      assert_true(warnings.length() == 1)
      assert_true(warnings[0].contains("use --config"))
    }
    _ => panic()
  }
}

test "apply_kind_overrides rewrites role kinds" {
  let base = @config.ProjectConfig::preset_default()
  let updated = @cli.apply_kind_overrides(
    base,
    dev_kind=Some(@types.AgentKind::Codex),
    review_kind=Some(@types.AgentKind::ClaudeCode),
  )

  assert_true(updated.agents.length() == 2)
  inspect(updated.agents[0].role, content="Dev")
  inspect(updated.agents[0].kind, content="Codex")
  inspect(updated.agents[1].role, content="Review")
  inspect(updated.agents[1].kind, content="ClaudeCode")
}
