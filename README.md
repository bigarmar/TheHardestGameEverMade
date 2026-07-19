# The Hardest Game Ever Made

## Purpose and premise

This is a complete short-form comedy first-person-shooter prototype made for Godot 4.7.1. It presents one tiny campaign as an impossibly expensive, dangerous, civilization-defining military operation. The actual objective is to enter one compact containment chamber and shoot one large stationary target directly in front of the player. One successful shot completes the campaign.

The intended joke is **maximum presentation, minimum challenge**. Before the hit, the presentation remains sincere and severe. After the hit, the game celebrates as though history has permanently changed.

## Godot version and renderer

- Godot Engine 4.7.1 standard edition
- GDScript only; no C# and no .NET requirement
- Forward+ renderer using the Windows D3D12 rendering device
- Jolt Physics

## Opening and running the project

1. Open Godot 4.7.1.
2. In the Project Manager, import or select `project.godot` from this folder.
3. Open the project.
4. Press **F6/F5** or click the Play button. The configured main scene is `scenes/main.tscn`.

## Controls

- **W A S D** — move
- **Mouse** — aim
- **Left mouse button** — fire
- **Shift** — move faster
- **Escape** — pause and release the mouse

The pause menu includes Resume, Settings, Restart Campaign, Return to Main Menu, and Quit.

## Project structure

- `assets/audio/` — documentation for replaceable procedural audio events
- `assets/materials/` — reserved for future authored materials
- `assets/models/` — reserved for future authored models
- `assets/portraits/hero_expressions.png` — original seven-expression HUD portrait atlas
- `assets/textures/` — reserved for future authored textures
- `scenes/main.tscn` — main scene entry point
- `scenes/gameplay/` — reserved for packed gameplay scenes if the procedural chamber is later converted
- `scenes/ui/` — reserved for packed UI scenes if the programmatic menus are later converted
- `scripts/main.gd` — game manager, screen flow, chamber construction, victory flow, and statistics presentation
- `scripts/gameplay/` — player, weapon, and target controllers
- `scripts/systems/` — saving, achievements, audio, and transitions
- `scripts/ui/` — HUD and portrait controllers

The chamber is assembled from original Godot primitive geometry at runtime. This keeps the prototype self-contained and makes the tiny room easy to tune.

## Portrait assets and expressions

The generated original portrait sprite sheet is stored at:

`assets/portraits/hero_expressions.png`

`scripts/ui/portrait_controller.gd` selects one of seven regions from the atlas. Supported state names are:

- `determined`
- `impatient`
- `concerned`
- `disappointed`
- `shocked`
- `proud`
- `exhausted`

`scripts/ui/hud_controller.gd` owns the portrait during gameplay. `scripts/main.gd` changes expressions in response to waiting, missing, victory, and repeated completions. The portrait also has subtle pulse and blink animation.

## Temporary audio and ElevenLabs replacement

All current audio is original and generated procedurally in `scripts/systems/audio_manager.gd`. This avoids copyrighted downloads and keeps the repository small. The named events are documented in `assets/audio/REPLACE_ME.md`.

To replace an event with an ElevenLabs WAV file later:

1. Export the final sound as PCM WAV or OGG.
2. Place it in `assets/audio/` using the corresponding event name.
3. In `AudioManager._create_event()` or `AudioManager.play_music()`, replace the procedural generator call with `load("res://assets/audio/<event>.wav")`.
4. Keep menu, music, and sound-effect volume routing intact.

## Saves, settings, achievements, and statistics

The game uses Godot's recommended local user-data location and writes:

`user://hardest_game_save.json`

On Windows, `user://` normally resolves beneath `%APPDATA%\Godot\app_userdata\The Hardest Game Ever Made\`.

The save contains settings, achievement unlocks, difficulty selections, completion counts, campaign times, shots, misses, accuracy inputs, credits completions, and time spent in gameplay and menus. Missing saves are created automatically. Malformed JSON is ignored safely and copied to `hardest_game_save_corrupted.json` before defaults are restored.

To reset local progress, close the game and delete `hardest_game_save.json` from the Godot user-data folder. Settings are preserved only when reset through code; deleting the file resets everything.

## Windows export

1. In Godot, open **Project > Export**.
2. Add a **Windows Desktop** preset.
3. Install the official Godot export templates if Godot requests them.
4. Choose an output such as `build/TheHardestGameEverMade.exe`.
5. Keep Forward+ enabled for the intended visual result.
6. Export the project and test the executable on a clean Windows machine.

The project deliberately does not include accounts, networking, analytics, Firebase, Google Cloud, advertisements, payments, or multiplayer.

## Adding Android controls later

The player, weapon, and game flow are separated so mobile input can be added without rewriting the campaign:

1. Create a mobile HUD scene with a virtual movement stick, look region, fire button, sprint button, and pause button.
2. Map those widgets to input actions or expose movement/look/fire methods on `PlayerController`.
3. Switch the renderer to Mobile for Android if Forward+ is too expensive on the target device.
4. Increase HUD touch targets and add safe-area margins.
5. Tune sensitivity, camera sway, particles, fog, shadows, and light count per device tier.
6. Create an Android export preset and test touch capture, pause behavior, and save persistence.

## Known limitations

- The prototype uses generated primitive geometry rather than authored skeletal models.
- Audio is intentionally procedural placeholder audio, ready to be replaced by final ElevenLabs/music assets.
- The seven portrait expressions share one generated atlas; future animation could use multi-frame facial motion.
- Volumetric fog, glow, four shadowed lights, and dense victory particles target a desktop GPU. Lower light shadow counts and confetti amount for older hardware or mobile.
- Export templates are not bundled with the project, so a Windows executable must be exported from an installed Godot editor.

