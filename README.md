# wf2s: Wreckfest 2 dedicated server

Host your own **Wreckfest 2** dedicated server on a Windows PC, set up and run from a page in your browser: server name and
password, the track rotation, cups, bots and rules, start/stop, and help with the router. Plain PowerShell, nothing to install
beyond a Steam account that owns Wreckfest 2.

Licensed under the [AGPL-3.0](LICENSE). Game files are never part of this project; they are downloaded from Steam on your PC.

## Quick start (no technical knowledge needed)

You need: a Windows 10 or 11 PC, a Steam account that **owns Wreckfest 2**, about 6 GB of free disk space, and (for friends
outside your home) access to your router's settings.

1. **Download** the latest `wf2s-<version>.zip` from the [Releases page](https://github.com/gerp93/wf2s/releases), right-click it,
   choose **Extract All**, and open the extracted folder. (Do not run it from inside the zip.)
2. **Double-click `Start.cmd`.** Windows may show a blue "Windows protected your PC" box because the file came from the internet:
   click **More info**, then **Run anyway**. The program is plain text you can read in the `scripts` folder.
3. **Answer the questions** in the window that opens:
   - your **Steam account name** (the one you sign in with). Steam then asks for your password, and a Steam Guard code if you use
     one, in the same window. Those go straight to Steam; this program never sees or stores them. The game server (a few GB) downloads.
   - a **server name** (shown in the game's server list) and a **server password** that friends type to join.
   - your **Steam ID** (optional) to become the server's admin. The window explains where to find it.
   - Windows asks once for **permission to open the game port in its firewall**: click Yes.
4. **Set up your router** (the one step no program can do for you, see below). Skip it if everyone plays on your home network.
5. The **settings page** opens in your browser. Click **Start server**. After about 20 seconds the status turns green and the server is
   in the game's multiplayer server list (search for its name; passworded servers show a lock).
6. On the page's **Network & version** tab, check that the server says it is reachable from the internet.

Next time, just double-click `Start.cmd` again: it opens the settings page straight away. Closing the window closes the page only;
a running server keeps running in its own window.

### The router step
Friends on the internet reach you through your router, which needs two settings (the page's **Network & version** tab shows the
exact numbers for your PC):

1. **A static IP address for this PC.** Look for *DHCP reservation* or *static lease* in the router and reserve this PC's address.
   Otherwise the router may give the PC a new address one day and the forward below stops working.
2. **Port forwarding** of **UDP 30100** (external and internal) to that address. Some routers call it *virtual server*.

Every router has different menus, and some (such as Deco or eero mesh systems) can only be changed from their phone app instead of a web page: search for your router's model name plus "port forwarding". Forward only that one port, and avoid
DMZ. If your router's internet address starts with `10.`, `192.168.`, `172.16`-`172.31` or `100.64`-`100.127`, your provider shares one
address between customers (CGNAT) and no port forward can work; you would need a public address from the provider, or to host elsewhere.

### What can go wrong
- **"Failed to install app 3519390 (Missing configuration)"**: that account does not own Wreckfest 2, or the login failed. Run
  `Start.cmd` again to retry.
- **Players are refused with a version or "300E checksum mismatch" error**: their game and your server are on different versions.
  Use **Update server** on the Network & version tab. Never add files to the server's `data` folder.
- **Friends time out**: see the checklist the page shows under "Is it working?". Playing from the host PC through your own public
  address often fails because many routers cannot loop back; join from the in-game server list instead.
- **Nothing happens when I double-click `Start.cmd`**: make sure you extracted the zip, and that antivirus did not quarantine it.

## For people who want to go further

### Requirements
- Windows 10/11 and PowerShell 5.1+
- A Steam account that **owns Wreckfest 2**. Anonymous SteamCMD login is refused for this app
  ("Missing configuration"), so installing needs a Steam account name (`-SteamUser`, or the first-run setup asks).
- For friends over the internet: UDP **30100** forwarded on your router to the host PC (see [Networking](#networking)).

### Install from git instead of the zip
```powershell
git clone https://github.com/gerp93/wf2s.git ; cd wf2s
.\Start.cmd          # or: powershell -ExecutionPolicy Bypass -File scripts\launch.ps1
```
That is the same first-run setup as the zip. To do the steps by hand: `.\scripts\install.ps1 -SteamUser NAME`,
`.\scripts\set-password.ps1`, put your SteamID64 in `instances\main\admins.local`, `.\scripts\firewall.ps1` (elevated),
`.\scripts\start.ps1 -Instance main`. A server needs `instances\main` to exist first: run `.\scripts\setup.ps1`, or any script that
creates it from `defaults\instance`.

## Scripts
| Script | What it does |
|---|---|
| `Start.cmd` | Double-click launcher: runs `scripts\launch.ps1` with `-ExecutionPolicy Bypass`. |
| `scripts/launch.ps1 [-Instance name] [-Port 30180]` | Runs `setup.ps1` if anything is missing, then runs the settings page and opens it in the browser. |
| `scripts/setup.ps1 [-Instance name]` | First-run wizard (PC check, game download, name/password/admin, firewall, router help). Safe to re-run: finished steps are skipped and an existing server is only changed if you type new answers. |
| `scripts/install.ps1 [-SteamUser name]` | Downloads SteamCMD if missing, installs or updates the server into `./server`. Remembers the Steam account name (not the password) in `steam-user.local`. |
| `scripts/update.ps1` | Re-runs the install to pick up game patches. Stop the server first (the page's Update button does that). |
| `scripts/set-password.ps1 [-Instance name]` | Prompts for the password and writes `password.local`. |
| `scripts/start.ps1 [-Instance name] [-Local]` | Creates the instance from `defaults\instance` if it does not exist, generates the config files, then launches the server with `--save-dir instances\<name>`. `-Local` starts the game's local-only mode (`--local-server`) instead of the online one; it is for testing. |
| `scripts/firewall.ps1 [-Ports 30100,...]` | Adds inbound UDP allow rules (skips ports that already have one). Run elevated; `setup.ps1` does that for you. |
| `scripts/ui.ps1 [-Instance name] [-Port 30180] [-OpenBrowser]` | Local settings page at `http://127.0.0.1:30180`. See [Settings page](#settings-page). |
| `scripts/console.ps1 -ProcessId <pid> [-Send 'cmd'] [-Read n]` | Types commands into a running server's console and prints its screen. Used by "Apply now" and the Network tab. |
| `scripts/game-data-report.ps1` | Re-reads the game facts the page relies on (names, lists, flags, limits) from the installed game. See [docs/game-data-sources.md](docs/game-data-sources.md). |
| `scripts/test.ps1` | Automated checks (script syntax, defaults, setup, generators, the page's API, packaging). Needs no game and no Steam account. CI runs it. |
| `scripts/package.ps1 [-Version v1.2.3]` | Builds `dist\wf2s-<version>.zip` from the files tracked in git and checks that nothing personal or from the game is in it. |
| `scripts/update-visual-assault-css.ps1 <tag>` | Re-vendors the settings page theme from a VisualAssault tag. |

## Layout
```
Start.cmd                        double-click launcher
scripts/                         setup and run scripts
defaults/instance/               the clean starting point every new server is created from (tracked)
defaults/server_cup_config.ccnl  the game's six cups as shipped ("Reset to defaults")
defaults/known-build.json        the game build this app was last checked against
instances/<name>/                YOUR server (this is the --save-dir). Created by setup, never tracked, never shipped
  server_config.template.scnf    name, description, port, event loop, timers, ban settings
  default_loop.template.becl     event rotation (tracks, modes, laps, bots, cars)
  settings.json                  global overrides saved by the settings page (optional)
  cups/<slug>.becl               custom cup rotations made on the Cups tab (optional)
  server_cup_config.template.ccnl cup definitions and points (the page edits this one)
  server_cup_config.ccnl         generated each start (template + cups\*.becl): the cup list the game reads
  cups-generated/<slug>.becl     generated each start from cups\<slug>.becl: each custom cup's events for the game
  server_privilege.template.sprv empty roles/bans skeleton
  server_config.scnf             generated each start (template + settings.json + password.local)
  default_loop.becl              generated each start (template + settings.json)
  server_privilege.sprv          created once from template + admins.local; roles/bans change at runtime
  password.local                 server password
  admins.local                   admin SteamID64s, one per line
ui/                              settings page (index.html, vendored VisualAssault theme)
server/  steamcmd/               the game and SteamCMD, recreated by install.ps1 (not tracked)
steam-user.local                 your Steam account name (not tracked)
```
Everything under `instances/`, `server/`, `steamcmd/` and every `*.local` file is gitignored and left out of the release zip.
Edit the **template** files (or use the page), not the generated ones. They are JSON despite the `.scnf`/`.becl` extensions.

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
A local page (PowerShell only, no extra dependencies) with five tabs: Global defaults, Rotation, Cups, Password and Network & version.
The server does not need to be stopped to edit; changes apply the **next time it starts**, or right away with **Apply now**.
The header shows whether this instance's `Wreckfest2.exe` is running and can start and stop it (see below).

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

### Network & version tab
- **Make your server reachable from the internet:** this PC's local address, the router's address, the port and protocol to forward (UDP 30100, read from the
  instance's `game port`), whether the address is fixed (DHCP) and whether the Windows Firewall rule exists. It explains in plain
  words what a static IP and a port forward are, as two numbered steps with the values to type into the router.
- **Is it working?** The server tests itself shortly after it starts and prints `Server is reachable from public network.` or
  `Server is unreachable.`, plus `Router port forwarded using UPnP. External endpoint at <ip>` or `... UPnP unavailable ...`. The
  page reads those lines from the running server's console (the same way Apply now does) and turns them into advice, including a
  CGNAT warning when the router reports a private address. It cannot test your router from outside by itself, and it makes no
  requests to outside services. Before the server prints a verdict it says "no result yet"; click Refresh.
  Tested here: the console-text parsing, with the server's exact messages (taken from the server program) as test input; the tab
  against a running local-only server (which never prints a verdict, so only the "no result" case was seen live).
- **Game version:** shows what this app was **tested up to** (game version and server build, from `defaults/known-build.json`),
  and what is installed: the Steam server build (`server\steamapps\appmanifest_3519390.acf`) and the game version players see
  (read from the running server's window title, then remembered in `game-version.local` for as long as the server build is the same). A banner warns when either
  differs from what was tested, because the reverse-engineered formats and string tables may have changed. **Update server** stops the server after asking, then opens `scripts\update.ps1` in its own window
  (SteamCMD may need a Steam Guard code); start the server again from the header when it finishes. It needs the Steam account name
  that `install.ps1` saved in `steam-user.local`; the button explains this when it is missing. The update path has not been run end to end.

To open it from Hardpoint, add a mount that runs `powershell scripts\ui.ps1` from this folder with the Open URL
`http://127.0.0.1:30180`. Restart it after updating these scripts.

## Networking
1. Set a static IP for the host PC in your router (DHCP reservation).
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
**The game server:** use **Update server** on the page's Network & version tab, or stop the server, run
`.\scripts\update.ps1` (it uses the Steam account name saved by the first install; pass `-SteamUser NAME` to change it) and start it
again. Keep the server and client on the same version, especially during Early Access.

**This app:** download the new zip and extract it over (or beside) the old folder. Your server lives in `instances\`, which the zip
does not contain, so it is never overwritten. If you installed with git, `git pull`.

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
