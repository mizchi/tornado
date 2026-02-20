///|
/// LineBuffer accumulates streaming chunks and emits complete lines.
/// Handles partial lines across chunk boundaries.
pub struct LineBuffer {
  buf : StringBuilder
}

///|
pub fn LineBuffer::new() -> LineBuffer {
  { buf: StringBuilder::new() }
}

///|
/// Push a chunk of data. Emits each complete line (terminated by \n) via on_line.
/// Partial lines are buffered until the next push or flush.
pub fn LineBuffer::push(
  self : LineBuffer,
  chunk : String,
  on_line : (String) -> Unit,
) -> Unit {
  self.buf.write_string(chunk)
  let content = self.buf.to_string()
  // Find last newline position
  let mut last_nl = -1
  for i in 0..<content.length() {
    if content[i] == '\n'.to_int().to_uint16() {
      last_nl = i
    }
  }
  if last_nl < 0 {
    // No complete line yet
    return
  }
  // Extract complete lines portion and remainder
  let complete = content.unsafe_substring(start=0, end=last_nl)
  let remainder = if last_nl + 1 < content.length() {
    content.unsafe_substring(start=last_nl + 1, end=content.length())
  } else {
    ""
  }
  // Reset buffer with remainder
  self.buf.reset()
  self.buf.write_string(remainder)
  // Emit lines
  for line in complete.split("\n") {
    let s = line.to_string()
    // Strip trailing \r for CRLF support
    let stripped = if s.has_suffix("\r") {
      s.unsafe_substring(start=0, end=s.length() - 1)
    } else {
      s
    }
    on_line(stripped)
  }
}

///|
/// Flush remaining buffered content as a final line.
pub fn LineBuffer::flush(
  self : LineBuffer,
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
