test "MockBackend with default response" {
  let mock = @agent.MockBackend::new()
  let backend = mock.boxed()
  let events : Array[String] = []
  let result = backend.run("do something", "", fn(event) {
    match event {
      @types.AgentEvent::OutputLine(s) => events.push(s)
      _ => ()
    }
  })
  inspect(result.content, content="mock response")
  inspect(result.status, content="Completed")
  inspect(result.error, content="None")
  assert_true(events.length() == 1)
  inspect(events[0], content="mock response")
}

test "MockBackend with custom responses" {
  let mock = @agent.MockBackend::new()
  mock.add_response("build", "building complete")
  mock.add_response("test", "tests passed")
  let backend = mock.boxed()
  let result1 = backend.run("build api", "", fn(_) {  })
  inspect(result1.content, content="building complete")
  let result2 = backend.run("test suite", "", fn(_) {  })
  inspect(result2.content, content="tests passed")
}

test "MockBackend falls back to default" {
  let mock = @agent.MockBackend::new(default_response="fallback")
  let backend = mock.boxed()
  let result = backend.run("unknown task", "", fn(_) {  })
  inspect(result.content, content="fallback")
}

test "MockBackend tracks call history" {
  let mock = @agent.MockBackend::new()
  let backend = mock.boxed()
  ignore(backend.run("task1", "prompt1", fn(_) {  }))
  ignore(backend.run("task2", "prompt2", fn(_) {  }))
  let history = mock.get_history()
  assert_true(history.length() == 2)
  let (t1, p1) = history[0]
  inspect(t1, content="task1")
  inspect(p1, content="prompt1")
  let (t2, p2) = history[1]
  inspect(t2, content="task2")
  inspect(p2, content="prompt2")
}

test "MockBackend emits status events" {
  let mock = @agent.MockBackend::new()
  let backend = mock.boxed()
  let statuses : Array[String] = []
  ignore(
    backend.run("task", "", fn(event) {
      match event {
        @types.AgentEvent::StatusChange(s) => statuses.push(s.to_string())
        _ => ()
      }
    }),
  )
  assert_true(statuses.length() == 2)
  inspect(statuses[0], content="Running")
  inspect(statuses[1], content="Completed")
}

test "FailingMockBackend returns failure" {
  let mock = @agent.FailingMockBackend::new(error_msg="oops")
  let backend = mock.boxed()
  let result = backend.run("task", "", fn(_) {  })
  inspect(result.content, content="")
  inspect(result.status, content="Failed(\"oops\")")
  inspect(result.error, content="Some(\"oops\")")
}

test "FailingMockBackend emits failure events" {
  let mock = @agent.FailingMockBackend::new()
  let backend = mock.boxed()
  let statuses : Array[String] = []
  ignore(
    backend.run("task", "", fn(event) {
      match event {
        @types.AgentEvent::StatusChange(s) => statuses.push(s.to_string())
        _ => ()
      }
    }),
  )
  assert_true(statuses.length() == 2)
  inspect(statuses[0], content="Running")
  inspect(statuses[1], content="Failed(\"mock error\")")
}

test "BoxedBackend wraps MockBackend" {
  let mock = @agent.MockBackend::new(default_response="boxed result")
  let boxed = mock.boxed()
  inspect(boxed.name(), content="mock")
  let result = boxed.run("task", "", fn(_) {  })
  inspect(result.content, content="boxed result")
}

test "BoxedBackend wraps FailingMockBackend" {
  let mock = @agent.FailingMockBackend::new(error_msg="boxed error")
  let boxed = mock.boxed()
  inspect(boxed.name(), content="failing-mock")
  let result = boxed.run("task", "", fn(_) {  })
  inspect(result.status, content="Failed(\"boxed error\")")
}

test "SubprocessBackend name via boxed" {
  let cc = @agent.SubprocessBackend::new(@types.AgentKind::ClaudeCode)
  let boxed = cc.boxed()
  inspect(boxed.name(), content="claude-code")
  let codex = @agent.SubprocessBackend::new(@types.AgentKind::Codex)
  let boxed2 = codex.boxed()
  inspect(boxed2.name(), content="codex")
}

test "MockBackend name via boxed" {
  let mock = @agent.MockBackend::new()
  let boxed = mock.boxed()
  inspect(boxed.name(), content="mock")
}
