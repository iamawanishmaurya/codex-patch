const { createRequire } = require("node:module");
const { spawnSync } = require("node:child_process");
const path = require("node:path");

const requireFromN8n = createRequire("C:/Users/water/AppData/Roaming/npm/node_modules/n8n/");
const sqlite3 = requireFromN8n("sqlite3");

const DB_PATH = "C:/Users/water/.codex/state_5.sqlite";
const MIMO_PROVIDER = "cmp_1777839123484_1";
const OPENAI_PROVIDER = "openai";
const OPENAI_MODELS = new Set(["gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "gpt-5.3-codex", "gpt-5.2"]);

function usage() {
  console.error(
    [
      "Usage:",
      "  node switch-codex-gui-model.cjs --model <model> [--thread <thread-id>] [--config-default]",
      "",
      "Defaults:",
      "  Uses CODEX_THREAD_ID when available.",
      "  Otherwise repairs the latest thread for this workspace.",
      "",
      "Examples:",
      "  node switch-codex-gui-model.cjs --model mimo-v2.5-pro",
      "  node switch-codex-gui-model.cjs --model gpt-5.5 --config-default",
    ].join("\n"),
  );
}

function parseArgs(argv) {
  const args = {
    model: null,
    threadId: process.env.CODEX_THREAD_ID || null,
    configDefault: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--model") {
      args.model = argv[++i];
    } else if (arg === "--thread") {
      args.threadId = argv[++i];
    } else if (arg === "--config-default") {
      args.configDefault = true;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (!args.model) {
    usage();
    process.exit(2);
  }

  return args;
}

function providerForModel(model) {
  if (model === "mimo-v2.5-pro") {
    return MIMO_PROVIDER;
  }

  if (OPENAI_MODELS.has(model)) {
    return OPENAI_PROVIDER;
  }

  throw new Error(`No provider mapping is known for model: ${model}`);
}

function normalizePathForSql(value) {
  return value.replace(/\//g, "\\").toLowerCase();
}

function get(db, sql, params = []) {
  return new Promise((resolve, reject) => {
    db.get(sql, params, (err, row) => (err ? reject(err) : resolve(row)));
  });
}

function all(db, sql, params = []) {
  return new Promise((resolve, reject) => {
    db.all(sql, params, (err, rows) => (err ? reject(err) : resolve(rows)));
  });
}

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

function setConfigDefault(model) {
  const script = path.join(__dirname, "set-codex-default-model.cjs");
  const result = spawnSync(process.execPath, [script, "--model", model], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });

  if (result.status !== 0) {
    throw new Error(result.stderr.trim() || `set_config_default_failed=${result.status}`);
  }

  return result.stdout.trim();
}

async function findTargetThread(db, requestedThreadId) {
  if (requestedThreadId) {
    const row = await get(db, "SELECT id, title, model, model_provider, cwd FROM threads WHERE id = ?", [
      requestedThreadId,
    ]);
    if (!row) {
      throw new Error(`thread_not_found=${requestedThreadId}`);
    }
    return row;
  }

  const cwd = normalizePathForSql(process.cwd());
  const rows = await all(
    db,
    "SELECT id, title, model, model_provider, cwd FROM threads ORDER BY updated_at_ms DESC LIMIT 100",
  );
  const row = rows.find((item) => normalizePathForSql(item.cwd || "").includes(cwd));
  if (!row) {
    throw new Error(`no_recent_thread_for_workspace=${process.cwd()}`);
  }
  return row;
}

async function main() {
  const { model, threadId, configDefault } = parseArgs(process.argv.slice(2));
  const provider = providerForModel(model);
  const db = new sqlite3.Database(DB_PATH);

  try {
    const before = await findTargetThread(db, threadId);
    const changes = await run(db, "UPDATE threads SET model = ?, model_provider = ? WHERE id = ?", [
      model,
      provider,
      before.id,
    ]);
    const after = await get(db, "SELECT id, title, model, model_provider, cwd FROM threads WHERE id = ?", [
      before.id,
    ]);

    console.log(`updated_rows=${changes}`);
    console.log(`before=${JSON.stringify(before)}`);
    console.log(`after=${JSON.stringify(after)}`);
    if (configDefault) {
      console.log(setConfigDefault(model));
    }
    console.log(`next_step=Fully close and reopen Codex Desktop before retrying this GUI thread.`);
  } finally {
    db.close();
  }
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
