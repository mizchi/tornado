"use strict";

/**
 * Returns current time as "HH:MM:SS" string.
 * Single source of truth — used by both SDK (runner-io) and CLI (FFI).
 */
function nowTimestamp() {
  const d = new Date();
  const h = String(d.getHours()).padStart(2, "0");
  const m = String(d.getMinutes()).padStart(2, "0");
  const s = String(d.getSeconds()).padStart(2, "0");
  return `${h}:${m}:${s}`;
}

module.exports = { nowTimestamp };
