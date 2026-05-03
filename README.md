# Codex Desktop + MiMo Repair Notes

## Problem Summary

There were three separate issues mixed together:

1. `gpt-5.5` was failing with:

```text
stream disconnected before completion: Mimo upstream returned HTTP 400:
{ "error": { "code": "400", "message": "Not supported model gpt-5.5", "param": "Param Incorrect" } }
```

2. `mimo-v2.5-pro` was not showing in the Codex Desktop GUI model picker.
3. Image input for MiMo was not usable because the local proxy converted images into plain text placeholders.

## Root Causes

### 1. Wrong provider binding in the thread database

Thread `019def7a-30c8-71f1-b952-b9c78722e126` had:

- `model = "gpt-5.5"`
- `model_provider = "cmp_1777839123484_1"`

That meant the GUI was trying to send a GPT model slug through the MiMo proxy provider.

### 2. MiMo catalog path was missing from `config.toml`

The line below had been removed from `C:\Users\water\.codex\config.toml`:

```toml
model_catalog_json = "C:\\Users\\water\\.codex\\mimo-model-catalog.json"
```

Without that path, Codex Desktop only saw the stock model catalog.

### 3. MiMo entry was missing from `models_cache.json`

`C:\Users\water\.codex\mimo-model-catalog.json` still had the `mimo-v2.5-pro` model entry, but `C:\Users\water\.codex\models_cache.json` did not.

That is why MiMo disappeared from the GUI picker.

### 4. Proxy image handling was flattening multimodal input

The local proxy at:

- `C:\Users\water\.codex\mimo-responses-proxy\mimo-responses-proxy.mjs`

was converting:

- `input_image`

into:

- `[image: ...]`

which removed the actual multimodal structure before sending requests upstream.

## What Was Fixed

### 1. Fixed GPT-5.5 provider routing

Updated the `threads` table in:

- `C:\Users\water\.codex\state_5.sqlite`

The broken row now correctly uses:

- `model = "gpt-5.5"`
- `model_provider = "openai"`

This restores real OpenAI routing for that GPT thread.

### 2. Restored the custom model catalog hook

Added back to `C:\Users\water\.codex\config.toml`:

```toml
model_catalog_json = "C:\\Users\\water\\.codex\\mimo-model-catalog.json"
```

This allows Codex Desktop to load the custom MiMo model catalog again.

### 3. Reinserted MiMo into the cache used by the GUI

Copied the `mimo-v2.5-pro` entry from:

- `C:\Users\water\.codex\mimo-model-catalog.json`

into:

- `C:\Users\water\.codex\models_cache.json`

Current MiMo entry:

- `slug = "mimo-v2.5-pro"`
- `display_name = "MiMo-V2.5-Pro"`
- `visibility = "list"`
- `input_modalities = ["text", "image"]`
- `supports_image_detail_original = true`
- `context_window = 1048576`

### 4. Aligned the MiMo profile with the GUI slug

In `C:\Users\water\.codex\config.toml`:

```toml
[profiles.mimo]
model = "mimo-v2.5-pro"
model_provider = "cmp_1777839123484_1"
model_context_window = 1048576
model_max_output_tokens = 131072
```

The proxy still maps GUI-facing slugs to the real upstream MiMo model:

- `mimo-v2.5-pro` -> `mimo-v2-pro`

### 5. Fixed proxy image forwarding

Patched `C:\Users\water\.codex\mimo-responses-proxy\mimo-responses-proxy.mjs` so message content can now be converted into structured chat parts.

Important behavior change:

- text stays text
- images become `image_url` parts
- files still become text placeholders

This means the proxy no longer collapses image inputs into a plain string before forwarding upstream.

## Verification Performed

### Database verification

Confirmed the previously broken thread now shows:

- `id = "019def7a-30c8-71f1-b952-b9c78722e126"`
- `model = "gpt-5.5"`
- `model_provider = "openai"`

Confirmed MiMo threads still show:

- `model = "mimo-v2.5-pro"`
- `model_provider = "cmp_1777839123484_1"`

### Config verification

Confirmed `config.toml` now starts with:

```toml
model_catalog_json = "C:\\Users\\water\\.codex\\mimo-model-catalog.json"
```

### Cache verification

Confirmed `models_cache.json` now contains:

- `slug = "mimo-v2.5-pro"`
- `display_name = "MiMo-V2.5-Pro"`
- `visibility = "list"`
- `input_modalities = ["text", "image"]`
- `supports_image_detail_original = true`

### Proxy verification

Health check:

- `GET http://127.0.0.1:41418/v1/healthz`
- result: proxy listening and targeting Xiaomi upstream

Direct request test through the local proxy:

- `model = "gpt-5.5"`
- endpoint: `http://127.0.0.1:41418/v1/responses`
- result: success
- response model resolved to: `mimo-v2-pro`
- no upstream `Not supported model gpt-5.5` error

Image-path test through the local proxy:

- `model = "mimo-v2.5-pro"`
- request contained both `input_text` and `input_image`
- result: request completed successfully
- result meaning: the proxy accepted structured image content and did not flatten it into a literal `[image: ...]` placeholder

## Important Current State

### GPT threads

For the repaired GPT thread, selecting `gpt-5.5` now uses the real OpenAI provider again.

### MiMo threads

For MiMo threads, selecting `mimo-v2.5-pro` uses the local MiMo proxy provider.

### GUI picker

The files are fixed, but Codex Desktop GUI usually needs a full restart before it reloads:

- `config.toml`
- `models_cache.json`
- `mimo-model-catalog.json`

If MiMo still does not show in the GUI right away, fully close and reopen Codex Desktop.

## Files Changed

- `C:\Users\water\.codex\config.toml`
- `C:\Users\water\.codex\models_cache.json`
- `C:\Users\water\.codex\state_5.sqlite`
- `C:\Users\water\.codex\mimo-responses-proxy\mimo-responses-proxy.mjs`

## Backups Created

- `C:\Users\water\.codex\config.toml.bak-fix-2026-05-03T21-52-19-751Z`
- `C:\Users\water\.codex\models_cache.json.bak-fix-2026-05-03T21-52-19-766Z`
- `C:\Users\water\.codex\mimo-responses-proxy\mimo-responses-proxy.mjs.bak-fix-2026-05-03T21-52-19-767Z`

## Remaining Operational Step

1. Close Codex Desktop completely.
2. Open Codex Desktop again.
3. Check the model picker for `MiMo-V2.5-Pro`.
4. Open the repaired GPT thread and confirm `gpt-5.5` works without reconnect loops.
5. Open or create a MiMo thread and confirm the image button is available.
