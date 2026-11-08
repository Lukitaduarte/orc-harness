# How Orc Harness works

One daemon (`orcd`) on your Mac owns everything that runs: Claude Code sessions, their terminals, worktrees, browsers, emulators and secrets. The app, on the desktop and the phone, only shows what the daemon reports and sends back what you do.

## The big picture

```mermaid
flowchart LR
  subgraph clients["Clients"]
    desk["Orc Harness app<br/>desktop (Flutter)"]
    phone["Orc Harness app<br/>phone (Flutter)"]
  end

  subgraph mac["Your Mac"]
    subgraph orcd["orcd (Rust, LaunchAgent)"]
      remote["remote<br/>iroh QUIC, paired keys only"]
      sock["local socket<br/>~/.orc/orcd.sock"]
      mgr["session manager<br/>PTY + terminal emulation"]
      cat["catalog<br/>skills · MCPs · envs · connectors"]
      plans["plans + kanban<br/>DAG of cards"]
      gates["gates<br/>deploys, merges, pushes wait for you"]
      quota["quotas<br/>5h / 7d per account"]
      db[("orc.db (Turso)<br/>usage · memory")]
      cdp["CDP proxy<br/>who drives the browser"]
      emu["emulators<br/>simctl + AXe · emulator + adb"]
    end
    keychain[("macOS Keychain<br/>env values, daemon key")]
    subgraph sessions["Claude Code sessions (one per account × task)"]
      claude["claude<br/>own CLAUDE_CONFIG_DIR,<br/>generated settings + mcp.json"]
      helpers["orc-statusline · orc-hook<br/>orc-mcp · orc-commit-check"]
    end
    wt["git worktrees<br/>one per card"]
    chrome["headless Chrome<br/>one profile per workspace"]
    devices["iOS simulators<br/>Android emulators"]
  end

  subgraph outside["Outside"]
    anthropic["Anthropic API<br/>(Claude accounts)"]
    connectors["claude.ai connectors<br/>Gmail · Drive · Slack…"]
    github["GitHub (gh)<br/>PRs, merges"]
  end

  desk <-->|"orc/2: frames, grids binary"| remote
  phone <-->|"orc/2 (relay optional)"| remote
  remote --> mgr
  mgr -->|spawns, resumes| claude
  claude --- helpers
  helpers -->|"status, hooks, harness tools"| sock
  sock --> gates
  sock --> quota
  claude -->|"OTLP metrics"| db
  claude --> anthropic
  claude -.->|"allowlisted"| connectors
  claude -->|"Playwright MCP"| cdp --> chrome
  claude -->|"adb / simctl / axe"| devices
  emu --> devices
  mgr --> keychain
  plans -->|"cards run in"| wt
  claude --> wt
  plans -->|"PR status"| github
```

## A session's life

```mermaid
sequenceDiagram
  autonumber
  actor You
  participant App
  participant orcd
  participant claude as claude (session)
  participant hook as orc-hook / orc-mcp

  You->>App: New session (account, folder, profile)
  App->>orcd: create_session
  orcd->>orcd: write settings.json, mcp.json, skills plugin
  orcd->>orcd: read env values from the Keychain
  orcd->>claude: spawn in a PTY (--session-id, --mcp-config, --strict-mcp-config)
  loop every frame (~30 fps)
    claude-->>orcd: terminal output
    orcd-->>App: binary grid diff (changed rows only)
  end
  You->>App: keys
  App->>orcd: input
  orcd->>claude: PTY write
  claude->>hook: PreToolUse (every tool call)
  hook->>orcd: gate?
  alt deploy, merge, push to main, publish
    orcd-->>App: approval request (desktop or phone)
    You->>App: Approve
    App->>orcd: resolve_approval
  end
  orcd-->>hook: allow / deny
  claude->>hook: harness tools (send_message, request_mcp_add, remember…)
  hook->>orcd: McpCall
  You->>App: change profile
  App->>orcd: apply_profile
  orcd->>claude: restart with --resume (same conversation)
```

## From a plan to merged code

```mermaid
flowchart TD
  t["Template<br/>(back + deploy, app + release, spike)"] --> draft["Planning session writes plan.md"]
  draft --> review["You review section by section<br/>comments → answers or amendments"]
  review -->|all sections approved| dag["Loops become cards<br/>(DAG with a model per card)"]
  dag --> pick{"Account with the most<br/>headroom (5h < 90%, 7d < 95%)"}
  pick --> run["Card runs in its own worktree<br/>conventional commits only"]
  run --> pr["PR opened → card in review"]
  pr --> merge{"Merge<br/>(gate: your OK)"}
  merge --> done["Card done; dependents unblock"]
  done --> learn["Learn: card comments<br/>→ proposed skill edits (your OK)"]
```

## What lives where

```mermaid
flowchart LR
  subgraph files["~/.orc (JSON you can edit)"]
    cfg["config.json<br/>accounts, relay, claude path"]
    ws["workspaces.json · catalog.json<br/>projects.json · devices.json"]
    tpl["templates/*.md · plans/&lt;id&gt;/"]
    rt["sessions/ (generated per session)<br/>worktrees/ · browsers/ · accounts/"]
  end
  db[("orc.db<br/>usage, memory")]
  kc[("Keychain: orc-harness<br/>env values, daemon key")]
  app["App: only its pairing<br/>(Application Support)"]
```

Secrets never go in files, plans, logs or the app: env values live in the Keychain, configs carry `${NAME}` references, and the daemon puts the values in a session's environment when it starts it.
