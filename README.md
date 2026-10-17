# wf2s: Wreckfest 2 dedicated server

Config-as-code for a Windows-hosted Wreckfest 2 dedicated server (Steam app **3519390**).
Game binaries are not committed; the config, event rotations and setup scripts are, so the
whole server can be rebuilt on another machine in a few minutes.

- Secrets (server password, admin SteamIDs) stay on the host and are injected at start time.
- Everything is plain PowerShell, with no dependencies beyond Windows and a Steam account that owns Wreckfest 2.

## Requirements
- Windows 10/11 and PowerShell 5.1+
- A Steam account that **owns Wreckfest 2**. Anonymous SteamCMD login is refused for this app
  ("Missing configuration"), so `install.ps1` needs `-SteamUser`.
- For friends over the internet: UDP **30100** forwarded on your router to the host PC
  (see [Networking](#networking)).

## Quick start
```powershell
git clone https://github.com/gerp93/wf2s.git ; cd wf2s

# 1. Install SteamCMD + the dedicated server into ./server (prompts for Steam password / Steam Guard)
.\scripts\install.ps1 -SteamUser YOUR_STEAM_USERNAME

# 2. Set the server password (stored in instances\main\password.local, gitignored)
.\scripts\set-password.ps1

# 3. Make yourself admin: put your SteamID64 in instances\main\admins.local (one per line, gitignored)

# 4. Open the game port in Windows Firewall (elevated PowerShell, once)
.\scripts\firewall.ps1

# 5. Run it
.\scripts\start.ps1 -Instance main
```
The server then appears in the game's multiplayer server browser (search by name). A password-protected
server shows a lock icon.

## Scripts
| Script | What it does |
|---|---|
| `scripts/install.ps1 [-SteamUser name]` | Downloads SteamCMD if missing, installs or updates the server into `./server`. |
| `scripts/update.ps1` | Re-runs the install to pick up game patches. Stop the server first. |
| `scripts/set-password.ps1 [-Instance name]` | Prompts for the password and writes `password.local`. |
| `scripts/start.ps1 [-Instance name] [-Local]` | Generates local config files if needed, then launches the server with `--save-dir instances\<name>`. `-Local` starts the game's local-only mode (`--local-server`) instead of the online one; it is for testing. |
| `scripts/firewall.ps1 [-Ports 30100,...]` | Adds inbound UDP allow rules. Run elevated. |
| `scripts/ui.ps1 [-Instance name] [-Port 30180]` | Local settings page (bots, damage, laps, server name, ...) at `http://127.0.0.1:30180`. See [Settings page](#settings-page). |
| `scripts/console.ps1 -ProcessId <pid> [-Send 'cmd'] [-Read n]` | Types commands into a running server's console and prints its screen. Used by "Apply now". |
| `scripts/game-data-report.ps1` | Re-reads the game facts the page relies on (names, lists, flags, limits) from the installed game. See [docs/game-data-sources.md](docs/game-data-sources.md). |
| `scripts/update-visual-assault-css.ps1 <tag>` | Re-vendors the settings page theme from a VisualAssault tag. |

## Layout
```
scripts/                         setup and run scripts
instances/<name>/                one folder per server (this is the --save-dir)
  server_config.template.scnf    TRACKED: name, description, port, event loop, timers, ban settings
  default_loop.template.becl     TRACKED: event rotation (tracks, modes, laps, bots, cars)
  settings.json                  TRACKED: global overrides saved by the settings page (optional)
  cups/<slug>.becl               TRACKED: custom cup rotations made on the Cups tab (optional)
  server_cup_config.template.ccnl TRACKED: cup definitions and points (the page edits this one)
  server_cup_config.ccnl         generated each start (template + cups\*.becl), gitignored: the cup list the game reads
  cups-generated/<slug>.becl     generated each start from cups\<slug>.becl, gitignored: each custom cup's events for the game
  server_privilege.template.sprv TRACKED: empty roles/bans skeleton
  server_config.scnf             generated each start (template + settings.json + password.local), gitignored
  default_loop.becl              generated each start (template + settings.json), gitignored
  server_privilege.sprv          created once from template + admins.local; roles/bans change at runtime, gitignored
  password.local                 server password, gitignored
  admins.local                   admin SteamID64s, one per line, gitignored
ui/                              settings page (index.html, vendored VisualAssault theme)
server/  steamcmd/               gitignored, recreated by install.ps1
```
Edit the **template** files, not the generated ones. They are JSON despite the `.scnf`/`.becl` extensions.

## Configuration
- **Name, description, port, timers:** `server_config.template.scnf`. Changes take effect on the next start.
- **Event rotation:** `default_loop.template.becl` is a list of events (`start.ps1` generates `default_loop.becl`
  from it, so edit the template). Each event sets a `level id` (track), a
  `game mode id`, a weather file, rules (`laps`, `time limit` in minutes, `max number of participants`),
  a `bot count` and an optional `car restriction` list. The server runs them in order, loops, and lets
  players vote between events. The loop is chosen by `event loop name` in the server config.
- **Cups:** `server_cup_config.template.ccnl` defines points-based cups (the file the game reads, `server_cup_config.ccnl`, is generated from it). Each cup points at its own rotation
  file. Default loops ship under `server/data/property/settings/`.
- **Admins:** add SteamID64s to `admins.local`. This only seeds the privilege file on its first creation.
  Afterwards use the server console: `role STEAMID64,admin`. To reseed, delete `server_privilege.sprv`.
- **Console:** type `help` in the server console. The server binary includes `eventloop`
  (`enable`, `disable`, `load <name>`, `reload`, `next`, `list`, `create`, `save`) and `cup`
  (`reload`, `start <index>`) commands.

## Settings page
```powershell
.\scripts\ui.ps1        # then open http://127.0.0.1:30180
```
A local page (PowerShell only, no extra dependencies) with three tabs. The server does not need to be stopped to edit,
but changes apply the **next time it starts**. The page does not start or stop the server; it shows whether
`Wreckfest2.exe` is running.

- **Rotation:** every track the game ships is listed, with its friendly name ("Crash Canyon - Waypoint Race") read from
  the game's files. The track itself is fixed. Each row has an **On** checkbox: untick it to skip that track without
  deleting it (the entry stays in `default_loop.template.becl` with `"disabled": true` and is left out of the file the
  game reads). You can reorder with ▲▼ and set mode, weather, laps, time limit, bots and damage preset, and under `⋯`
  the AI set, max players, teams, car reset delay, collecting order, flags and car restriction. Tracks the game ships that
  your file didn't have yet appear switched off, with the game's own default mode for that track.
  - **Fixed drop-downs** (the full list is known, so no free text): weather (the game's weather files, with their names),
    collecting order, damage preset (the game's damage list), and the car types in a restriction (the game's vehicle
    folders, with names such as "Popper (car10)").
  - **Game mode** is a fixed drop-down of the four ids the game's own events use: `bangerrace`, `waypointrace`,
    `suiciderace` and `deathmatch` (the game's "demolition derby"). The server rejects an unknown mode id for an event
    ("Invalid game mode id"), so there is no free text. The game's binary hints at more modes (a Tag mode, a Time Trial
    category) but their ids are inside the encrypted game archive, so they are not offered.
  - **AI set** is a drop-down with **Other…** (the list is what could be found, not provably complete). Other… turns the
    field into a text box with a ▾ button to go back to the list.
  - A value already in your config that isn't in a list is kept and marked "not in list".
- **Cups:** name, description, start order (drop-down: `random`, `points`, `points reversed`, `last race`,
  `last race reversed`; `last race` comes from the game's string table and is not used by the shipped cups), points, bonus points, last race multiplier, flags and car restriction per
  cup; add, **clone**, delete and reorder cups. **Clone** asks for a new name and makes a custom copy of the cup next to it: all its
  settings, plus its own copy of the events (a built-in cup's copy starts with the game's tracks for that cup). The copy is not
  built-in, so it can be deleted (its events file goes with it). The events lists have **Select all** / **Select none**;
  Save waits until at least one event is on. A cup's panel title follows the Name box as you type. Saves to `server_cup_config.ccnl`. The game's own cup rotations are binary files and
  can't be edited, so **Customize events** makes your own copy for that cup (starting as a copy of the main rotation) in
  `instances/<name>/cups/<slug>.becl`. At every start (and on **Apply now**) the cup list and each custom cup's events are
  **generated into the instance folder** (`server_cup_config.ccnl`, `cups-generated/<slug>.becl`), and the cup list points at
  `cups-generated/<slug>.becl`. Never into the game's own `data` folder: see "Custom cups" below.
- **Global defaults** (the first tab): tick a setting (bots, AI set, damage, laps, time limit, max players, car reset delay, rule
  flags, server name, description, countdown, voting time) to make it the **default** for every event of the main rotation
  **and of your own cups**. Saved to `settings.json`. Settings work in layers, and the most specific one wins:
  1. **the event's own value** (an event that has *overridden* the field),
  2. **the cup's own setting** (the checkboxes on a cup; cup events only),
  3. **the Global default**,
  4. otherwise whatever the event's file says.

  On the Rotation and Cups tabs a field that follows a default shows **Global** (or **Cup**). Click it to **override it for that
  event only** (it starts from the default's value); an overridden field has a small **↩** to follow the default again. The
  event records which fields it owns in an `"overrides"` list in its entry, which the game never sees. Existing events own
  nothing, so every event follows Global exactly as before until you override one. The game's own built-in cups are binary
  files, so Global cannot reach them; only cups you customized follow it. Server-wide settings (name, description, countdown, voting)
  are not per event, so they are plain settings with no override.
- **Rule flags** (Rotation `⋯` panel per event, and as one Global default): checkboxes for **Car resets off**, **Tuning off**,
  **Upgrades off** and **Wrong-way limiter off**, written the way the server needs them (`name | name`). When car resets are
  off *in the flags that win for an event* (its own, else the cup/Global default), that event's car reset delay is grayed out;
  a Global car reset delay default is unticked and grayed out while the Global flags turn resets off.
- **Password tab:** a box that saves the server password to `password.local` (the same file `set-password.ps1` writes). It
  can't set an empty password. The current password stays hidden until you click **Show**, which hides it again after 15
  seconds. Below that is a history of when it was changed (`password-history.local`, gitignored: dates and where it was
  changed from, never the password).

### Start and stop the server from the page
The **Start server** / **Stop server** button in the header (next to the status badge) does what Hardpoint's mount does, so
you can use either.
- **Start** runs `scripts\start.ps1 -Instance <name>` (the same command Hardpoint runs) in its own minimized PowerShell
  window, then waits for the server to report "Server Started". It refuses with a clear message if the game isn't installed or
  no password is set. Start-up takes roughly 5 to 20 seconds.
- **Stop** asks first (everyone connected is disconnected), then types the server's own `shutdown` command ("graceful
  shutdown"; the process exits in about 2 seconds). If that does not work within 20 seconds the page offers a **force stop**,
  which ends only this instance's `Wreckfest2.exe`.
- The page finds "its" server by its `--save-dir`, so it never starts, stops or touches another instance. A server started
  from Hardpoint or a terminal shows up and can be stopped from the page too.
- If you also use Hardpoint to run `ui.ps1`, note that Hardpoint's own Stop kills every process started from the repo folder,
  which includes the settings page.
- Tested with `-LocalServer` (`ui.ps1 -LocalServer` makes the page's Start use the game's local-only mode) against a
  throwaway instance on its own port, with bots only: start, a second start, graceful stop, force stop, and the
  no-password error. It has not been run against your real online server.

### Apply now (live, no restart)
The **Apply now** button (top right, enabled when the page sees your server running and nothing is unsaved) pushes the
saved rotation and cups to the **running** server. It regenerates the files, then types `eventloop reload` and
`cup reload` into the server's console (`scripts/console.ps1`), because the server has no network remote control. Then it
jumps back to the track that was running with `eventloop select`.
- Players stay on the server and nothing needs a restart, but the reload **restarts the current track** (a race in
  progress restarts) and briefly loads the first track on the way. Apply between races.
- `cup reload` is refused by the server while a cup is running; the page tells you and you can apply again afterwards.
- Name, password, port and ban settings are only read at startup and still need a restart.
- It finds the server by its `--save-dir`, so it only ever touches the instance the page is for. The server needs a console
  window (it has one when started with `start.ps1`, including from Hardpoint).
- Tested against a local-only test server (`--local-server`, its own folder and port) with bots only. Not tested with real
  players connected.

Things to know:
- `start.ps1` regenerates `default_loop.becl` every start, so edits made with the server's `eventloop save` command are
  overwritten. Permanent loop changes belong in the template (or on the Rotation tab).
- Names and lists are read from the installed game's own files (event, weather, AI set and damage files), so they need
  `install.ps1` to have run. Without the game installed the page falls back to plain ids. The damage presets are the three
  entries in the game's damage list; check that the setting takes effect in a race, as I have not run the server with them.
- **Custom cups (what works and what does not).** A custom cup's events are a JSON file, like the main rotation. Tested on a
  local test server: a JSON events file in the **instance (save) folder** is accepted and the cup runs (`cup start`), but the
  same file copied into the game's own `server\data\property\settings\cup` folder is rejected ("has no valid events"), and
  **any extra file in the game's `data` folder changes the data checksum**, so players are refused with "Failed to connect
  (300E) Server checksum mismatch" (the only difference between a client's and this server's `data\property` files was our
  `wf2s_*.becl` files). So nothing is ever written to the game's `data` folder, and `start.ps1` removes leftovers from the old
  approach. If you get a checksum mismatch, check that `server\data\property\settings\cup` has no `wf2s_*.becl` files.
  I could not test an actual client joining; the cause is established by the file comparison and the server's own rejection.
- **AI set paths.** The server accepts the built-in class sets (`career/ai-class-all.aist`, `-a`, `-b`, `-c`, `-d`) and a full
  file path `data/property/career/ai_sets/<...>.aist`. The short form `career/ai_sets/<...>` is rejected ("Invalid AI set path").
  Older versions of the page wrote the short form; it is rewritten to the full path wherever it is read.
- It only listens on `127.0.0.1`, rejects other host names and requires a custom header to save, so other websites
  open in your browser cannot change your settings. The server password is not part of the page's normal data; it is only returned when you click Show on the Password tab (same header check, no cross-site access).
- Theme: VisualAssault "neon", vendored in `ui/vendor` from a pinned tag. This repo follows the shared conventions in
  [gerp93/KVG_Standards](https://github.com/gerp93/KVG_Standards).
- **Where the game knowledge comes from** (file formats, which game file each name/list was read from, what was tested on a
  running server, and what is still unknown): [docs/game-data-sources.md](docs/game-data-sources.md). Re-read it from the
  installed game with `.\scripts\game-data-report.ps1`.

To open it from Hardpoint, add a mount that runs `powershell scripts\ui.ps1` from this folder with the Open URL
`http://127.0.0.1:30180`. Restart it after updating these scripts.

## Networking
1. Reserve a fixed local IP for the host PC in your router.
2. Forward **UDP 30100** (external and internal) to that IP.
3. Run `firewall.ps1` on the host.
4. Friends join from the in-game server browser and enter the password.

Extra servers need their own `instances/<name>` folder **and** a unique `game port` in their config, plus
a matching forward and firewall rule. Forward only the game port, and avoid DMZ and UPnP for this.

## Security notes
- The port forward exposes only that UDP port, and only to the server process listening on it. It does
  not expose the rest of the PC. The server process is still the attack surface, and it runs as your user.
- The server password only gates joining the lobby. Admin powers come from the privilege file.
- Use a unique password and don't reuse it elsewhere. It sits in plain text in `password.local`.
- The server is listed publicly, so anyone can see its name. Joining needs the password.
- Keep the server updated with `update.ps1` and run it only when needed. For more isolation, run it
  under a separate low-privilege Windows account or on a separate machine.

## Updating
Stop the server, run `.\scripts\update.ps1 -SteamUser YOUR_STEAM_USERNAME`, and start it again. Keep the
server and client on the same version, especially during Early Access.

## Troubleshooting
- **`ERROR! Failed to install app '3519390' (Missing configuration)`:** anonymous login is not allowed. Pass `-SteamUser`.
- **`No password set` on start:** run `set-password.ps1`.
- **Server not in the browser list:** check the process is running and listening on UDP 30100, and that no
  browser filter (for example hide passworded servers) is hiding it.
- **Friends time out:** check the router forward, the host's reserved IP, the firewall rule, and that your
  router's WAN IP is a public address (a `10.x`, `100.64-127.x` or `192.168.x` address means CGNAT or double NAT).
- **Can't connect from the host PC via your public IP:** many routers lack NAT loopback. Join from the
  server browser or use the LAN IP.

## Not supported
Linux: the server is a Windows build. Community Docker/Wine setups exist but are untested here.
