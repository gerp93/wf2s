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
| `scripts/start.ps1 [-Instance name]` | Generates local config files if needed, then launches the server with `--save-dir instances\<name>`. |
| `scripts/firewall.ps1 [-Ports 30100,...]` | Adds inbound UDP allow rules. Run elevated. |

## Layout
```
scripts/                         setup and run scripts
instances/<name>/                one folder per server (this is the --save-dir)
  server_config.template.scnf    TRACKED: name, description, port, event loop, timers, ban settings
  default_loop.becl              TRACKED: event rotation (tracks, modes, laps, bots, cars)
  server_cup_config.ccnl         TRACKED: cup definitions and points
  server_privilege.template.sprv TRACKED: empty roles/bans skeleton
  server_config.scnf             generated each start (template + password.local), gitignored
  server_privilege.sprv          created once from template + admins.local; roles/bans change at runtime, gitignored
  password.local                 server password, gitignored
  admins.local                   admin SteamID64s, one per line, gitignored
server/  steamcmd/               gitignored, recreated by install.ps1
```
Edit the **template** files, not the generated ones. They are JSON despite the `.scnf`/`.becl` extensions.

## Configuration
- **Name, description, port, timers:** `server_config.template.scnf`. Changes take effect on the next start.
- **Event rotation:** `default_loop.becl` is a list of events. Each event sets a `level id` (track), a
  `game mode id`, a weather file, rules (`laps`, `time limit` in minutes, `max number of participants`),
  a `bot count` and an optional `car restriction` list. The server runs them in order, loops, and lets
  players vote between events. The loop is chosen by `event loop name` in the server config.
- **Cups:** `server_cup_config.ccnl` defines points-based cups. Each cup points at its own rotation
  file. Default loops ship under `server/data/property/settings/`.
- **Admins:** add SteamID64s to `admins.local`. This only seeds the privilege file on its first creation.
  Afterwards use the server console: `role STEAMID64,admin`. To reseed, delete `server_privilege.sprv`.
- **Console:** type `help` in the server console. The server binary includes `eventloop`
  (`enable`, `disable`, `load <name>`, `reload`, `next`, `list`, `create`, `save`) and `cup`
  (`reload`, `start <index>`) commands.

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
