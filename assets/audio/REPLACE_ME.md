# Temporary procedural audio replacement map

The prototype's centralized `AudioManager` generates every sound locally. Replace these named events with final ElevenLabs or authored assets when ready:

| Event | Suggested filename | Purpose |
|---|---|---|
| `menu_move` | `menu_move.wav` | menu hover/navigation tick |
| `menu_confirm` | `menu_confirm.wav` | menu confirmation and campaign start |
| `warning` | `impossible_warning.wav` | Impossible Mode alarm |
| `loading` | `loading_progress.wav` | staged loading update |
| `ambience` | `campaign_ambience.ogg` | containment chamber drone |
| `gunshot` | `weapon_fire.wav` | original weapon firing sound |
| `impact` | `target_impact.wav` | confirmed target hit |
| `confetti` | `confetti_burst.wav` | celebration burst |
| `achievement` | `achievement_unlocked.wav` | achievement notification |
| `countdown` | `countdown_tick.wav` | pre-control countdown |
| `music_menu` | `title_music.ogg` | blockbuster title/menu bed |
| `music_battle` | `campaign_music.ogg` | serious combat bed |
| `music_victory` | `victory_fanfare.ogg` | exaggerated completion fanfare |
| `music_credits` | `credits_music.ogg` | dramatic scrolling credits cue |

Optional voice lines such as `CAMPAIGN INITIATED` can be added as new clearly named events without changing gameplay logic.

