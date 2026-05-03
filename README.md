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
- The local MiMo proxy accepts direct text, image-shaped, and function-call
  requests.
- The Codex config includes the custom model catalog hook so MiMo can appear in
  Desktop GUI model lists.
- The active GUI thread was repaired from `gpt-5.5/openai` to
  `mimo-v2.5-pro/cmp_1777839123484_1` after Desktop tried to send MiMo through
  the ChatGPT-account provider.
- The active GUI thread repair was verified in `state_5.sqlite`; a full Codex
  Desktop close/reopen is still required so the running GUI reloads that saved
  provider binding.
- A later GUI 400 was caused by the same active thread drifting back to
  `gpt-5.5/cmp_1777839123484_1`. It was repaired to `gpt-5.5/openai` with
  `node set-thread-model-provider.cjs --current --model gpt-5.5`.

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

- `repair-codex-mimo.cjs` repairs config, cache, and proxy image handling.
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

1. Fully close Codex Desktop.
2. Confirm the proxy is running on `127.0.0.1:41418`.
3. Reopen Codex Desktop.
4. Open the model picker.
5. Confirm `gpt-5.5` is available and uses the OpenAI provider.
6. Confirm `MiMo-V2.5-Pro` appears.
7. Create a new MiMo thread and check that image upload is available.
8. In old GPT threads, verify the thread is not still bound to
   `cmp_1777839123484_1`.

If the GUI reconnects five times and shows `Not supported model gpt-5.5`, the
active thread is still routed to the MiMo provider. Run:

```powershell
node update-gpt-providers.cjs
```

Then restart Codex Desktop.

## Adding Any Custom Model To Codex

Use this checklist when adding another provider/model:

1. Create or reuse a local proxy if the provider does not natively support the
   exact Codex wire API.
2. Add a `[model_providers.<id>]` entry in `config.toml`.
3. Add a `[profiles.<name>]` entry pointing to the provider and model slug.
4. Add the model to a custom catalog JSON.
5. Point `model_catalog_json` at that custom catalog.
6. Mirror the model entry into `models_cache.json` if the GUI does not show it.
7. Set realistic `context_window` and `max_output_tokens`.
8. Set `input_modalities` correctly, for example `["text", "image"]`.
9. Implement tool-call translation in the proxy if the provider has a different
   tool schema.
10. Implement image translation in the proxy if the provider has a different
    multimodal schema.
11. Test CLI text, CLI tool calls, CLI image input, direct proxy calls, and GUI
    model switching.
12. Repair old thread rows in `state_5.sqlite` if they point to the wrong
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

Use this helper to repair the current or target thread:

```powershell
node set-thread-model-provider.cjs --current --model mimo-v2.5-pro
node set-thread-model-provider.cjs --current --model gpt-5.5
node set-thread-model-provider.cjs --thread <thread-id> --model mimo-v2.5-pro
```

After repairing a live Desktop thread, fully close and reopen Codex Desktop so
the running session reloads the saved provider binding.

## Known Caveats

- Codex Desktop may need a full restart before it reloads the custom catalog.
- `models_cache.json` can be overwritten by Codex refreshes.
- Existing threads can preserve old provider ids even after `config.toml` is
  fixed.
- The current MiMo proxy is a compatibility bridge, so new Codex wire/API
  changes may require proxy updates.
- Direct Xiaomi API limits and model names can change; verify against the
  Xiaomi platform before changing context or output values.
