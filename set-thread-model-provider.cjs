const { createRequire } = require("node:module");

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
      "  node set-thread-model-provider.cjs --thread <thread-id> --model <model>",
      "  node set-thread-model-provider.cjs --current --model <model>",
      "",
      "Examples:",
      "  node set-thread-model-provider.cjs --current --model mimo-v2.5-pro",
      "  node set-thread-model-provider.cjs --current --model gpt-5.5",
    ].join("\n"),
  );
}

function parseArgs(argv) {
  const args = { threadId: null, model: null, current: false };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--current") {
      args.current = true;
    } else if (arg === "--thread") {
      args.threadId = argv[++i];
    } else if (arg === "--model") {
      args.model = argv[++i];
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (args.current) {
    args.threadId = process.env.CODEX_THREAD_ID;
  }

  if (!args.threadId || !args.model) {
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

const { threadId, model } = parseArgs(process.argv.slice(2));
const provider = providerForModel(model);
const db = new sqlite3.Database(DB_PATH);

db.serialize(() => {
  db.get(
    "SELECT id, title, model, model_provider FROM threads WHERE id = ?",
    [threadId],
    (selectErr, before) => {
      if (selectErr) {
        console.error(selectErr.message);
        process.exitCode = 1;
        db.close();
        return;
      }

      if (!before) {
        console.error(`thread_not_found=${threadId}`);
        process.exitCode = 1;
        db.close();
        return;
      }

      db.run(
        "UPDATE threads SET model = ?, model_provider = ? WHERE id = ?",
        [model, provider, threadId],
        function updateDone(updateErr) {
          if (updateErr) {
            console.error(updateErr.message);
            process.exitCode = 1;
            db.close();
            return;
          }

          console.log(`updated_rows=${this.changes}`);
          console.log(`before=${JSON.stringify(before)}`);
          console.log(`after=${JSON.stringify({ id: threadId, model, model_provider: provider })}`);
          db.close();
        },
      );
    },
  );
});
