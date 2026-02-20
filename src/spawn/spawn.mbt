///|
/// Spawn a child process and stream stdout line-by-line.
/// Lines are delivered incrementally as stdout chunks arrive.
/// Partial lines are buffered until a newline is received or the process exits.
///
/// - on_line: called for each complete line from stdout
/// - on_error: called with stderr content or spawn errors
/// - on_done: called with exit code when the process exits
pub fn spawn_lines(
  program : String,
  args : Array[String],
  on_line : (String) -> Unit,
  on_error : (String) -> Unit,
  on_done : (Int) -> Unit,
) -> Unit {
  let args_json = Json::array(args.map(fn(s) { s.to_json() })).stringify()
  let lb = LineBuffer::new()
  spawn_streaming(
    program,
    args_json,
    fn(chunk) { lb.push(chunk, on_line) },
    on_error,
    fn(code) {
      lb.flush(on_line)
      on_done(code)
    },
  )
}
