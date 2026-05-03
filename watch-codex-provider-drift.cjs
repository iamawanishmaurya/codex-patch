const { createRequire } = require("node:module");

const requireFromN8n = createRequire("C:/Users/water/AppData/Roaming/npm/node_modules/n8n/");
const sqlite3 = requireFromN8n("sqlite3");

const DB_PATH = "C:/Users/water/.codex/state_5.sqlite";
const INTERVAL_MS = Number(process.env.CODEX_PROVIDER_WATCH_MS || "1000");
const MIMO_PROVIDER = "cmp_1777839123484_1";
const OPENAI_PROVIDER = "openai";
const OPENAI_MODELS = ["gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "gpt-5.3-codex", "gpt-5.2"];

function run(db, sql, params = []) {
  return new Promise((resolve, reject) => {
    db.run(sql, params, function done(err) {
      if (err) {
        reject(err);
        return;
      }

      resolve(this.changes);
    });
  });
}

async function repairOnce() {
  const db = new sqlite3.Database(DB_PATH);

  try {
    const placeholders = OPENAI_MODELS.map(() => "?").join(",");
    const gptChanges = await run(
      db,
      `UPDATE threads SET model_provider = ? WHERE model IN (${placeholders}) AND model_provider <> ?`,
      [OPENAI_PROVIDER, ...OPENAI_MODELS, OPENAI_PROVIDER],
    );
    const mimoChanges = await run(
      db,
      "UPDATE threads SET model_provider = ? WHERE model = ? AND model_provider <> ?",
      [MIMO_PROVIDER, "mimo-v2.5-pro", MIMO_PROVIDER],
    );

    const total = gptChanges + mimoChanges;
    if (total > 0) {
      console.log(`${new Date().toISOString()} repaired_rows=${total}`);
    }
  } finally {
    db.close();
  }
}

async function main() {
  console.log(`watching=${DB_PATH}`);
  console.log(`interval_ms=${INTERVAL_MS}`);

  await repairOnce();
  setInterval(() => {
    repairOnce().catch((err) => {
      console.error(`${new Date().toISOString()} ${err.message}`);
    });
  }, INTERVAL_MS);
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
