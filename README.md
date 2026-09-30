# wf2s: Wreckfest 2 dedicated server

Config-as-code for a Wreckfest 2 dedicated server (Steam app **3519390**). Binaries are not committed; config is.

## Setup on a new machine
```powershell
git clone <this repo> ; cd wf2s
.\scripts\install.ps1                 # SteamCMD + server into ./server
.\scripts\firewall.ps1                # elevated, once; UDP 30100
.\scripts\start.ps1 -Instance main    # first run creates defaults in instances/main
```
If hosting at home, also forward UDP 30100 on your router to this machine.

## Layout
- `scripts/`: install, update, start, firewall
- `instances/<name>/`: per-server `--save-dir` (tracked config). Extra servers need a unique folder **and** a unique port in their `server_config.scnf`.
- `server/`, `steamcmd/`: gitignored, recreated by `install.ps1`

Keep server and client builds in sync after game updates by running `update.ps1`.
