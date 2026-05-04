const fs = require("node:fs");
const path = require("node:path");

const MODEL_CONFIG_PATH = path.join(__dirname, "codex-models.json");
const modelConfig = JSON.parse(fs.readFileSync(MODEL_CONFIG_PATH, "utf8"));

function providers() {
  return modelConfig.providers || [];
}

function models() {
  return providers().flatMap((provider) =>
    (provider.models || []).map((model) => ({ ...model, provider })),
  );
}

function findProviderById(id) {
  return providers().find((provider) => provider.id === id || provider.codexProviderId === id) || null;
}

function findModel(slug) {
  return models().find((entry) => entry.slug === slug) || null;
}

function providerForModel(slug) {
  const entry = findModel(slug);
  if (!entry) {
    throw new Error(`No provider mapping is known for model: ${slug}`);
  }

  return entry.provider.codexProviderId;
}

function isProviderModel(slug, providerId) {
  const entry = findModel(slug);
  return Boolean(entry && entry.provider.id === providerId);
}

function modelsForProvider(providerId) {
  const provider = findProviderById(providerId);
  if (!provider) {
    return [];
  }

  return provider.models || [];
}

function openAiModelSlugs() {
  return modelsForProvider("openai").map((model) => model.slug);
}

function xiaomiModelSlugs() {
  return modelsForProvider("xiaomi").map((model) => model.slug);
}

function xiaomiProvider() {
  return findProviderById("xiaomi");
}

module.exports = {
  MODEL_CONFIG_PATH,
  modelConfig,
  providers,
  models,
  findProviderById,
  findModel,
  providerForModel,
  isProviderModel,
  modelsForProvider,
  openAiModelSlugs,
  xiaomiModelSlugs,
  xiaomiProvider,
};
