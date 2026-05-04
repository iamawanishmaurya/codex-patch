# Codex Model Patch Guide: GPT-5.5 + MiMo

This repo documents the local Codex Desktop/CLI patch used to keep OpenAI
Codex models and Xiaomi MiMo available side by side.

The main failure we fixed was model/provider drift: a `gpt-5.5` thread was
still bound to the custom MiMo provider, so Codex sent `gpt-5.5` to Xiaomi and
Xiaomi correctly rejected it with:

```text
Mimo upstream returned HTTP 400:
Not supported model gpt-5.5
```

## Current Verified State

Verified on this machine on 2026-05-04:

- Codex CLI was upgraded from `0.120.0` to `0.128.0`.
- `codex exec --model gpt-5.5 ...` routed through `openai` and returned
  `CLI_GPT55_OK` before the account quota was exhausted. A later recheck hit
  the ChatGPT Codex usage limit and reported retry availability on
  2026-05-11 03:18.
- `codex exec --profile mimo ...` works and returns `CLI_MIMO_OK`.
- MiMo CLI tool execution works; a shell-tool test returned `CLI_MIMO_TOOL_OK`.
- MiMo CLI image input works; `codex exec --profile mimo --image ...` returned
  `CLI_MIMO_IMAGE_OK`.
- After the hard-switch helper was added, GPT-5.5 CLI returned
  `CLI_GPT55_AFTER_PATCH_OK`.
- After the hard-switch helper was added, MiMo CLI returned
  `CLI_MIMO_AFTER_PATCH_OK`.
- After the hard-switch helper was added, MiMo CLI image input returned
  `CLI_MIMO_IMAGE_AFTER_PATCH_OK`.
- The local MiMo proxy accepts direct text, image-shaped, and function-call
  requests.
- The Codex config includes the custom model catalog hook so MiMo can appear in
  Desktop GUI model lists.
- Xiaomi's `/v1/models` endpoint currently reports `mimo-v2-omni`,
  `mimo-v2-pro`, `mimo-v2.5`, `mimo-v2.5-pro`, and TTS variants. The launcher
  exposes the four Codex-usable chat/omni models and excludes TTS models from
  Codex chat switching.
- `mimo-v2.5-pro`, `mimo-v2.5`, `mimo-v2-pro`, and `mimo-v2-omni` are present
  in both the custom catalog and models cache with `["text", "image"]`
  modalities and tool support enabled.
- `codex-gui` sets the top-level default to the selected model/provider pair.
  After the latest multi-MiMo verification, the default is
  `mimo-v2.5-pro/cmp_1777839123484_1`.
- `codex-gui` now uses a colored quiet launcher with a spinner; raw repair and
  thread-sync logs are hidden unless `-VerboseLogs` or `--verbose` is passed.
- `codex-gui /login` now provides an interactive provider/API setup and then a
  provider-scoped model picker.
- `/login` was verified with Xiaomi: it kept the saved `MIMO_API_KEY`, fetched
  live Xiaomi models, showed the Xiaomi-only model list, and switched to
  `mimo-v2-omni` in a no-restart test.
- The installed `codex-gui.cmd` shim was verified in quiet spinner mode and in
  explicit `--logs` mode with `--no-restart`.
- The local proxy `/v1/models` route now reports all four Codex-ready Xiaomi
  models, and direct proxy tests confirmed `mimo-v2.5-pro` and `mimo-v2.5` are
  forwarded as their selected upstream model slugs.
- The latest GUI project repair moved all 4 visible `mimo` project chats to
  `mimo-v2.5-pro/cmp_1777839123484_1`.
- The GUI switch now updates both `state_5.sqlite` and each selected thread's
  rollout JSONL metadata so Codex Desktop does not rebuild mixed GPT/MiMo
  sidebar state on launch.
- A no-restart switch verification synced all 4 visible project chats to
  `gpt-5.5/openai`, then back to `mimo-v2.5-pro/cmp_1777839123484_1`; SQLite
  and rollout metadata were clean in both directions.
- After the rollout metadata sync fix, MiMo CLI image input returned
  `MIMO_IMAGE_ROLLOUT_SYNC_OK`.
- The saved thread database currently has no known GPT/MiMo provider
  mismatches; the latest check covered 48 active known-model thread rows with
  0 mismatches.
- Earlier GUI 400s came from live Desktop sessions where the visible model slug
  changed but the in-memory provider did not. For GUI use, run the hard-switch
  helper and let it restart Desktop so the provider binding is reloaded.

Non-blocking warnings still appear in some CLI runs from Codex plugin/analytics
sync calls returning HTTP 403 from `chatgpt.com`. They did not block GPT-5.5,
MiMo text, MiMo tool use, or MiMo image tests.

## Important Files

Codex files outside this repo:

- `C:\Users\water\.codex\config.toml`
- `C:\Users\water\.codex\mimo-model-catalog.json`
- `C:\Users\water\.codex\models_cache.json`
- `C:\Users\water\.codex\state_5.sqlite`
- `C:\Users\water\.codex\mimo-responses-proxy\mimo-responses-proxy.mjs`

Helper files in this repo:

- `codex-models.json` is the shared provider/model catalog used by the
  launcher and Node repair/switch helpers.
- `codex-models.cjs` loads that shared catalog for Node scripts.
- `codex-gui.ps1` provides the interactive `codex-gui` terminal command.
- `install-codex-gui-alias.ps1` installs `codex-gui.cmd` into
  `C:\Users\water\bin` and adds that folder to the user PATH.
- `repair-codex-mimo.cjs` repairs config, cache, and proxy image handling.
- `hard-switch-codex-gui-model.ps1` sets the requested GUI model/provider pair
  and restarts Codex Desktop so the running provider is reloaded.
- `set-codex-default-model.cjs` changes the top-level Desktop default
  model/provider pair in `config.toml`.
- `switch-codex-gui-model.cjs` switches the current or latest GUI thread to
  the matching model/provider pair and syncs rollout JSONL metadata for the
  same threads.
- `watch-codex-provider-drift.cjs` continuously repairs saved thread rows when
  Codex Desktop writes a model/provider mismatch.
- `update-gpt-providers.cjs` moves GPT threads away from the MiMo provider.
- `update-thread-provider.cjs` repairs one known bad thread.
- `check-db.mjs` lists recent Codex thread model/provider bindings.

## Correct Routing

OpenAI Codex models must use the OpenAI provider:

```text
gpt-5.5        -> openai
gpt-5.4        -> openai
gpt-5.4-mini   -> openai
gpt-5.3-codex  -> openai
gpt-5.2        -> openai
```

MiMo must use the local MiMo Responses proxy provider:

```text
mimo-v2.5-pro -> cmp_1777839123484_1
mimo-v2.5     -> cmp_1777839123484_1
mimo-v2-pro   -> cmp_1777839123484_1
mimo-v2-omni  -> cmp_1777839123484_1
```

The local provider points Codex at:

```text
http://127.0.0.1:41418/v1
```

The proxy forwards requests to Xiaomi's OpenAI-compatible Chat Completions
endpoint:

```text
https://token-plan-sgp.xiaomimimo.com/v1/chat/completions
```

## Config Shape

`C:\Users\water\.codex\config.toml` needs this top-level catalog line:

```toml
model_catalog_json = "C:\\Users\\water\\.codex\\mimo-model-catalog.json"
```

The MiMo provider/profile should look like this:

```toml
[model_providers.cmp_1777839123484_1]
name = "Mimo v2.5 Pro"
base_url = "http://127.0.0.1:41418/v1"
wire_api = "responses"
request_max_retries = 1
stream_idle_timeout_ms = 300000

[profiles.mimo]
model = "mimo-v2.5-pro"
model_provider = "cmp_1777839123484_1"
model_context_window = 1048576
model_max_output_tokens = 131072
```

The context value is advertised in the model catalog. The large output cap is
set on the Codex profile with `model_max_output_tokens = 131072`.

## Model Catalog Entry

`mimo-model-catalog.json` and `models_cache.json` both need a visible MiMo
entry. The key fields are:

```json
{
  "slug": "mimo-v2.5-pro",
  "display_name": "MiMo-V2.5-Pro",
  "visibility": "list",
  "input_modalities": ["text", "image"],
  "supports_image_detail_original": true,
  "supports_parallel_tool_calls": true,
  "context_window": 1048576
}
```

`model_catalog_json` is the durable Desktop hook. `models_cache.json` can still
be refreshed or overwritten by Codex, so rerun the repair script if MiMo
disappears from the GUI picker after a refresh.

## Proxy Requirements

The MiMo proxy exists because Codex uses the Responses API shape while Xiaomi's
endpoint is Chat Completions shaped.

The proxy must translate:

- Responses `input_text` parts into Chat Completions text parts.
- Responses `input_image` parts into Chat Completions `image_url` parts.
- Responses tools/functions into Chat Completions tools.
- Chat Completions tool calls back into Responses `function_call` output items.

The proxy should map the GUI-facing slug to Xiaomi's accepted upstream model:

```text
mimo-v2.5-pro -> mimo-v2-pro
```

Do not alias OpenAI model names such as `gpt-5.5` to MiMo. If a GPT thread hits
the MiMo proxy, the thread/provider binding is wrong and should be repaired.

## Repair Commands

Run from this repo:

```powershell
node repair-codex-mimo.cjs
node update-gpt-providers.cjs
node check-db.mjs
```

Restart the proxy if needed:

```powershell
$pids = (netstat -ano | Select-String ":41418").ToString() -replace '.*\s(\d+)$','$1' | Sort-Object -Unique
$pids | ForEach-Object { Stop-Process -Id $_ -Force }
Start-Process -WindowStyle Hidden -FilePath node -ArgumentList "C:\Users\water\.codex\mimo-responses-proxy\mimo-responses-proxy.mjs"
```

Check proxy health:

```powershell
Invoke-RestMethod http://127.0.0.1:41418/v1/healthz
```

## CLI Verification

GPT-5.5:

```powershell
codex exec --model gpt-5.5 --dangerously-bypass-approvals-and-sandbox "Reply exactly CLI_GPT55_OK"
```

MiMo text:

```powershell
codex exec --profile mimo --dangerously-bypass-approvals-and-sandbox "Reply exactly CLI_MIMO_OK"
```

MiMo tool use:

```powershell
codex exec --profile mimo --dangerously-bypass-approvals-and-sandbox "Use the shell tool to run Write-Output CLI_MIMO_TOOL_OK, then reply exactly CLI_MIMO_TOOL_OK."
```

MiMo image:

```powershell
codex exec --profile mimo --image C:\path\to\image.png --dangerously-bypass-approvals-and-sandbox "An image is attached. Reply exactly CLI_MIMO_IMAGE_OK."
```

If GPT-5.5 fails with "requires a newer version of Codex", upgrade the CLI:

```powershell
npm install -g @openai/codex@latest
codex --version
```

## GUI Verification

The easiest path is the terminal command:

```powershell
.\install-codex-gui-alias.ps1
codex-gui
```

`codex-gui` shows a colored menu, switches the selected model/provider pair,
and launches a fresh Codex Desktop session. By default it switches visible
non-`exec` GUI chats together, so sidebar groups do not keep mixed providers.
It also accepts direct model aliases:

```powershell
codex-gui gpt-5.5
codex-gui mimo
codex-gui mino
codex-gui mimo-v2.5
codex-gui omni
```

For the OpenClaude-style setup path, use `/login`:

```powershell
codex-gui /login
```

That flow first asks for a provider, then handles provider setup. OpenAI uses
the existing Codex Desktop sign-in. Xiaomi asks for `MIMO_API_KEY` if it is not
already saved, checks `https://token-plan-sgp.xiaomimimo.com/v1/models`, and
then shows only Xiaomi MiMo models for the Xiaomi provider.

Normal runs are quiet and show only the selected model, provider, spinner, and
final success line. Use verbose mode only when you need the full diagnostic log:

```powershell
codex-gui mimo -VerboseLogs
codex-gui gpt55 --verbose
```

The launcher also accepts CLI-style flags such as `--logs`, `--no-restart`,
`--current-only`, `--thread <id>`, and `--plain`.

Use `codex-gui mimo -CurrentOnly` only when you intentionally want to switch
just the current/latest thread row.

One-shot `codex exec ...` verification runs are stored with `source=exec`.
Codex Desktop does not show those in the normal GUI chat list, so the
project-wide switch intentionally targets visible non-`exec` project chats.

The launcher uses the registered Windows app id from `Get-StartApps` instead
of relying on direct `C:\Program Files\WindowsApps` directory access. That
avoids the `Could not locate Codex.exe under C:\Program Files\WindowsApps`
failure on systems where Windows blocks listing that folder.

The hard switch stops Codex Desktop before writing `state_5.sqlite`. If Desktop
stays open while the database is edited, the live session can write its old
model/provider back and the sidebar may show only the one chat that kept the
new model.

Codex Desktop can also rebuild sidebar metadata from per-thread rollout JSONL
files under `C:\Users\water\.codex\sessions`. The switch helper updates
`session_meta.model_provider`, `turn_context.model`, and the collaboration-mode
model/provider fields in those files alongside SQLite.

Codex Desktop 0.128 can change a visible model slug inside an already-running
thread without changing that thread's provider. Use the hard switch helper for
cross-provider changes:

```powershell
.\hard-switch-codex-gui-model.ps1 -Model mimo-v2.5-pro
.\hard-switch-codex-gui-model.ps1 -Model gpt-5.5
```

Use `-NoRestart` only for a dry run. The restart is the important part for the
GUI, because the live session keeps its provider in memory.

After switching to MiMo:

1. Confirm the proxy is running on `127.0.0.1:41418`.
2. Reopen Codex Desktop.
3. Open the repaired thread or create a new thread after the switch.
4. Confirm `MiMo-V2.5-Pro` is selected.
5. Send `Introduce yourself`.
6. Attach an image and confirm the image button is available.

After switching back to GPT:

1. Run `.\hard-switch-codex-gui-model.ps1 -Model gpt-5.5`.
2. Reopen Codex Desktop.
3. Send a short prompt and confirm the logs show `provider=OpenAI`.

If the GUI reconnects five times and shows `Not supported model gpt-5.5`, the
active thread is still routed to the MiMo provider. Run:

```powershell
node update-gpt-providers.cjs
```

Then run the GPT hard switch so the live Desktop session reloads OpenAI:

```powershell
.\hard-switch-codex-gui-model.ps1 -Model gpt-5.5
```

## Adding Any Custom Model To Codex

Use this checklist when adding another provider/model:

1. Add the provider and model slugs to `codex-models.json`; this drives the
   launcher menu, provider mapping, repair scripts, and drift watcher.
2. Create or reuse a local proxy if the provider does not natively support the
   exact Codex wire API.
3. Add a `[model_providers.<id>]` entry in `config.toml`.
4. Add a `[profiles.<name>]` entry pointing to the provider and model slug.
5. Add the model to a custom catalog JSON.
6. Point `model_catalog_json` at that custom catalog.
7. Mirror the model entry into `models_cache.json` if the GUI does not show it.
8. Set realistic `context_window` and `max_output_tokens`.
9. Set `input_modalities` correctly, for example `["text", "image"]`.
10. Implement tool-call translation in the proxy if the provider has a different
   tool schema.
11. Implement image translation in the proxy if the provider has a different
    multimodal schema.
12. Test CLI text, CLI tool calls, CLI image input, direct proxy calls, and GUI
    model switching.
13. Repair old thread rows in `state_5.sqlite` if they point to the wrong
    provider.

The most important rule: model slugs and provider ids are separate. A model can
appear in the picker but still fail if an existing thread is bound to the wrong
provider.

## Desktop Model Switch Caveat

Codex Desktop can show `Model changed from GPT-5.5 to MiMo-V2.5-Pro` while the
running thread still uses the provider it started with. If that provider is a
ChatGPT/OpenAI account provider, MiMo fails with:

```text
The 'mimo-v2.5-pro' model is not supported when using Codex with a ChatGPT account.
```

That is not a Xiaomi API failure. It means the model slug changed but the thread
provider did not change to `cmp_1777839123484_1`.

Use these helpers to repair the current or target thread:

```powershell
node set-thread-model-provider.cjs --current --model mimo-v2.5-pro
node set-thread-model-provider.cjs --current --model gpt-5.5
node set-thread-model-provider.cjs --thread <thread-id> --model mimo-v2.5-pro
```

For saved-state repair without a restart, use the workspace-aware helper:

```powershell
node switch-codex-gui-model.cjs --model mimo-v2.5-pro
node switch-codex-gui-model.cjs --model gpt-5.5
```

For sidebar-wide GUI sync across all active project groups, use:

```powershell
node switch-codex-gui-model.cjs --model mimo-v2.5-pro --all-project-threads
node switch-codex-gui-model.cjs --model gpt-5.5 --all-project-threads
```

Despite the historical flag name, `--all-project-threads` now updates all
active non-`exec` Codex Desktop GUI threads across every project in the sidebar,
not just the current working folder. Direct `exec` smoke-test rows are skipped
because they are not sidebar chats.

For real GUI usage across providers, use the hard switch helper instead:

```powershell
.\hard-switch-codex-gui-model.ps1 -Model mimo-v2.5-pro
.\hard-switch-codex-gui-model.ps1 -Model gpt-5.5
```

If Desktop keeps writing bad pairings after GUI model switches, keep the watcher
running in a background PowerShell:

```powershell
node watch-codex-provider-drift.cjs
.\start-provider-watch.ps1
```

After repairing a live Desktop thread, fully close and reopen Codex Desktop so
the running session reloads the saved provider binding.

## Global Sync Verification

The original switcher only synchronized threads whose `cwd` matched the current
folder, which meant it touched 4 `mimo` threads and left other sidebar projects
unchanged. The fixed switcher was verified against the local state DB:

```text
allGuiThreads=21
mimoFolderThreads=4
updated_rows=21
updated_scope=all_gui_threads
updated_thread_count=21
```

That means choosing GPT-5.5 now updates every active GUI chat to:

```text
model=gpt-5.5
model_provider=openai
```

## Known Caveats

- Codex Desktop may need a full restart before it reloads the custom catalog.
- `models_cache.json` can be overwritten by Codex refreshes.
- Existing threads can preserve old provider ids even after `config.toml` is
  fixed.
- The current MiMo proxy is a compatibility bridge, so new Codex wire/API
  changes may require proxy updates.
- Direct Xiaomi API limits and model names can change; verify against the
  Xiaomi platform before changing context or output values.
