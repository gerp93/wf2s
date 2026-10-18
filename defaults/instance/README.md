# Your server's folder

This folder is the server's `--save-dir`. It was created from `defaults/instance` by `scripts\setup.ps1` and belongs to you:
updating the app never changes it. Most of it is edited from the settings page, so you rarely need to open it.

- `server_config.template.scnf`: name, description, port, event loop, timers, ban settings.
- `default_loop.template.becl`: the event rotation. `default_loop.becl` is generated from it at every start.
- `server_cup_config.template.ccnl`: the cup list. `server_cup_config.ccnl` is generated from it at every start.
- `settings.json`: the page's Global defaults (bots, damage, laps, server name, ...).
- `cups/*.becl`: your own cup rotations (made on the Cups tab).
- `password.local`, `admins.local`: the server password and the admin Steam IDs. Never share these.
- `server_privilege.sprv`: roles and bans. Created once from `admins.local`; it changes while the server runs.

Edit the template files (or use the page), not the generated ones. The files are JSON despite their extensions.
