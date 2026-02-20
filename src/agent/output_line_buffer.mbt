///|
/// OutputLineBuffer accumulates text chunks and emits complete lines.
/// This keeps AgentEvent::OutputLine aligned to logical lines instead of raw token chunks.
pub struct OutputLineBuffer {
  buf : StringBuilder
}

///|
pub fn OutputLineBuffer::new() -> OutputLineBuffer {
  { buf: StringBuilder::new() }
}

///|
/// Push a text chunk and emit complete lines (newline-terminated).
/// Newline characters are not included in emitted lines.
pub fn OutputLineBuffer::push(
  self : OutputLineBuffer,
  chunk : String,
  on_line : (String) -> Unit,
) -> Unit {
  self.buf.write_string(chunk)
  let content = self.buf.to_string()
  let mut last_nl = -1
  for i in 0..<content.length() {
    if content[i] == '\n'.to_int().to_uint16() {
      last_nl = i
    }
  }
  if last_nl < 0 {
    return
  }
  let complete = content.unsafe_substring(start=0, end=last_nl)
  let remainder = if last_nl + 1 < content.length() {
    content.unsafe_substring(start=last_nl + 1, end=content.length())
  } else {
    ""
  }
  self.buf.reset()
  self.buf.write_string(remainder)
  for line in complete.split("\n") {
    let s = line.to_string()
    let stripped = if s.has_suffix("\r") {
      s.unsafe_substring(start=0, end=s.length() - 1)
    } else {
      s
    }
    on_line(stripped)
  }
}

///|
/// Flush remaining partial text as the final line.
pub fn OutputLineBuffer::flush(
  self : OutputLineBuffer,
  on_line : (String) -> Unit,
) -> Unit {
  let remaining = self.buf.to_string()
  if not(remaining.is_empty()) {
    let stripped = if remaining.has_suffix("\r") {
      remaining.unsafe_substring(start=0, end=remaining.length() - 1)
    } else {
      remaining
    }
    on_line(stripped)
    self.buf.reset()
  }
}
