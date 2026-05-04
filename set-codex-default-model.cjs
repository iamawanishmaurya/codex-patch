const fs = require("node:fs");
const { findModel, providerForModel, isProviderModel } = require("./codex-models.cjs");

const CONFIG_PATH = "C:/Users/water/.codex/config.toml";
const CATALOG_PATH = "C:\\\\Users\\\\water\\\\.codex\\\\mimo-model-catalog.json";

function usage() {
  console.error(
    [
      "Usage:",
      "  node set-codex-default-model.cjs --model <model>",
      "  node set-codex-default-model.cjs --clear",
      "",
      "Examples:",
      "  node set-codex-default-model.cjs --model gpt-5.5",
      "  node set-codex-default-model.cjs --model mimo-v2.5-pro",
      "  node set-codex-default-model.cjs --model mimo-v2.5",
    ].join("\n"),
  );
}

function parseArgs(argv) {
  const args = { model: null, clear: false };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--model") {
      args.model = argv[++i];
    } else if (arg === "--clear") {
      args.clear = true;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (!args.clear && !args.model) {
    usage();
    process.exit(2);
  }

  return args;
}

function splitTopLevel(config) {
  const lines = config.split(/\r?\n/);
  const firstTableIndex = lines.findIndex((line) => /^\s*\[/.test(line));
  if (firstTableIndex === -1) {
    return { top: lines, rest: [] };
  }

  return {
    top: lines.slice(0, firstTableIndex),
    rest: lines.slice(firstTableIndex),
  };
}

function removeDefaultKeys(lines) {
  const defaultKeys = new Set([
    "model",
    "model_provider",
    "model_context_window",
    "model_max_output_tokens",
  ]);

  return lines.filter((line) => {
    const match = line.match(/^\s*([A-Za-z0-9_-]+)\s*=/);
    return !match || !defaultKeys.has(match[1]);
  });
}

function ensureCatalogLine(lines) {
  const catalogLine = `model_catalog_json = "${CATALOG_PATH}"`;
  const withoutCatalog = lines.filter((line) => !/^\s*model_catalog_json\s*=/.test(line));
  return [catalogLine, ...withoutCatalog.filter((line, index) => index !== 0 || line.trim() !== "")];
}

function buildDefaultLines(model) {
  const provider = providerForModel(model);
  const lines = [`model = "${model}"`, `model_provider = "${provider}"`];

  if (isProviderModel(model, "xiaomi")) {
    const entry = findModel(model);
    const providerConfig = entry.provider;
    const contextWindow = entry.contextWindow || providerConfig.contextWindow;
    const maxOutputTokens = entry.maxOutputTokens || providerConfig.maxOutputTokens;
    if (contextWindow) {
      lines.push(`model_context_window = ${contextWindow}`);
    }
    if (maxOutputTokens) {
      lines.push(`model_max_output_tokens = ${maxOutputTokens}`);
    }
  }

  return lines;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const before = fs.readFileSync(CONFIG_PATH, "utf8");
  const { top, rest } = splitTopLevel(before);
  let nextTop = ensureCatalogLine(removeDefaultKeys(top));

  if (!args.clear) {
    nextTop = [...buildDefaultLines(args.model), ...nextTop];
  }

  while (nextTop.length > 0 && nextTop[nextTop.length - 1].trim() === "") {
    nextTop.pop();
  }

  const next = `${nextTop.join("\n")}\n${rest.join("\n")}`;
  if (next !== before) {
    fs.writeFileSync(CONFIG_PATH, next);
  }

  if (args.clear) {
    console.log("cleared_config_default_model=true");
  } else {
    console.log(`config_default_model=${args.model}`);
    console.log(`config_default_provider=${providerForModel(args.model)}`);
  }
  console.log(`config_path=${CONFIG_PATH}`);
}

main();
