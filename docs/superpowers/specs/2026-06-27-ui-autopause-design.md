# UI Auto-Pause Design

## Goal

Add an optional "pause when opening WIT UI" feature for the main JEI popup.
Default is enabled.

## Scope

- Applies only to the core WIT popup opened by `R` / `U`.
- Does not apply to the mod config screen or keybind popup.
- Only works in single-player style sessions:
  - client-hosted world
  - exactly one player in the world
- Multiplayer sessions do nothing.

## Behavior

- When the popup is created successfully and the option is enabled, the mod pauses the world.
- When the popup closes, the mod resumes the world only if the mod was the source that paused it.
- If the world is already paused for another reason, the mod does not take ownership and will not unpause it later.

## Implementation

- Add a new mod config option:
  - `AUTO_PAUSE_UI`
  - default `true`
- Add localized option label and hover text in `scripts/wit_lang.lua`.
- Add popup pause helpers in `scripts/wit_ui.lua`:
  - check whether current session is eligible
  - pause on popup open
  - resume on popup close
- Use `SetServerPaused(true/false)` instead of the global `SetAutopaused()` wrapper so the feature is controlled by the mod option itself rather than the player's global auto-pause profile setting.

## Safety

- Only pause after `WIT_POPUP` is fully created.
- Track whether the mod actually caused the pause.
- Closing and reopening the popup should not leave the world stuck paused.

## Validation

- Single-player, option on: open popup pauses, close popup resumes.
- Single-player, option off: open popup does not pause.
- Multiplayer: open popup does not pause.
- World already paused before opening popup: popup close does not unpause it.
