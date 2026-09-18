# Tools and MCP inventory

This inventory is derived from the configured config.toml at
C:\Users\DELL\Downloads\config.toml. It records names, purpose,
prerequisites and authentication requirements without copying credentials.
An enabled entry means that Codex may try to start or call it; it does not prove
that the process is installed, reachable or authenticated.

## Minimum tools for this repository

| Tool or service | Needed for | Local requirements | Authentication |
| --- | --- | --- | --- |
| Git and the GitHub remote | Commit and push source, reports and APK metadata | Git; a configured remote and credential helper | GitHub credential is required for push, but it is not configured as an MCP in config.toml |
| Flutter, Dart, Android SDK and Gradle | Build and test the Android app | Flutter SDK, Android platform/build tools, Java, accepted SDK licenses | No cloud account authentication |
| adb / mcp_servers.adb | Install APKs, collect logs and inspect a phone | Android platform-tools, USB debugging, RSA approval on the phone | No cloud authentication; the physical device must authorize the computer |
| mcp_servers.mobile-device | Optional structured mobile-device actions | Node/npm and the mobile-device-mcp package; an ADB-visible device | No cloud authentication; device authorization still applies |
| Roboflow inference | Run projec-mutta/2 model inference and evaluate detections | Existing gateway or a server-side Roboflow client | Roboflow workspace/API authentication is required for private model operations; never place the key in the APK |
| Cloudflare Worker/Wrangler | Deploy or inspect the gateway, bindings and observability | Wrangler and network access | Cloudflare account OAuth or API-token authentication is required for deployment and private account operations |
| Python/OpenCV backend | Local hybrid research, geometry and quality analysis | The repository Python runtime and vision dependencies | No account authentication for local execution; this is not an MCP in the config |
| mcp_servers.codebase-memory / codebase-memory-mcp | Optional repository indexing and context retrieval | The configured local executable and an indexed checkout | No external account authentication is declared |

The minimum production-counting path is therefore the app toolchain plus ADB
for device work, Roboflow authentication for model inference, and Cloudflare
authentication only when deploying or reading private Worker resources. The
other configured MCPs are convenience or integration tools, not counting
dependencies.

## MCP servers configured in config.toml

| Configured MCP | Transport / command | What it provides | What it requires | Auth requirement |
| --- | --- | --- | --- | --- |
| codebase-memory | Local codebase-memory-mcp.exe | Repository memory/index operations | Installed executable and readable checkout | No external auth is declared |
| agent-reach | Local Python module agent_reach.integrations.mcp_server | Agent-reach integrations | Python 3.10 path and the installed package | Provider-specific credentials may be needed; none are declared in this config |
| codebase-map | Local codebase-memory-mcp.exe | Code map/index operations | Installed executable and indexed checkout | No external auth is declared |
| codebase-map.tools.check_index_coverage | Tool policy approval_mode = approve | Index-coverage check | User approval when the tool requests it | Approval is a safety gate, not authentication |
| codebase-memory-mcp | Local codebase-memory-mcp.exe | Alternate memory-server entry | Installed executable | No external auth is declared |
| mobile-device | npx -y mobile-device-mcp | Mobile-device control | Node/npm, package download, ADB-visible device | No cloud auth is declared; device authorization is required |
| adb | Local Node adb-mcp server | ADB commands and device inspection | Node, adb-mcp package and Android platform-tools | No cloud auth; the device must be authorized by USB debugging |
| node_repl | Local Codex Node REPL | Browser/Codex-side JavaScript automation | Configured Node runtime, trusted paths and named pipes | No separate provider credential is declared; website sessions may require sign-in |
| cloudflare | Remote https://mcp.cloudflare.com/mcp | Cloudflare account, Worker and deployment operations | Network access and a Cloudflare account | Required for private account, Worker and deployment operations; config contains no token value |
| cloudflare-docs | Remote https://docs.mcp.cloudflare.com/mcp | Cloudflare documentation lookup | Network access | Public documentation may work without account auth; the config does not declare a credential |
| cloudflare-bindings | Remote https://bindings.mcp.cloudflare.com/mcp | Worker binding management | Cloudflare account/project access | Required for private bindings; no credential is declared here |
| cloudflare-builds | Remote https://builds.mcp.cloudflare.com/mcp | Cloudflare build/deployment operations | Cloudflare account/project access | Required for private builds; no credential is declared here |
| cloudflare-observability | Remote https://observability.mcp.cloudflare.com/mcp | Logs, metrics and Worker observability | Cloudflare account/project access | Required for private telemetry; no credential is declared here |
| ai-cli | Local ai-cli-mcp.cmd | AI CLI-backed tools | Installed command and its provider configuration | Conditional; provider auth is outside this config |
| apify | npx -y @apify/actors-mcp-server | Apify actors and datasets | Node/npm and the package | Required for Apify operations. APIFY_TOKEN is configured, but its value is intentionally omitted and must never be committed |
| composio | Remote https://connect.composio.dev/mcp | Connected third-party apps | Network access and a Composio connection | Required for connected-app operations; no credential is declared here |
| whatsapp | npx -y whatsapp-mcp and enabled = true | Optional WhatsApp web-bridge automation | Node/npm, package and QR/session bridge | QR/session authentication is required; this is optional and unrelated to tray counting |

## Enabled plugins and their role

The config also enables these plugins:

| Plugin | Role in this project | Separate auth |
| --- | --- | --- |
| codex-app-tools | Codex task, workspace and app integration | Uses the Codex app session; no repository secret |
| visualize | Interactive or explanatory visuals | No separate auth for local/in-chat visuals |
| documents, pdf, spreadsheets, presentations, template-creator | Artifact creation and verification | No separate auth for local files; connected cloud destinations may ask for their own sign-in |
| roboflow | Roboflow inference, data and training workflows | Roboflow account/API authentication for private workspaces |
| ponytail | Code-simplification workflow | No external auth |
| browser, computer-use, unified-computer-use | Browser or desktop UI control | The target website/app may require its own user session; this config does not contain that credential |
| sites | Site preview/hosting workflows | Hosting account authentication is required when publishing; not needed for this repository's Worker |

## Authentication and secret handling

- The config explicitly contains an APIFY_TOKEN assignment. This document
  deliberately does not reproduce the token. Move provider tokens to a secret
  store or environment injection and rotate any token that has been exposed.
- Cloudflare and Roboflow credentials belong in their respective CLI/session
  stores or server-side Worker secrets. They must not be placed in Flutter
  assets, source code, logs, reports or this file.
- ADB “authentication” means the Android RSA authorization prompt, not a cloud
  API key. A USB cable is insufficient until adb devices -l shows an authorized
  device serial.
- The config does not prove current auth for any remote MCP. Validate with the
  service's least-privilege health/readiness command before deployment or data
  collection.

## Project-specific recommendation

For the next live counting test, use only Flutter/Android tooling, adb, the
existing Cloudflare gateway and the server-side Roboflow model. Add
codebase-memory or browser/UI MCPs only when they shorten a concrete task.
Do not make WhatsApp, Apify, Composio, Agent Reach or document plugins
dependencies of the counting path.
