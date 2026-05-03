const { createRequire } = require('node:module');
const requireFromN8n = createRequire('C:/Users/water/AppData/Roaming/npm/node_modules/n8n/');
const sqlite3 = requireFromN8n('sqlite3');
const db = new sqlite3.Database('C:/Users/water/.codex/state_5.sqlite');
const sql = `UPDATE threads SET model_provider = 'openai' WHERE model IN ('gpt-5.5','gpt-5.4','gpt-5.4-mini','gpt-5.3-codex','gpt-5.2') AND model_provider = 'cmp_1777839123484_1'`;
db.run(sql, function(err) {
  if (err) {
    console.error(err.message);
    process.exitCode = 1;
  } else {
    console.log(`updated_rows=${this.changes}`);
  }
  db.close();
});
