# Where the settings page gets its game knowledge

Everything the settings page knows about Wreckfest 2 (track names, valid weather, game modes, flags, limits, live commands) was
found by reading the installed dedicated server or by trying things on a running test server. This document records **what we
know, where each fact comes from, and how sure we are**, so you can go back to the source instead of trusting memory.

- Game build these facts were collected from: **Steam build id 25956988** (`server\steamapps\appmanifest_3519390.acf`),
  `Wreckfest2.exe` 24,448,000 bytes, dated 2026-10-16. The game is in Early Access and changes often.
- To re-read the data-file facts from whatever is installed now: `.\scripts\game-data-report.ps1`
  (prints the same numbers with the file each one came from, and flags anything the game no longer contains).

## How sure are we? (legend)

| Label | Meaning |
|---|---|
| **Tested** | Tried on a running local test server and watched what it did. |
| **Read** | Read directly from a game file or from the program's own text. |
| **Inferred** | Worked out from patterns in the data; consistent with everything seen, but not stated by the game. |
| **Unknown** | Looked for it and could not find it. |

## The install at a glance

Game files live under `server\` (created by `install.ps1`, not committed). Paths below are relative to `server\`.

| Path | What it is |
|---|---|
| `Wreckfest2.exe` | The server program. Its plain-text string table is a source of valid values and console help (see below). |
| `data\property\event\trackNN\*.evse` | One **event** per playable track layout (45, plus `menutrack`). Holds title, description, weather list and sometimes the game mode. |
| `data\property\event\trackNN\trackNN.envi` | One **environment** (venue) per `trackNN`: venue name and description. |
| `data\property\weather\*.weat` / `*.weli` | `.weat` = one weather (name, sky settings). `.weli` = a weather **list**: which `.weat` files a track may use. |
| `data\property\career\ai_sets\**\*.aist` | AI car sets. `singles\` holds one per car (named after the car). |
| `data\vehicle\*` | One folder per car (plus `shared`). |
| `data\property\settings\damage_settings_list.vdsl` and `settings\damage\*`, `deformscales_*.dfsc` | The damage presets and their parts. |
| `data\property\settings\default_event_rotation.becl` | The game's own default event loop (binary). |
| `data\property\settings\cup\*.becl`, `default_cup_config_list.ccnl` | The game's own cups: track lists (binary) and cup settings. |
| `data00.rpck`, `data02.rpck` | **Encrypted archives** (header `kcpr`, high entropy). Game modes (`data/property/gamemode/*.gmde`) and some AI sets live in packs like these and **cannot be read from disk**. |

## How to read the game's data files

Almost every file under `data\property\` has the same shape, which is how the names and lists are read:

```
offset 0   u32   7
offset 4   4cc   file type, spelled backwards ("esve" = .evse, "taew" = .weat, ...)
offset 8   u32   (not needed)
offset 12  u32   length of the payload
offset 16  u32   (not needed)
offset 20  ...   payload = one standard LZ4 block
```

- **Read, checked on all 101 event, environment and weather files:** the file size always equals `20 + payload length`, and every file
  decodes at offset 20.
- Inside the decoded payload, display text is stored as a **localisation key followed by length-prefixed UTF-8**:
  `EVENT_TITLE_0657108540_12` then a `u32` length then `Main Circuit`. Keys seen: `EVENT_TITLE`, `EVENT_DESCRIPTION`,
  `ENVIRONMENT_TITLE`, `ENVIRONMENT_DESCRIPTION`, `WEATHER_NAME`, `DAMAGE_SETTINGS_NAME`, `MECH_DMG_STATE_*_DESC`.
- Other fields are binary. File paths and ids inside them are plain ASCII, so a regex finds them (for example
  `data/property/gamemode/waypointrace.gmde` inside an `.evse`).
- **Where it is implemented:** the `WfGameText` C# class in [`scripts/loops.ps1`](../scripts/loops.ps1) (`Lz4`, `Read`, `Text`).
- **Decoder in a few lines of Python**, for exploring by hand:

```python
def lz4(src, start=20):
    out = bytearray()
    i = start
    while i < len(src):
        token = src[i]; i += 1
        literals = token >> 4
        if literals == 15:                      # 255-continuation bytes extend the length
            while True:
                x = src[i]; i += 1; literals += x
                if x != 255: break
        out += src[i:i + literals]; i += literals
        if i >= len(src): break                 # the last sequence has no match part
        offset = src[i] | src[i + 1] << 8; i += 2
        match = token & 15
        if match == 15:
            while True:
                x = src[i]; i += 1; match += x
                if x != 255: break
        for _ in range(match + 4):              # copy from `offset` bytes back, one byte at a time
            out.append(out[-offset])
    return bytes(out)

# Example: the weather name of a file.
#   import re; b = open(r'server\data\property\weather\track10_1.weat', 'rb').read()
#   print(re.findall(rb'WEATHER_NAME_\d+_\d+', lz4(b)))
```

**The program's string table.** `Wreckfest2.exe` keeps its text as plain ASCII, so searching it for a phrase shows what the game
recognises (flags, orders, console help, error messages). Offsets change every build, so cite the **string**, not the offset.
(For build 25956988: console command table near `13864336`, rules summary near `13821032`, start orders near `19619800`,
collecting orders near `19643592`, car-restriction flags near `19656032`.)

## Fact register

### Tracks and names

| Fact | Source | Sure? |
|---|---|---|
| 45 playable tracks = the 45 `.evse` files (without `menutrack`). Level folders under `data\art\levels` are *not* the list: `track13_2_rev` has a folder but no event, and the `_sr` variants have events but no folder. | `data\property\event\**\*.evse` | Read |
| Track display name = **venue + layout**, e.g. "Crash Canyon - Waypoint Race" (`track10_1`). Venue from `trackNN.envi` `ENVIRONMENT_TITLE`; layout from the `.evse` `EVENT_TITLE`. | `.envi`, `.evse` | Read; the running server prints the same names ("Loading level: Crash Canyon, Waypoint Race (track10_1)") |
| `track08_1` ("Testing Grounds") is a playable event but is not in the game's default rotation. | `.evse` vs `default_event_rotation.becl` | Read |
| `track14_1`, `track14_2`, `track15_1`, `track15_2` are in the game's default rotation (44 events) but were not in the repo's original loop, which predates them. | `default_event_rotation.becl` | Read |

### Weather

| Fact | Source | Sure? |
|---|---|---|
| 40 weather files, each with a name (`WEATHER_NAME`): "Bright Day", "Sunset", "Clear Midday", ... | `data\property\weather\*.weat` | Read |
| **Weather is per track.** Each `.evse` names a weather list (`data/property/weather/<x>.weli`) and that list holds the allowed `.weat` files, e.g. FinnCross Circuit -> `track01_1.weat`, `track01_2.weat`. | `.evse`, `.weli` | Read. All 45 events in the repo's loop use a weather from their own track's list. |
| The number in a weather file name (`track01_2.weat`) is the weather **variant**, not the track layout. | `.weli` contents | Read |
| `default.weat` is in no list (it is the fallback). | `weather\` | Read |
| Whether the server rejects a weather that is not in the track's list. | n/a | Unknown (not tested) |

### Game modes

| Fact | Source | Sure? |
|---|---|---|
| Mode ids seen: `bangerrace`, `waypointrace`, `suiciderace`, `deathmatch`. | `.evse` (9 name `waypointrace`/`suiciderace` via `data/property/gamemode/<id>.gmde`), `quickrace.qred` (`bangerrace`), the repo loop | Read |
| In the game's binary default rotation the marker `demolitionderby` sits on exactly the tracks that carry `deathmatch` in the repo loop (`track06_2`, `track07_2`, `track09_3`) -> they are the same mode. Unmarked tracks are `bangerrace`. | `default_event_rotation.becl` | Inferred (the derived default mode matches the repo loop for all 40 of its tracks, including these 3) |
| The server **validates** the mode id: "Invalid game mode id '%s' for event %d". | exe string | Read |
| The game has mode categories `racing` and `derby` ("core gamemode"), menu brushes Race / Folk / Derby / TimeTrial / Waypoint, and a "Tag Game Modes" ruleset. | exe strings | Read (ids for Tag and Time Trial are **Unknown**) |
| The complete list of mode ids. The `.gmde` files are in the encrypted packs. | `data00.rpck`, `data02.rpck` | **Unknown** |

### Cars and AI

| Fact | Source | Sure? |
|---|---|---|
| 24 cars = the 24 folders under `data\vehicle` (22 `carNN`, `motorhome`, `school_bus`; `shared` is not a car). The ids match `allowed car type` in a cup's car restriction. | `data\vehicle\*` | Read |
| Car names (RoadSlayer, Popper, Gizmo, Motorhome, ...) come from the single-car AI sets. | `ai_sets\singles\*.aist` | Read |
| AI set files and names ("American Cars", ...). The loop's default `career/ai-class-all.aist` is **not on disk**, and `quickchallenge/qc_*.aist` are only referenced from the game's cup files, so the on-disk list is incomplete. | `ai_sets\**\*.aist`, `settings\cup\*.becl` | Read; completeness **Unknown** |

### Damage

| Fact | Source | Sure? |
|---|---|---|
| Three presets: `normal`, `realistic`, `wrecker`. | `damage_settings_list.vdsl` | Read |
| `normal` and `wrecker` use the **reduced** engine damage model (`damage_reduced.veed`); `realistic` uses the **full** one (`damage_full.veed`). Each preset has its own tyre, deformation and mechanical-damage files. Numbers differ between presets but are unlabeled, so "which takes more damage" is **not** stated anywhere. | `damage_settings_list.vdsl`, `damage\*`, `deformscales_*.dfsc` | Read |
| When `vehicle damage id` is empty the server uses **`normal`** (`rules` printed `"vehicle damage id": "normal"` for an empty setting). | local test server | **Tested** |
| The server rejects unknown ids ("Invalid vehicle damage id!") and has a console command to change or list them. | exe strings | Read |

### Rules, flags and orders

| Fact | Source | Sure? |
|---|---|---|
| Collecting orders: `Collecting None`, `Collecting Sequential`, `Collecting Random`, `Collecting Free`. | exe string table | Read |
| Start orders: `random`, `points`, `points reversed`, `last race`, `last race reversed`. (`random` and `points` are used by the shipped cups; `last race` is only in the exe.) | exe string table, `server_cup_config.ccnl` | Read |
| Rule flag names in the exe: `disable car resets`, `disable tuning`, `disable upgrades`, `disable wrong way limiter`, `disable special vehicles`, `disable class a` (b, c, d), `disable mechanical particle effects`. Car-restriction flags: `reverse rule`, `disallow class a` (b, c, d), `disallow upgrades`, `disallow tuning`. | exe string table | Read |
| The `flags` string in a rules block: **lower case, exact names, separated by `|`** (spaces around it are fine; the server prints `a | b`). A comma, `;`, `+`, a space, or upper case makes the server **silently drop all flags**; an unknown name is **silently dropped**. Accepted and echoed back: `disable car resets`, `disable tuning`, `disable upgrades`, `disable wrong way limiter`. | local test server | **Tested** |
| **Car resets are turned off with the `disable car resets` flag**, not with the delay. `car reset delay (seconds)` is the wait between resets. The game's rules summary lists "Car Resets", "Wrong Way Limiter", "Special Vehicles", "Off-board Camera", "Tuning", "Upgrades" as on/off rules, and "Car Reset Delay: %ds" separately. | exe strings; flag **Tested** as accepted | Read; that it actually blocks resets in a race is **Unknown** (needs a human player) |
| What delay `0` does (instant resets vs. unlimited). | n/a | **Unknown** |

### Limits

| Fact | Source | Sure? |
|---|---|---|
| **24 cars is a hard cap** (players + bots). `grid_size` 25, 30, 32, 40, 64, 128, 1000 all stay at 24; `bot_count 30` ends at 24/24. | local test server | **Tested** |
| The program also has a `max client count` setting; what it controls (spectators?) is **Unknown**. | exe string | Read |

### Cups

| Fact | Source | Sure? |
|---|---|---|
| The server's cup list is `server_cup_config.ccnl` in the save dir (log: "Cup config list 'save/server_cup_config.ccnl' loaded"). Each cup has race settings and an `event loop` path. In this repo that file is **generated** from `server_cup_config.template.ccnl`. | local test server | **Tested** |
| The game's own cup loops (`settings\cup\*.becl`) are binary files holding events with a track id, laps and minutes. `Get-WfBuiltinCupEvents` in `scripts/loops.ps1` reads them. | `settings\cup\*.becl` | Read; values not cross-checked against a running cup |
| **A cup's `event loop` path is resolved relative to the save (instance) folder.** A JSON events file there (`wp.becl`, or in a subfolder `sub/wp2.becl`) is accepted: `cup reload` succeeds and `cup start N` runs it (cups are numbered from 1). The `save/<file>` spelling is rejected ("invalid event loop"), as is a path that does not exist. | local test server | **Tested** |
| **The same JSON file copied into the game's own `server\data\property\settings\cup` folder is rejected**: "Cup N, event loop 'data/property/settings/cup/wf2s_x.becl' has no valid events!" / "Failed to load cup config". | local test server; also seen on the real server's log | **Tested** |
| **Extra loose files in the server's `data` folder make clients refuse to join.** The server and the client each compute a data checksum ("Join rejected: Client has mismatching checksum" on the server, "Server checksum mismatch" / error 300E on the client). Comparing the client's `data\property` with the server's (2,956 files, same sizes) the only difference was the seven `wf2s_*.becl` files we had copied in. | exe strings; file comparison of both installs; the player's error screenshot | Read / Inferred: a client actually joining after the fix was **not** tested |
| Valid `ai set path` values: the class sets `career/ai-class-all.aist` and `-a`/`-d` (and by pattern `-b`, `-c`), and a full path `data/property/career/ai_sets/<...>.aist` (including `quickchallenge/qc_folk_racing.aist`, which is not a loose file). Rejected: `career/ai_sets/<...>` (short form), `career/ai-class-b` (no extension). The server validates each event: "Invalid AI set path '%s' for event %d". | local test server (10 spellings tried); exe strings `career/ai-class-all`, `-a`..`-d`, `data/property/career/ai_sets` | **Tested** |
| `cup reload` re-reads the cup config; the server refuses it while a cup is running. | local test server; exe string | **Tested** (reload) / Read (refusal) |

### Server console and live control

| Fact | Source | Sure? |
|---|---|---|
| The server console takes commands. From its help text: `event`, `eventloop` (enable, disable, load, reload, create, save, list, inspect, next, select, replace, insert, remove), `level`/`track`, `levels`, `weather`, `weathers`, `rules`, `grid_size`, `laps`, `collectingOrder`, `damage`, `players`, `users`, `kick`, `ban`, `censor`, `silence`, `pardon`, `banlist`, `roles`, `role`, `print_config`, `race_director`, `idle_kick`, `race_end_timer`, `countdown`, `message`, `cup` (abandon, reload, start), plus name, description and password commands, `bots`/`bot_count`, `add_bot`, `restart`, `race_end`. | exe string table; `eventloop` and `cup` listings **Tested** | Read / Tested |
| `eventloop reload` re-reads the loop file and applies it (bots 8 -> 3, 40 -> 39 events). It **restarts the loop at its first event and reloads the level**. | local test server | **Tested** |
| `eventloop select N` jumps to event N (0-based). `event` prints the active event as JSON including `"eventId"`. | local test server | **Tested** |
| Name, description and password can probably be changed live: the console has `name`, `description` and `password` commands (`password` takes `disabled` to remove it). | the server's own `help` list | Read; not tested |
| **`shutdown` stops the server gracefully** ("Requesting shutdown... NetServer shutdown... Deinitializing"); the process exits in about 2 seconds. `exit` / `quit` stop it immediately. | local test server | **Tested** (`shutdown`); `exit`/`quit` Read |
| The server's console help (`help`, `commands` or `?`) lists every command with its aliases: add_bot/bot, ban, banlist, bot_count/bots, censor, collectingOrder, countdown, cup, damage, description, event, eventloop/el, exit/quit, grid_size, idle_kick, kick, laps, level/track, levels/tracks, message, name, pardon/unban, password, players/plrs, print_config, race_director, race_end/abandon, race_end_timer, restart, restart_countdown, role, roles, rules, set, show_join_errors, shutdown, silence, status, telemetry_player, users/clients, version, weather, weathers. | local test server | **Tested** (printed by the running server) |
| When started with `scripts\start.ps1` the PowerShell launcher returns straight away while the game keeps running with its own console window. `Wreckfest2.exe` is therefore found by its `--save-dir` command line, not by its parent. | observed when starting a local test instance from the page | **Tested** |
| Start-up options: `--server`, `--local-server`, `--disable-online-server`, `--disable-eventloop`, `--server-address`, `--use-title-entity`, `--save-dir`. | exe strings | Read |

## How the test server was run

Facts marked **Tested** came from a throwaway server, never the real one:

1. Copy the config templates into a separate folder (outside the repo or under `instances\zz-*`, deleted afterwards), set a different
   `game port` (30199) and a dummy password, generate `server_config.scnf` and `default_loop.becl` with `Build-WfLoop`.
2. Start `server\Wreckfest2.exe --local-server --save-dir=<folder>` **without redirecting its output** (the console screen is how
   replies are read).
3. Type commands and read the screen with [`scripts/console.ps1`](../scripts/console.ps1)
   (`-ProcessId <pid> -SendList 'eventloop reload|cup reload' -Read 40`). It attaches to the server's console, writes keystrokes with
   `WriteConsoleInput` and reads the screen buffer through `CONOUT$`.
4. Stop only that process (check its command line contains the test folder name) and delete the folder.

The same `console.ps1` mechanism powers **Apply now** ([`scripts/apply.ps1`](../scripts/apply.ps1)).
Never run any of this against a real server except through the page's Apply now button.

## Not verified yet (the honest list)

- Whether a custom cup loop file is accepted by the server (and how added cups look in the client's cup picker).
- Whether the server rejects a weather outside a track's list.
- That `disable car resets` really blocks resets in a race, and what `car reset delay` `0` means.
- The full game-mode list (Tag, Time Trial and any others are in encrypted archives).
- What `max client count` does.
- Live name, description and password changes.
- Behaviour with real players connected (all tests used bots only).

## Where each fact is used in this repo

| Fact | Code |
|---|---|
| Decoding data files | `WfGameText` in `scripts/loops.ps1` |
| Track, weather, AI, car names | `Get-WfNames` |
| Track list, weather list, mode list, cars, AI sets, damage, orders (the page's drop-downs) | `Get-WfChoices` |
| Default mode per track | `Get-WfTrackModes` |
| Weather allowed per track | `Get-WfWeatherByTrack` |
| 24-car cap | `MAX_PLAYERS` in `ui/index.html`; limits in `scripts/loops.ps1` (`Assert-WfLoop`) |
| Live apply | `scripts/apply.ps1`, `scripts/console.ps1`, `POST /api/apply` in `scripts/ui.ps1` |
| Start / stop the server | `scripts/server.ps1` (`Start-WfServer`, `Stop-WfServer`), `POST /api/server/start` and `/api/server/stop` in `scripts/ui.ps1` |
| Rule flags (car resets, tuning, upgrades, wrong-way limiter) | `$WfRuleFlags` in `scripts/settings.ps1`; `flagsEditor` in `ui/index.html` |
| Layered settings (event own value > cup > Global default > file) | `Set-WfLoopOverrides` and `Build-WfLoop` in `scripts/settings.ps1`; `Publish-WfCupLoops` in `scripts/loops.ps1`; `makeOv` / `effective` in `ui/index.html`. This is page logic, not game behaviour: the game only ever sees the final merged files. |
| Everything above, re-read from the installed game | `scripts/game-data-report.ps1` |
