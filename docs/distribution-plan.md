# Plan: make wf2s something a friend can set up and run

Written for a **new session** to pick up cold. Read this file, then `README.md` and `docs/game-data-sources.md`.
Last updated 2026-10-17 on branch `settings-ui`.

## Goal

A friend who plays Wreckfest 2 can host their own dedicated server with this project. After downloading it, the only things
they do by hand are:

1. type their passwords (a server password, and a Steam login unless step 2 of "Decisions" removes it), and
2. set up their router (a fixed local address for the PC, and forward **UDP 30100**).

Everything else is automatic or a single click: install, config, firewall, start/stop, editing rotations and cups from the
browser page. The router can never be automated, so the page must make that step as easy as possible and tell them honestly
whether it worked.

## Where things stand (what already exists)

Working and tested on the owner's PC only (Windows 11, PowerShell 5.1):

- `scripts/install.ps1` / `update.ps1` (SteamCMD, app **3519390**, needs `-SteamUser`: anonymous login is refused),
  `set-password.ps1`, `firewall.ps1` (admin), `start.ps1 [-Instance] [-Local]`.
- The settings page: `scripts/ui.ps1` serves `ui/index.html` on `http://127.0.0.1:30180`. Tabs: Global defaults, Rotation, Cups,
  Password. Header: Apply now, Start/Stop server, status. Start/Stop use `scripts/server.ps1`; live apply uses
  `scripts/apply.ps1` + `scripts/console.ps1` (types commands into the server's console).
- Generated-from-template files (gitignored): `default_loop.becl`, `server_config.scnf`, `server_cup_config.ccnl`,
  `cups-generated/`.
- `docs/game-data-sources.md` records every game fact, where it came from, and how sure we are. **Read its "Not verified" list.**

Not done / not true yet:

- **Nothing is committed.** All of the above is uncommitted work on branch `settings-ui` (see "First steps").
- Never run on a machine other than the owner's. No clean-machine test. No automated tests or CI. No `LICENSE`.
- `instances/main` holds the owner's own server (name, cups, rotation, `settings.json`, `cups-backup/`). It must not ship.
- No launcher, no first-run setup, no packaging.

## Decisions to make with the owner before building

1. **Name of the first-run path.** One double-click launcher (`Start.cmd`) that runs the setup with `-ExecutionPolicy Bypass`.
   (Without it PowerShell blocks `.ps1` files on most PCs.) Recommended.
2. **Can we avoid typing Steam credentials?** If the "Wreckfest 2 Dedicated Server" tool is installable from a Steam library,
   setup could use that copy (Steam keeps it updated) instead of SteamCMD. **Unverified: check on a PC that owns the game**
   (Library > Tools, or `steam://install/3519390`). If yes: add a setting for the server folder (today the scripts assume `.\server`)
   and make SteamCMD the fallback. If no: SteamCMD stays, with Steam Guard prompts explained in the UI.
3. **Admin Steam ID.** Ask for it (profile URL or number), or offer to read it from the local Steam install with the user's consent.
   Never read or store Steam passwords or tokens.
4. **Distribution format.** A zip from a GitHub release (recommended) vs. "git clone". Needs a repo decision (the owner's rules say
   `wf2s` is *not* one of the auto-merge repos: open the PR, leave it open, tell the owner).
5. **License.** The owner's standard is AGPL-3.0 (`KVG_Standards`); confirm, then add `LICENSE`.
6. **Remote editing** (other people using the page from other PCs) is a separate, later project. Plan agreed in conversation:
   Tailscale node sharing + a "listen on" setting + a per-person key with roles + a change log. Do not start it here.

## Work breakdown (suggested order)

### 1. Clean up and commit what exists (first)
- Review the uncommitted tree. It contains work from **two sessions** (the page, cups, password history, `defaults/`, and this
  session's apply / start-stop / layered defaults / cup-generation work). Do not discard anything.
- Remove personal data from the tree before any release: `instances/main/cups-backup/`, personal `settings.json`, personal cups.
  Keep the owner's instance working locally (move it out of the tracked paths, or gitignore it), do **not** delete it.
- Commit on `settings-ui`, open a PR, leave it open (repo is not in the owner's auto-merge list). Check the PR state first
  (`gh pr view`) as the owner's global rules require.

### 2. A clean default instance
- Create `instances/default/` (or a template folder copied on first run): the game's own default rotation (44 events, readable from
  `server/data/property/settings/default_event_rotation.becl`; see `Get-WfTrackModes` for how it is parsed), the six shipped cups
  (`defaults/server_cup_config.ccnl`), neutral server name/description, no password, no admins.
- Setup copies it to the friend's own instance name, so updates to the app never overwrite their config.

### 3. Launcher and first-run setup
- `Start.cmd` (double-click): runs `scripts/setup.ps1` the first time, then starts the settings page and opens the browser.
- `setup.ps1` steps, each with a plain-language message and a way to retry:
  1. check Windows/PowerShell, disk space, that the game server isn't already installed;
  2. get the game server (decision 2), showing a progress note (it is a large download);
  3. ask for server name, server password, admin Steam ID;
  4. write the instance from the default template; run the firewall step (self-elevate once, explain the UAC prompt);
  5. show the router checklist (below) and finish by opening the page.
- Keep PowerShell-only: no extra installs. Use `$PSScriptRoot` paths only (no `C:\Users\...` anywhere).
- Make `install.ps1`, `update.ps1`, `start.ps1` safe to re-run.

### 4. Make the router step easy (inside the page)
- A "Network" panel showing: this PC's local address, the port/protocol to forward (UDP 30100), and a one-line plain explanation of a
  fixed address (DHCP reservation) vs. port forwarding.
- Show the game's own result: the server log prints "Server is reachable from public network" or not, and
  "Router port forwarding using UPnP unavailable" when UPnP fails (read it with `scripts/console.ps1`).
- Warn about a shared public address (CGNAT): the server prints the address it advertises; a private-range address means no forward
  will work. Link to simple help text. Be honest that no software can fix this.
- No router-brand-specific instructions; a short generic guide plus "search your router model + port forwarding".

### 5. Game version and update handling
- Show the installed Steam build id (`server/steamapps/appmanifest_3519390.acf`) and compare with the build the tool was last checked
  against (`docs/game-data-sources.md`); warn when different (the reverse-engineered parts may have changed).
- An "Update server" button: stop (with confirmation), run `update.ps1`, start. Explain that clients and server must be on the same
  version, otherwise players are refused (the "300E checksum mismatch" family).
- Never write into the game's `data` folder (see the checksum lesson in `docs/game-data-sources.md`).

### 6. Packaging and docs
- A release zip (GitHub Action) containing scripts, `ui/`, `defaults/`, `docs/`, the clean default instance, `Start.cmd`, `LICENSE`.
  **Never** include `server/`, `steamcmd/`, `*.local`, or any personal instance.
- `README` quick start for non-technical people, with screenshots: download, double-click, answer five questions, router steps.
- Update `README.md` / `docs/game-data-sources.md`; link `KVG_Standards` per the owner's standards.

### 7. Testing (the part this session could not do)
- **Clean-machine test** on a fresh Windows 10/11 VM or a friend's PC: follow only the README. Record every stumble.
- Test with a fresh Steam account state (Steam Guard prompt) and with no game client installed.
- Add basic automated checks: parse all `.ps1`, run the generators on sample data, run `game-data-report.ps1`, CI on push.
- Confirm a **real player can join** (not yet seen).

## Acceptance criteria

- On a clean Windows PC with a Steam account that owns the game, someone who only follows the README gets a joinable server with
  no terminal use beyond double-clicking, typing passwords, one UAC prompt, and doing their router steps.
- Re-running setup never overwrites an existing instance; updating the app never touches their config.
- No file from the owner's personal setup is in the release; no game files are redistributed.
- The page tells the host plainly whether the server is reachable from outside and what to do if not.

## Risks and things to be honest about

- **Router/CGNAT** is outside our control. Some people simply can't host without a VPN or a rented host.
- **The game is in Early Access.** Reverse-engineered formats and the string tables can change per build; the page must degrade to plain
  ids (it does) and warn on a build change.
- **Steam login** may be unavoidable (decision 2).
- **Windows SmartScreen** will warn on a downloaded launcher; document the click. Code signing costs money.
- Only tested with bots, on one PC, one Windows version, PowerShell 5.1.

## Rules and gotchas for whoever picks this up

- **Never touch the owner's real server or game client.** Tests use a throwaway instance and `start.ps1 -Local` / `--local-server`
  on another port (e.g. 30199), and only stop a process whose command line contains the test folder name. The real server runs with
  `--save-dir=...\instances\main`; the game client is the `Wreckfest2.exe` with no arguments (in the Steam folder).
- **Never touch the `P:` drive** (owner's global rule).
- **Use a separate browser tab for testing**, not the pane the owner is looking at; a forced reload discards their unsaved edits
  (this lost a cup entry once).
- Windows PowerShell 5.1 quirks that bit us: `Get-Content` reads UTF-8 as ANSI (use `Read-WfJson`), `ConvertTo-Json` formatting
  (use `Write-WfJson`), an empty string argument to a native exe is dropped, `Start-Process` arguments need their own quotes.
- Settings layers are page logic: event own value > cup > Global default > file. The game only sees merged files.
- The page binds to `127.0.0.1` and rejects other hosts; changing writes need the `X-WF-UI` header. Keep both.
- Git: the owner's rules say verify PR state before pushing, never push to the default branch, `wf2s` is not an auto-merge repo.
