const { createRequire } = require("node:module");
const { findProviderById, openAiModelSlugs, xiaomiModelSlugs } = require("./codex-models.cjs");

const requireFromN8n = createRequire("C:/Users/water/AppData/Roaming/npm/node_modules/n8n/");
const sqlite3 = requireFromN8n("sqlite3");

const DB_PATH = "C:/Users/water/.codex/state_5.sqlite";
const INTERVAL_MS = Number(process.env.CODEX_PROVIDER_WATCH_MS || "1000");
const MIMO_PROVIDER = findProviderById("xiaomi").codexProviderId;
const OPENAI_PROVIDER = findProviderById("openai").codexProviderId;
const OPENAI_MODELS = openAiModelSlugs();
const XIAOMI_MODELS = xiaomiModelSlugs();

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
    const xiaomiPlaceholders = XIAOMI_MODELS.map(() => "?").join(",");
    const mimoChanges = await run(
      db,
      `UPDATE threads SET model_provider = ? WHERE model IN (${xiaomiPlaceholders}) AND model_provider <> ?`,
      [MIMO_PROVIDER, ...XIAOMI_MODELS, MIMO_PROVIDER],
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
