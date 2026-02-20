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
      review_interval=ri,
      rlm=rlm,
      warnings=warnings,
    ) => {
      inspect(config, content="None")
      inspect(plan, content="None")
      inspect(dev, content="Some(Codex)")
      inspect(review, content="Some(ClaudeCode)")
      inspect(ri, content="None")
      inspect(rlm, content="false")
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
      review_kind=_review,
      review_interval=_ri,
      rlm=_rlm,
      warnings=warnings,
    ) => {
      inspect(config, content="None")
      inspect(plan, content="Some(\"plan.md\")")
      inspect(dev, content="Some(Codex)")
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
      review_interval=_ri,
      rlm=_rlm,
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
      review_interval=_ri,
      rlm=_rlm,
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
      review_interval=_ri,
      rlm=_rlm,
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

test "parse_cli_args --review-interval=3" {
  let args = ["tornado", "--review-interval=3", "--dev=codex"]
  let parsed = @cli.parse_cli_args(args, file_exists_mock)
  match parsed {
    Run(
      config_path=_config,
      plan_path=_plan,
      dev_kind=dev,
      review_kind=_review,
      review_interval=ri,
      rlm=rlm,
      warnings=warnings,
    ) => {
      inspect(dev, content="Some(Codex)")
      inspect(ri, content="Some(3)")
      inspect(rlm, content="false")
      assert_true(warnings.is_empty())
    }
    _ => panic()
  }
}

test "parse_cli_args --rlm flag" {
  let args = ["tornado", "--rlm", "plan.md"]
  let parsed = @cli.parse_cli_args(args, file_exists_mock)
  match parsed {
    Run(
      config_path=_config,
      plan_path=plan,
      dev_kind=_dev,
      review_kind=_review,
      review_interval=_ri,
      rlm=rlm,
      warnings=warnings,
    ) => {
      inspect(plan, content="Some(\"plan.md\")")
      inspect(rlm, content="true")
      assert_true(warnings.is_empty())
    }
    _ => panic()
  }
}

test "parse_cli_args --review-interval invalid warns" {
  let args = ["tornado", "--review-interval=abc"]
  let parsed = @cli.parse_cli_args(args, file_exists_mock)
  match parsed {
    Run(
      config_path=_config,
      plan_path=_plan,
      dev_kind=_dev,
      review_kind=_review,
      review_interval=ri,
      rlm=_rlm,
      warnings=warnings,
    ) => {
      inspect(ri, content="None")
      assert_true(warnings.length() == 1)
      assert_true(warnings[0].contains("Invalid --review-interval"))
    }
    _ => panic()
  }
}

test "parse_cli_args --review-interval=0 warns" {
  let args = ["tornado", "--review-interval=0"]
  let parsed = @cli.parse_cli_args(args, file_exists_mock)
  match parsed {
    Run(
      config_path=_config,
      plan_path=_plan,
      dev_kind=_dev,
      review_kind=_review,
      review_interval=ri,
      rlm=_rlm,
      warnings=warnings,
    ) => {
      inspect(ri, content="None")
      assert_true(warnings.length() == 1)
      assert_true(warnings[0].contains("Invalid --review-interval"))
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

test "apply_overrides overrides review_interval" {
  let base = @config.ProjectConfig::preset_default()
  inspect(base.review_interval, content="1")
  let updated = @cli.apply_overrides(base, review_interval=Some(3))
  inspect(updated.review_interval, content="3")
}

test "apply_overrides keeps review_interval when not overridden" {
  let base = @config.ProjectConfig::preset_default()
  let updated = @cli.apply_overrides(base)
  inspect(updated.review_interval, content="1")
}
