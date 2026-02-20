test "TaskManager::new starts empty" {
  let tm = @task.TaskManager::new()
  assert_true(tm.total() == 0)
  assert_true(tm.all_done())
}

test "TaskManager::add_task generates ids" {
  let tm = @task.TaskManager::new()
  let t1 = tm.add_task("task one")
  let t2 = tm.add_task("task two")
  inspect(t1.id, content="task-1")
  inspect(t2.id, content="task-2")
  assert_true(tm.total() == 2)
}

test "TaskManager::get_task finds by id" {
  let tm = @task.TaskManager::new()
  ignore(tm.add_task("task one"))
  let found = tm.get_task("task-1")
  assert_true(found is Some(_))
  inspect(found.unwrap().description, content="task one")
  let missing = tm.get_task("nonexistent")
  assert_true(missing is None)
}

test "TaskManager::get_pending returns pending tasks" {
  let tm = @task.TaskManager::new()
  let t1 = tm.add_task("task one")
  ignore(tm.add_task("task two"))
  t1.assign("agent-1")
  let pending = tm.get_pending()
  assert_true(pending.length() == 1)
  inspect(pending[0].id, content="task-2")
}

test "TaskManager::assign_next assigns first pending" {
  let tm = @task.TaskManager::new()
  ignore(tm.add_task("task one"))
  ignore(tm.add_task("task two"))
  let assigned = tm.assign_next("agent-1")
  assert_true(assigned is Some(_))
  inspect(assigned.unwrap().id, content="task-1")
  inspect(assigned.unwrap().status, content="InProgress(\"agent-1\")")
}

test "TaskManager::completed_count" {
  let tm = @task.TaskManager::new()
  let t1 = tm.add_task("task one")
  let t2 = tm.add_task("task two")
  assert_true(tm.completed_count() == 0)
  t1.complete("done")
  assert_true(tm.completed_count() == 1)
  t2.complete("also done")
  assert_true(tm.completed_count() == 2)
  assert_true(tm.all_done())
}

test "TaskManager::parse_tasks numbered list" {
  let tm = @task.TaskManager::new()
  let output = "1. Create database schema\n2. Implement API handlers\n3. Write tests"
  let tasks = tm.parse_tasks(output)
  assert_true(tasks.length() == 3)
  inspect(tasks[0].description, content="Create database schema")
  inspect(tasks[1].description, content="Implement API handlers")
  inspect(tasks[2].description, content="Write tests")
}

test "TaskManager::parse_tasks bullet list" {
  let tm = @task.TaskManager::new()
  let output = "- Setup project\n- Add dependencies\n- Configure CI"
  let tasks = tm.parse_tasks(output)
  assert_true(tasks.length() == 3)
  inspect(tasks[0].description, content="Setup project")
}

test "TaskManager::parse_tasks skips empty lines" {
  let tm = @task.TaskManager::new()
  let output = "task one\n\ntask two\n  \n"
  let tasks = tm.parse_tasks(output)
  assert_true(tasks.length() == 2)
}

test "TaskManager::parse_tasks with parent_id" {
  let tm = @task.TaskManager::new()
  let tasks = tm.parse_tasks("sub-task", parent_id=Some("parent-1"))
  assert_true(tasks.length() == 1)
  inspect(tasks[0].parent_id, content="Some(\"parent-1\")")
}
