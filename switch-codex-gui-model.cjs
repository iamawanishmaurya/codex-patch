const { createRequire } = require("node:module");
const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
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
      "  node switch-codex-gui-model.cjs --model <model> [--thread <thread-id>] [--config-default] [--all-project-threads]",
      "",
      "Defaults:",
      "  Uses CODEX_THREAD_ID when available.",
      "  Otherwise repairs the latest thread for this workspace.",
      "  --all-project-threads updates all non-exec Codex Desktop threads across every project.",
      "",
      "Examples:",
      "  node switch-codex-gui-model.cjs --model mimo-v2.5-pro --all-project-threads",
      "  node switch-codex-gui-model.cjs --model gpt-5.5 --config-default",
    ].join("\n"),
  );
}

function parseArgs(argv) {
  const args = {
    model: null,
    threadId: process.env.CODEX_THREAD_ID || null,
    explicitThread: false,
    configDefault: false,
    allProjectThreads: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--model") {
      args.model = argv[++i];
    } else if (arg === "--thread") {
      args.threadId = argv[++i];
      args.explicitThread = true;
    } else if (arg === "--config-default") {
      args.configDefault = true;
    } else if (arg === "--all-project-threads") {
      args.allProjectThreads = true;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (!args.model) {
    usage();
    process.exit(2);
  }

  if (args.allProjectThreads && !args.explicitThread) {
    args.threadId = null;
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

function normalizeFsPath(value) {
  if (!value) {
    return value;
  }

  return value.startsWith("\\\\?\\") ? value.slice(4) : value;
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
    const row = await get(db, "SELECT id, title, model, model_provider, cwd, rollout_path FROM threads WHERE id = ?", [
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
    "SELECT id, title, model, model_provider, cwd, rollout_path FROM threads ORDER BY updated_at_ms DESC LIMIT 100",
  );
  const row = rows.find((item) => normalizePathForSql(item.cwd || "").includes(cwd));
  if (!row) {
    throw new Error(`no_recent_thread_for_workspace=${process.cwd()}`);
  }
  return row;
}

async function findProjectThreads(db) {
  const rows = await all(
    db,
    "SELECT id, title, model, model_provider, cwd, source, rollout_path FROM threads WHERE COALESCE(archived, 0) = 0 ORDER BY updated_at_ms DESC LIMIT 500",
  );
  return rows.filter((item) => {
    return item.source !== "exec";
  });
}

function updatePayloadModelMetadata(item, model, provider) {
  if (!item || typeof item !== "object" || !item.payload || typeof item.payload !== "object") {
    return false;
  }

  let changed = false;

  if (item.type === "session_meta") {
    if (item.payload.model_provider !== provider) {
      item.payload.model_provider = provider;
      changed = true;
    }
  }

  if (item.type === "turn_context") {
    if (item.payload.model !== model) {
      item.payload.model = model;
      changed = true;
    }

    if (item.payload.model_provider !== provider) {
      item.payload.model_provider = provider;
      changed = true;
    }

    const settings = item.payload.collaboration_mode && item.payload.collaboration_mode.settings;
    if (settings && typeof settings === "object") {
      if (settings.model !== model) {
        settings.model = model;
        changed = true;
      }

      if (settings.model_provider !== provider) {
        settings.model_provider = provider;
        changed = true;
      }
    }
  }

  return changed;
}

function syncRolloutMetadata(thread, model, provider) {
  const rolloutPath = normalizeFsPath(thread.rollout_path);
  if (!rolloutPath) {
    return { id: thread.id, title: thread.title, action: "missing_rollout_path", changed_lines: 0 };
  }

  if (!fs.existsSync(rolloutPath)) {
    return { id: thread.id, title: thread.title, action: "rollout_not_found", rollout_path: rolloutPath, changed_lines: 0 };
  }

  const before = fs.readFileSync(rolloutPath, "utf8");
  const newline = before.includes("\r\n") ? "\r\n" : "\n";
  const hadFinalNewline = before.endsWith("\n");
  const lines = before.split(/\r?\n/);
  let changedLines = 0;

  const nextLines = lines.map((line) => {
    if (!line.trim()) {
      return line;
    }

    try {
      const item = JSON.parse(line);
      if (updatePayloadModelMetadata(item, model, provider)) {
        changedLines += 1;
        return JSON.stringify(item);
      }
    } catch {
      return line;
    }

    return line;
  });

  let next = nextLines.join(newline);
  if (hadFinalNewline && !next.endsWith(newline)) {
    next += newline;
  }

  if (next !== before) {
    fs.writeFileSync(rolloutPath, next);
  }

  return {
    id: thread.id,
    title: thread.title,
    action: changedLines > 0 ? "updated" : "unchanged",
    rollout_path: rolloutPath,
    changed_lines: changedLines,
  };
}

function syncRolloutMetadataForThreads(threads, model, provider) {
  return threads.map((thread) => syncRolloutMetadata(thread, model, provider));
}

async function main() {
  const { model, threadId, configDefault, allProjectThreads } = parseArgs(process.argv.slice(2));
  const provider = providerForModel(model);
  const db = new sqlite3.Database(DB_PATH);

  try {
    if (allProjectThreads && !threadId) {
      const projectThreads = await findProjectThreads(db);
      if (projectThreads.length === 0) {
        throw new Error(`no_project_threads_for_workspace=${process.cwd()}`);
      }

      const placeholders = projectThreads.map(() => "?").join(",");
      const changes = await run(
        db,
        `UPDATE threads SET model = ?, model_provider = ? WHERE id IN (${placeholders})`,
        [model, provider, ...projectThreads.map((thread) => thread.id)],
      );
      const rolloutSync = syncRolloutMetadataForThreads(projectThreads, model, provider);

      console.log(`updated_rows=${changes}`);
      console.log(`updated_scope=all_gui_threads`);
      console.log(`updated_thread_count=${projectThreads.length}`);
      console.log(
        `updated_threads=${JSON.stringify(
          projectThreads.map((thread) => ({
            id: thread.id,
            title: thread.title,
            before_model: thread.model,
            before_provider: thread.model_provider,
            after_model: model,
            after_provider: provider,
          })),
        )}`,
      );
      console.log(`rollout_sync=${JSON.stringify(rolloutSync)}`);
      if (configDefault) {
        console.log(setConfigDefault(model));
      }
      console.log(`next_step=Fully close and reopen Codex Desktop before retrying this GUI project.`);
      return;
    }

    const before = await findTargetThread(db, threadId);
    const changes = await run(db, "UPDATE threads SET model = ?, model_provider = ? WHERE id = ?", [
      model,
      provider,
      before.id,
    ]);
    const rolloutSync = syncRolloutMetadataForThreads([before], model, provider);
    const after = await get(db, "SELECT id, title, model, model_provider, cwd, rollout_path FROM threads WHERE id = ?", [
      before.id,
    ]);

    console.log(`updated_rows=${changes}`);
    console.log(`before=${JSON.stringify(before)}`);
    console.log(`after=${JSON.stringify(after)}`);
    console.log(`rollout_sync=${JSON.stringify(rolloutSync)}`);
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
