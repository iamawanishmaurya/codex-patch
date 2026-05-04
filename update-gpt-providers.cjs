const { createRequire } = require('node:module');
const { openAiModelSlugs, findProviderById } = require('./codex-models.cjs');
const requireFromN8n = createRequire('C:/Users/water/AppData/Roaming/npm/node_modules/n8n/');
const sqlite3 = requireFromN8n('sqlite3');
const db = new sqlite3.Database('C:/Users/water/.codex/state_5.sqlite');
const openAiProvider = findProviderById('openai').codexProviderId;
const models = openAiModelSlugs();
const placeholders = models.map(() => '?').join(',');
const sql = `UPDATE threads SET model_provider = ? WHERE model IN (${placeholders}) AND model_provider <> ?`;
db.run(sql, [openAiProvider, ...models, openAiProvider], function(err) {
  if (err) {
    console.error(err.message);
    process.exitCode = 1;
  } else {
    console.log(`updated_rows=${this.changes}`);
  }
  db.close();
});
