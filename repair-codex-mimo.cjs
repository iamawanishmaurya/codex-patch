const fs = require('fs');
const path = require('path');

const base = 'C:/Users/water/.codex';
const configPath = path.join(base, 'config.toml');
const cachePath = path.join(base, 'models_cache.json');
const catalogPath = path.join(base, 'mimo-model-catalog.json');
const proxyPath = path.join(base, 'mimo-responses-proxy', 'mimo-responses-proxy.mjs');

function backup(file) {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const backupPath = `${file}.bak-fix-${stamp}`;
  fs.copyFileSync(file, backupPath);
  console.log(`backup=${backupPath}`);
}

backup(configPath);
backup(cachePath);
backup(proxyPath);

let config = fs.readFileSync(configPath, 'utf8');
const modelCatalogLine = 'model_catalog_json = "C:\\\\Users\\\\water\\\\.codex\\\\mimo-model-catalog.json"';
if (!config.includes('model_catalog_json =')) {
  config = `${modelCatalogLine}\n${config}`;
}
config = config.replace('[profiles.mimo]\nmodel = "mimo-v2-pro"', '[profiles.mimo]\nmodel = "mimo-v2.5-pro"');
fs.writeFileSync(configPath, config, 'utf8');
console.log('config_updated=true');

const catalog = JSON.parse(fs.readFileSync(catalogPath, 'utf8'));
const cache = JSON.parse(fs.readFileSync(cachePath, 'utf8'));
const mimoEntry = (catalog.models || []).find((m) => m.slug === 'mimo-v2.5-pro');
if (!mimoEntry) {
  throw new Error('mimo-v2.5-pro not found in mimo-model-catalog.json');
}
const cacheModels = Array.isArray(cache.models) ? cache.models : [];
const existingIndex = cacheModels.findIndex((m) => m.slug === 'mimo-v2.5-pro');
if (existingIndex >= 0) {
  cacheModels[existingIndex] = mimoEntry;
  console.log('models_cache_action=updated');
} else {
  cacheModels.unshift(mimoEntry);
  console.log('models_cache_action=inserted');
}
cache.models = cacheModels;
fs.writeFileSync(cachePath, JSON.stringify(cache, null, 2) + '\n', 'utf8');
console.log('models_cache_updated=true');

let proxy = fs.readFileSync(proxyPath, 'utf8');

const oldBlock = `function stringifyContent(value) {
  if (value === null || value === undefined) {
    return "";
  }

  if (typeof value === "string") {
    return value;
  }

  if (Array.isArray(value)) {
    return value.map(stringifyContent).filter(Boolean).join("\\n");
  }

  if (typeof value === "object") {
    if (typeof value.text === "string") return value.text;
    if (typeof value.input_text === "string") return value.input_text;
    if (typeof value.output_text === "string") return value.output_text;
    if (typeof value.refusal === "string") return value.refusal;
    if (value.type === "input_text" || value.type === "output_text") {
      return stringifyContent(value.text);
    }
    if (value.type === "input_image") {
      return \`[image: \${value.image_url || value.file_id || "attached"}]\`;
    }
    if (value.type === "input_file") {
      return \`[file: \${value.filename || value.file_id || "attached"}]\`;
    }
    if ("content" in value) {
      return stringifyContent(value.content);
    }
  }

  return JSON.stringify(value);
}`;

const newBlock = `function stringifyContent(value) {
  if (value === null || value === undefined) {
    return "";
  }

  if (typeof value === "string") {
    return value;
  }

  if (Array.isArray(value)) {
    return value.map(stringifyContent).filter(Boolean).join("\\n");
  }

  if (typeof value === "object") {
    if (typeof value.text === "string") return value.text;
    if (typeof value.input_text === "string") return value.input_text;
    if (typeof value.output_text === "string") return value.output_text;
    if (typeof value.refusal === "string") return value.refusal;
    if (value.type === "input_text" || value.type === "output_text") {
      return stringifyContent(value.text);
    }
    if (value.type === "input_file") {
      return \`[file: \${value.filename || value.file_id || "attached"}]\`;
    }
    if ("content" in value) {
      return stringifyContent(value.content);
    }
  }

  return JSON.stringify(value);
}

function convertContentParts(value) {
  const parts = [];

  function visit(node) {
    if (node === null || node === undefined) {
      return;
    }

    if (typeof node === "string") {
      if (node) {
        parts.push({ type: "text", text: node });
      }
      return;
    }

    if (Array.isArray(node)) {
      for (const item of node) {
        visit(item);
      }
      return;
    }

    if (typeof node !== "object") {
      parts.push({ type: "text", text: JSON.stringify(node) });
      return;
    }

    if (node.type === "input_image") {
      const url = node.image_url || node.file_id;
      if (url) {
        parts.push({
          type: "image_url",
          image_url: {
            url,
            detail: node.detail || "high",
          },
        });
      }
      return;
    }

    if (node.type === "input_text" || node.type === "output_text") {
      visit(node.text);
      return;
    }

    if (typeof node.text === "string") {
      parts.push({ type: "text", text: node.text });
      return;
    }

    if (typeof node.input_text === "string") {
      parts.push({ type: "text", text: node.input_text });
      return;
    }

    if (typeof node.output_text === "string") {
      parts.push({ type: "text", text: node.output_text });
      return;
    }

    if (typeof node.refusal === "string") {
      parts.push({ type: "text", text: node.refusal });
      return;
    }

    if (node.type === "input_file") {
      parts.push({
        type: "text",
        text: \`[file: \${node.filename || node.file_id || "attached"}]\`,
      });
      return;
    }

    if ("content" in node) {
      visit(node.content);
      return;
    }

    parts.push({ type: "text", text: JSON.stringify(node) });
  }

  visit(value);
  return parts;
}`;

if (!proxy.includes('function convertContentParts(value) {')) {
  proxy = proxy.replace(oldBlock, newBlock);
}

const oldMessageBlock = `  if (item.type === "message" || item.role) {
    const role = item.role === "tool" ? "user" : item.role || "user";
    messages.push({
      role,
      content: stringifyContent(item.content),
    });
    return;
  }

  if (item.content) {
    messages.push({
      role: item.role || "user",
      content: stringifyContent(item.content),
    });
  }`;

const newMessageBlock = `  if (item.type === "message" || item.role) {
    const role = item.role === "tool" ? "user" : item.role || "user";
    const contentParts = convertContentParts(item.content);
    messages.push({
      role,
      content: contentParts.length > 0 ? contentParts : stringifyContent(item.content),
    });
    return;
  }

  if (item.content) {
    const contentParts = convertContentParts(item.content);
    messages.push({
      role: item.role || "user",
      content: contentParts.length > 0 ? contentParts : stringifyContent(item.content),
    });
  }`;

proxy = proxy.replace(oldMessageBlock, newMessageBlock);
fs.writeFileSync(proxyPath, proxy, 'utf8');
console.log('proxy_updated=true');
