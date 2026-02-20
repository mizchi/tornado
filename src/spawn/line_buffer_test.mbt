test "push: single complete line" {
  let lb = LineBuffer::new()
  let lines : Array[String] = []
  lb.push("hello\n", fn(line) { lines.push(line) })
  inspect(lines, content=(
    #|["hello"]
  ))
}

test "push: multiple complete lines in one chunk" {
  let lb = LineBuffer::new()
  let lines : Array[String] = []
  lb.push("hello\nworld\n", fn(line) { lines.push(line) })
  inspect(lines, content=(
    #|["hello", "world"]
  ))
}

test "push: no newline - nothing emitted" {
  let lb = LineBuffer::new()
  let lines : Array[String] = []
  lb.push("hello", fn(line) { lines.push(line) })
  inspect(lines, content=(
    #|[]
  ))
}

test "push: partial then complete across chunks" {
  let lb = LineBuffer::new()
  let lines : Array[String] = []
  let on_line = fn(line : String) { lines.push(line) }
  lb.push("hel", on_line)
  inspect(lines, content=(
    #|[]
  ))
  lb.push("lo\nwor", on_line)
  inspect(lines, content=(
    #|["hello"]
  ))
  lb.push("ld\n", on_line)
  inspect(lines, content=(
    #|["hello", "world"]
  ))
}

test "flush: emits remaining content" {
  let lb = LineBuffer::new()
  let lines : Array[String] = []
  let on_line = fn(line : String) { lines.push(line) }
  lb.push("hello\nworld", on_line)
  inspect(lines, content=(
    #|["hello"]
  ))
  lb.flush(on_line)
  inspect(lines, content=(
    #|["hello", "world"]
  ))
}

test "flush: nothing to emit" {
  let lb = LineBuffer::new()
  let lines : Array[String] = []
  lb.flush(fn(line) { lines.push(line) })
  inspect(lines, content=(
    #|[]
  ))
}

test "push: empty chunk" {
  let lb = LineBuffer::new()
  let lines : Array[String] = []
  lb.push("", fn(line) { lines.push(line) })
  inspect(lines, content=(
    #|[]
  ))
}

test "push: only newline" {
  let lb = LineBuffer::new()
  let lines : Array[String] = []
  lb.push("\n", fn(line) { lines.push(line) })
  inspect(lines, content=(
    #|[""]
  ))
}

test "push: consecutive newlines" {
  let lb = LineBuffer::new()
  let lines : Array[String] = []
  lb.push("a\n\nb\n", fn(line) { lines.push(line) })
  inspect(lines, content=(
    #|["a", "", "b"]
  ))
}

test "push: CRLF handling" {
  let lb = LineBuffer::new()
  let lines : Array[String] = []
  lb.push("hello\r\nworld\r\n", fn(line) { lines.push(line) })
  inspect(lines, content=(
    #|["hello", "world"]
  ))
}
