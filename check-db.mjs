import { createRequire } from "node:module";

const require = createRequire("C:/Users/water/AppData/Roaming/npm/node_modules/n8n/");

const sqlite3 = require("sqlite3");

const dbPath = "C:/Users/water/.codex/state_5.sqlite";
const db = new sqlite3.Database(dbPath, sqlite3.OPEN_READONLY);

db.serialize(() => {
  db.all("SELECT name FROM sqlite_master WHERE type='table'", (err, rows) => {
    if (err) {
      console.error("Error listing tables:", err);
      db.close();
      return;
    }
    console.log("Tables:", JSON.stringify(rows.map((r) => r.name)));
    db.all(
      "SELECT id, title, model, model_provider, cwd, updated_at_ms FROM threads ORDER BY updated_at_ms DESC LIMIT 20",
      (threadErr, threadRows) => {
        if (threadErr) {
          console.error("Error listing threads:", threadErr);
          db.close();
          return;
        }
        console.log("Threads:", JSON.stringify(threadRows, null, 2));
        db.close();
      },
    );
  });
});
