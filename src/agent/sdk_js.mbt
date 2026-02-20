///| Run Claude Agent SDK via runner script
///| Returns JSONL output string. stderr is inherited (shown in real-time).
pub fn run_claude_sdk(opts_json : String) -> String {
  js_run_sdk("claude-runner.mjs", opts_json)
}

///| Run Codex SDK via runner script
///| Returns JSONL output string. stderr is inherited (shown in real-time).
pub fn run_codex_sdk(opts_json : String) -> String {
  js_run_sdk("codex-runner.mjs", opts_json)
}

///|
extern "js" fn js_run_sdk(runner : String, opts_json : String) -> String =
  #|(runner, optsJson) => {
  #|  try {
  #|    const { spawnSync } = require('child_process');
  #|    const path = require('path');
  #|    const runnerPath = path.join(__dirname, '..', 'sdk', runner);
  #|    const result = spawnSync(process.execPath, [runnerPath, optsJson], {
  #|      encoding: 'utf-8',
  #|      stdio: ['pipe', 'pipe', 'inherit'],
  #|      maxBuffer: 100 * 1024 * 1024,
  #|      timeout: 600000,
  #|    });
  #|    if (result.error) return 'ERROR: ' + (result.error.message || String(result.error));
  #|    if (result.status !== 0 && !result.stdout) return 'ERROR: exit code ' + result.status;
  #|    return result.stdout || '';
  #|  } catch (e) {
  #|    return 'ERROR: ' + (e.message || String(e));
  #|  }
  #|}
