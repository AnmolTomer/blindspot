# What Blindspot shares

When the script finishes, it sends one **report** to `https://gird.ai/api/check`. If you use the menu at the end, it sends one more small **actions** event when you quit. Both go over https in the background, with a 5-second timeout. If they fail, nothing happens and nothing is retried.

Turn it all off with `--offline`, or set `DO_NOT_TRACK=1`.

Everything is built in one place near the end of [`gird-check.sh`](gird-check.sh), so you can read exactly what goes. Every field is a number or comes from a fixed list or a strict pattern. The server applies the same rules and drops anything else.

## Never sent

File paths, keys, key fragments, usernames, emails, hostnames, IP addresses or your raw hardware ID.

## The report

| Field | Example | What it is |
|---|---|---|
| `v`, `kind` | `"1"`, `"report"` | Format version and event type |
| `run_id` | `"4b78c51d64d15aa0"` | Random for each run. Links a report to its actions event |
| `device_id` | 64 hex characters | One-way SHA-256 of your Mac's hardware UUID (Linux: `/etc/machine-id`), salted with `gird-check-v1:`. Lets us count repeat runs. It can't be turned back into the hardware ID |
| `script` | `"1"` | Script version |
| `os`, `arch`, `model` | `"macOS 26.4"`, `"arm64"`, `"MacBookPro18,1"` | macOS version, processor type, Mac model identifier |
| `terminal`, `tmux` | `"iterm2"`, `0` | Terminal app, from a fixed list, and whether tmux is running |
| `shell`, `bash` | `"zsh"`, `3` | Your login shell, from a fixed list, and the bash major version running the script |
| `lang` | `"en_IN"` | Language and region setting |
| `via` | `"none"` | `claude-code` when the script runs inside Claude Code |
| `grade`, `score` | `"C"`, `64` | The result |
| `agents`, `agents_idle` | `["claude-code","codex"]`, `1` | Agents installed, from a fixed list, and how many weren't used in 30 days |
| `mcp_servers`, `mcp_configs`, `mcp_token_files` | `6`, `3`, `1` | MCP servers, config files with servers, and configs with a token written in |
| `key_files`, `key_providers`, `history_keys` | `4`, `["anthropic","aws"]`, `1` | Files with keys in plain text, which providers from a fixed list, and how many shell history files hold keys |
| `env_files` | `12` | `.env` files scanned |
| `allow_list_files`, `allow_list_keys`, `allow_list_npm` | `2`, `1`, `1` | Claude Code settings files, how many hold a saved command with a key, and how many an npm publish would ship |
| `login_files` | `["aws","ssh"]` | Kinds of login files present, from a fixed list |
| `ssh_keys`, `ssh_no_passphrase` | `2`, `1` | SSH private keys, and how many have no passphrase |
| `python_envs`, `litellm_installed`, `litellm_found` | `6`, `2`, `0` | Python environments checked, LiteLLM installs, and whether 1.107.0 malware signs were found |
| `opencode`, `railway` | `1`, `0` | Whether the OpenCode and Railway tools are installed |
| `files_found`, `scan_seconds`, `all_folders` | `140`, `18`, `0` | Candidate files found, scan time, and whether `--all` was used |
| `game_played`, `game_best`, `results_wait_seconds` | `1`, `150`, `40` | Whether you played GIRD Runner, a rounded best score, and how long you kept playing after the results were ready |

## The actions event

| Field | What it is |
|---|---|
| `run_id`, `device_id` | Same as the report |
| `saved`, `card`, `argus` | Whether you saved the report, opened your share card or opened the Argus download page |
| `menu_seconds` | Time spent in the menu |

## On our side

The server stores each event with the time it arrived and the two-letter country Cloudflare derives from the connection. It doesn't store your IP address. Events are kept for 24 months, then deleted. We use them for aggregate statistics and case studies, and never publish figures about a group smaller than 20 devices. The privacy notice is at [gird.ai/privacy](https://gird.ai/privacy).

## Deleting your data

Work out your device ID on a Mac:

```sh
printf 'gird-check-v1:%s' "$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/ {print $4}')" | shasum -a 256
```

On Linux, replace the `ioreg` part with `cat /etc/machine-id`. Email the hash to [hello@gird.ai](mailto:hello@gird.ai) and we'll delete every event with it.
