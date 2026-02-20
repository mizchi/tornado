///|
/// Spawn a child process with truly streaming stdout via child_process.spawn.
/// on_stdout receives raw chunks as they arrive from the child process.
/// on_stderr receives stderr chunks.
/// on_close receives the exit code (0 = success).
/// Returns immediately; callbacks fire asynchronously on the Node.js event loop.
pub fn spawn_streaming(
  program : String,
  args_json : String,
  on_stdout : (String) -> Unit,
  on_stderr : (String) -> Unit,
  on_close : (Int) -> Unit,
) -> Unit {
  js_spawn_streaming(program, args_json, on_stdout, on_stderr, on_close)
}

///|
extern "js" fn js_spawn_streaming(
  program : String,
  args_json : String,
  on_stdout : (String) -> Unit,
  on_stderr : (String) -> Unit,
  on_close : (Int) -> Unit,
) -> Unit =
  #|(program, argsJson, onStdout, onStderr, onClose) => {
  #|  const { spawn } = require('child_process');
  #|  const args = JSON.parse(argsJson);
  #|  const child = spawn(program, args, { stdio: ['pipe', 'pipe', 'pipe'] });
  #|  child.stdout.on('data', (chunk) => { onStdout(chunk.toString()); });
  #|  child.stderr.on('data', (chunk) => { onStderr(chunk.toString()); });
  #|  child.on('error', (err) => {
  #|    onStderr('ERROR: ' + (err.message || String(err)));
  #|    onClose(1);
  #|  });
  #|  child.on('close', (code) => { onClose(code || 0); });
  #|}

///|
/// Spawn a child process with JS-side line buffering on stdout.
/// Lines are split at \n boundaries inside the JS event handler,
/// so on_line receives exactly one complete line per call (without trailing newline/CR).
/// Partial lines are buffered across data events and flushed on close.
pub fn spawn_lines_raw(
  program : String,
  args_json : String,
  on_line : (String) -> Unit,
  on_stderr : (String) -> Unit,
  on_close : (Int) -> Unit,
) -> Unit {
  js_spawn_lines_raw(program, args_json, on_line, on_stderr, on_close)
}

///|
extern "js" fn js_spawn_lines_raw(
  program : String,
  args_json : String,
  on_line : (String) -> Unit,
  on_stderr : (String) -> Unit,
  on_close : (Int) -> Unit,
) -> Unit =
  #|(program, argsJson, onLine, onStderr, onClose) => {
  #|  const { spawn } = require('child_process');
  #|  const args = JSON.parse(argsJson);
  #|  const child = spawn(program, args, { stdio: ['pipe', 'pipe', 'pipe'] });
  #|  let buf = '';
  #|  child.stdout.on('data', (chunk) => {
  #|    buf += chunk.toString();
  #|    let nl;
  #|    while ((nl = buf.indexOf('\n')) !== -1) {
  #|      const line = buf.slice(0, nl).replace(/\r$/, '');
  #|      buf = buf.slice(nl + 1);
  #|      onLine(line);
  #|    }
  #|  });
  #|  child.stderr.on('data', (chunk) => { onStderr(chunk.toString()); });
  #|  child.on('error', (err) => {
  #|    onStderr('ERROR: ' + (err.message || String(err)));
  #|    onClose(1);
  #|  });
  #|  child.on('close', (code) => {
  #|    if (buf.length > 0) { onLine(buf.replace(/\r$/, '')); }
  #|    onClose(code || 0);
  #|  });
  #|}
