///| Read a file synchronously (JS/Node.js only)
pub fn read_file_sync(path : String) -> String {
  js_read_file_sync(path)
}

///|
extern "js" fn js_read_file_sync(path : String) -> String =
  #|(path) => {
  #|  try {
  #|    const fs = require('fs');
  #|    return fs.readFileSync(path, 'utf-8');
  #|  } catch (e) {
  #|    return 'ERROR: ' + (e.message || String(e));
  #|  }
  #|}

///| Show prompt and read a line from stdin synchronously
pub fn prompt_sync(message : String) -> String {
  js_prompt_sync(message)
}

///|
extern "js" fn js_prompt_sync(message : String) -> String =
  #|(message) => {
  #|  const fs = require('fs');
  #|  process.stdout.write(message);
  #|  const buf = Buffer.alloc(4096);
  #|  try {
  #|    const n = fs.readSync(0, buf, 0, buf.length);
  #|    return buf.toString('utf-8', 0, n).trim();
  #|  } catch (e) {
  #|    return '';
  #|  }
  #|}

///| Write a file synchronously
pub fn write_file_sync(path : String, content : String) -> Unit {
  js_write_file_sync(path, content)
}

///|
extern "js" fn js_write_file_sync(path : String, content : String) -> Unit =
  #|(path, content) => {
  #|  const fs = require('fs');
  #|  fs.writeFileSync(path, content, 'utf-8');
  #|}

///| Execute a shell command synchronously, return stdout
pub fn exec_sync(command : String) -> String {
  js_exec_sync(command)
}

///|
extern "js" fn js_exec_sync(command : String) -> String =
  #|(command) => {
  #|  try {
  #|    const { execSync } = require('child_process');
  #|    return execSync(command, { encoding: 'utf-8', timeout: 10000 }).trim();
  #|  } catch (e) {
  #|    return '';
  #|  }
  #|}

///| Get current timestamp as "HH:MM:SS" string
pub fn now_timestamp() -> String {
  js_now_timestamp()
}

///|
extern "js" fn js_now_timestamp() -> String =
  #|() => {
  #|  const d = new Date();
  #|  const h = String(d.getHours()).padStart(2, '0');
  #|  const m = String(d.getMinutes()).padStart(2, '0');
  #|  const s = String(d.getSeconds()).padStart(2, '0');
  #|  return h + ':' + m + ':' + s;
  #|}
