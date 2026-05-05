const fs = require("node:fs");
const path = require("node:path");
const { xiaomiProvider, xiaomiModelSlugs } = require("./codex-models.cjs");

const base = "C:/Users/water/.codex";
const configPath = path.join(base, "config.toml");
const cachePath = path.join(base, "models_cache.json");
const catalogPath = path.join(base, "mimo-model-catalog.json");
const proxyPath = path.join(base, "mimo-responses-proxy", "mimo-responses-proxy.mjs");

function backup(file) {
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const backupPath = `${file}.bak-fix-${stamp}`;
  fs.copyFileSync(file, backupPath);
  console.log(`backup=${backupPath}`);
}

function updateOrInsertModel(models, entry) {
  const index = models.findIndex((model) => model.slug === entry.slug);
  if (index >= 0) {
    models[index] = entry;
    return "updated";
  }

  models.unshift(entry);
  return "inserted";
}

function cloneXiaomiCatalogEntry(template, model, provider) {
  const entry = JSON.parse(JSON.stringify(template));
  entry.slug = model.slug;
  entry.display_name = model.displayName;
  entry.description = model.description || template.description;
  entry.input_modalities = model.supportsImages ? ["text", "image"] : ["text"];
  entry.supports_image_detail_original = Boolean(model.supportsImages);
  entry.model_context_window = model.contextWindow || provider.contextWindow || template.model_context_window;
  entry.model_max_output_tokens =
    model.maxOutputTokens || provider.maxOutputTokens || template.model_max_output_tokens;
  entry.base_instructions = template.base_instructions || "You are MiMo, a coding agent powered by Xiaomi.";
  return entry;
}

function ensureConfig() {
  let config = fs.readFileSync(configPath, "utf8");
  const modelCatalogLine = 'model_catalog_json = "C:\\\\Users\\\\water\\\\.codex\\\\mimo-model-catalog.json"';
  if (!config.includes("model_catalog_json =")) {
    config = `${modelCatalogLine}\n${config}`;
  }

  config = config.replace('[profiles.mimo]\nmodel = "mimo-v2-pro"', '[profiles.mimo]\nmodel = "mimo-v2.5-pro"');

  const provider = xiaomiProvider();
  for (const model of provider.models || []) {
    const profileName = model.slug.replace(/\./g, "-");
    const profileHeader = `[profiles.${profileName}]`;
    if (!config.includes(profileHeader)) {
      config += [
        "",
        profileHeader,
        `model = "${model.slug}"`,
        `model_provider = "${provider.codexProviderId}"`,
        `model_context_window = ${model.contextWindow || provider.contextWindow}`,
        `model_max_output_tokens = ${model.maxOutputTokens || provider.maxOutputTokens}`,
        "",
      ].join("\n");
    }
  }

  fs.writeFileSync(configPath, config, "utf8");
  console.log("config_updated=true");
}

function ensureCatalogAndCache() {
  const provider = xiaomiProvider();
  const catalog = JSON.parse(fs.readFileSync(catalogPath, "utf8"));
  const cache = JSON.parse(fs.readFileSync(cachePath, "utf8"));
  catalog.models = Array.isArray(catalog.models) ? catalog.models : [];
  cache.models = Array.isArray(cache.models) ? cache.models : [];

  const template =
    catalog.models.find((model) => model.slug === "mimo-v2.5-pro") ||
    cache.models.find((model) => model.slug === "mimo-v2.5-pro");
  if (!template) {
    throw new Error("mimo-v2.5-pro template not found in catalog/cache");
  }

  const actions = [];
  for (const model of provider.models || []) {
    const entry = cloneXiaomiCatalogEntry(template, model, provider);
    actions.push(`${model.slug}:catalog:${updateOrInsertModel(catalog.models, entry)}`);
    actions.push(`${model.slug}:cache:${updateOrInsertModel(cache.models, entry)}`);
  }

  fs.writeFileSync(catalogPath, `${JSON.stringify(catalog, null, 2)}\n`, "utf8");
  fs.writeFileSync(cachePath, `${JSON.stringify(cache, null, 2)}\n`, "utf8");
  console.log(`models_cache_action=${actions.join(",")}`);
  console.log("models_cache_updated=true");
}

function ensureProxy() {
  const provider = xiaomiProvider();
  let proxy = fs.readFileSync(proxyPath, "utf8");
  const slugs = xiaomiModelSlugs();
  const aliases = [];
  for (const model of provider.models || []) {
    aliases.push([model.slug, model.slug]);
    for (const alias of model.aliases || []) {
      aliases.push([alias, model.slug]);
    }
  }

  proxy = proxy.replace(
    /const DEFAULT_MODEL = process\.env\.MIMO_MODEL \|\| "[^"]+";/,
    'const DEFAULT_MODEL = process.env.MIMO_MODEL || "mimo-v2.5-pro";',
  );
  proxy = proxy.replace(/const SUPPORTED_MODELS = new Set\(\[[\s\S]*?\]\);\s*/g, "");
  proxy = proxy.replace(
    /const MODEL_ALIASES = new Map\(\[[\s\S]*?\]\);/,
    [
      `const SUPPORTED_MODELS = new Set(${JSON.stringify(slugs, null, 2)});`,
      `const MODEL_ALIASES = new Map(${JSON.stringify(aliases, null, 2)});`,
    ].join("\n"),
  );
  proxy = proxy.replace(
    /function resolveModel\(model\) \{[\s\S]*?\n\}/,
    `function resolveModel(model) {
  if (!model || typeof model !== "string") {
    return DEFAULT_MODEL;
  }

  const resolved = MODEL_ALIASES.get(model.toLowerCase()) || MODEL_ALIASES.get(model) || model;
  if (SUPPORTED_MODELS.has(resolved)) {
    return resolved;
  }

  if (/^gpt-/i.test(resolved)) {
    const err = new Error(\`OpenAI model \${resolved} was routed to the Xiaomi proxy. Switch provider to OpenAI.\`);
    err.statusCode = 400;
    throw err;
  }

  return resolved;
}`,
  );
  proxy = proxy.replace(
    /data: \[\{ id: DEFAULT_MODEL, object: "model", created: nowSeconds\(\), owned_by: "mimo" \}\],/,
    `data: Array.from(SUPPORTED_MODELS).map((id) => ({ id, object: "model", created: nowSeconds(), owned_by: "xiaomi" })),`,
  );
  if (!proxy.includes("function sendSseComment(res, comment)")) {
    proxy = proxy.replace(
      /function sendSse\(res, event, data\) \{[\s\S]*?\n\}/,
      (match) => `${match}

function sendSseComment(res, comment) {
  if (!res.writableEnded) {
    res.write(\`: \${comment}\\n\\n\`);
  }
}`,
    );
  }
  proxy = proxy.replace(
    /if \(message\?\.content\) \{\s*output\.push\(\{([\s\S]*?)content: \[\{ type: "output_text", text: stringifyContent\(message\.content\), annotations: \[\] \}\],/,
    `const content = message?.content || message?.reasoning_content;
  if (content) {
    output.push({$1content: [{ type: "output_text", text: stringifyContent(content), annotations: [] }],`,
  );
  proxy = proxy.replace(
    /const content = stringifyContent\(message\.content\);/,
    `const content = stringifyContent(message.content || message.reasoning_content);`,
  );
  proxy = proxy.replace(
    /if \(delta\.content\) \{\s*emitTextDelta\(res, state, delta\.content\);\s*\}/,
    `if (delta.content) {
        emitTextDelta(res, state, delta.content);
      } else if (delta.reasoning_content) {
        sendSseComment(res, "mimo reasoning");
      }`,
  );
  if (!proxy.includes("const keepalive = setInterval(() => sendSseComment(res, \"mimo keepalive\"), 15000);")) {
    proxy = proxy.replace(
      /sendSse\(res, "response\.created", \{ response: createdResponse \}\);\s*\n/,
      `sendSse(res, "response.created", { response: createdResponse });

  const keepalive = setInterval(() => sendSseComment(res, "mimo keepalive"), 15000);
  try {
`,
    );
    proxy = proxy.replace(
      /(\s*)finishStream\(res, state, usage\);\s*\n\}/,
      `$1finishStream(res, state, usage);
  } finally {
    clearInterval(keepalive);
  }
}`,
    );
  }

  fs.writeFileSync(proxyPath, proxy, "utf8");
  console.log("proxy_updated=true");
}

backup(configPath);
backup(cachePath);
backup(catalogPath);
backup(proxyPath);

ensureConfig();
ensureCatalogAndCache();
ensureProxy();
