const { createRequire } = require('node:module');
const requireFromN8n = createRequire('C:/Users/water/AppData/Roaming/npm/node_modules/n8n/');
const sqlite3 = requireFromN8n('sqlite3');
const db = new sqlite3.Database('C:/Users/water/.codex/state_5.sqlite');
const sql = `UPDATE threads SET model_provider = 'openai' WHERE id = '019def7a-30c8-71f1-b952-b9c78722e126' AND model = 'gpt-5.5' AND model_provider = 'cmp_1777839123484_1'`;
db.run(sql, function(err) {
  if (err) {
    console.error(err.message);
    process.exitCode = 1;
  } else {
    console.log(`updated_rows=${this.changes}`);
  }
  db.close();
});
