extends Node
class_name SaveManager

const SAVE_PATH := "user://hardest_game_save.json"
const DIFFICULTIES := ["Easy", "Normal", "Hard", "Expert", "Impossible"]

var data: Dictionary = {}


func _ready() -> void:
	load_data()


func _default_data() -> Dictionary:
	return {
		"version": 1,
		"settings": {
			"master_volume": 0.85,
			"music_volume": 0.60,
			"sfx_volume": 0.85,
			"mouse_sensitivity": 0.22,
			"fullscreen": false,
			"resolution": "1280x720"
		},
		"achievements": {},
		"stats": {
			"total_campaign_completions": 0,
			"fastest_campaign_time": 0.0,
			"slowest_campaign_time": 0.0,
			"total_shots_fired": 0,
			"total_successful_hits": 0,
			"total_misses": 0,
			"total_time_playing": 0.0,
			"total_time_menus": 0.0,
			"credits_completed": 0,
			"valued_life_count": 0,
			"difficulty_selections": {
				"Easy": 0, "Normal": 0, "Hard": 0, "Expert": 0, "Impossible": 0
			},
			"difficulty_completions": {
				"Easy": 0, "Normal": 0, "Hard": 0, "Expert": 0, "Impossible": 0
			}
		}
	}


func load_data() -> void:
	data = _default_data()
	if not FileAccess.file_exists(SAVE_PATH):
		save_data()
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		backup_corrupted_save()
		save_data()
		return
	_merge_dictionary(data, parsed)


func _merge_dictionary(target: Dictionary, incoming: Dictionary) -> void:
	for key in incoming:
		if target.has(key) and typeof(target[key]) == TYPE_DICTIONARY and typeof(incoming[key]) == TYPE_DICTIONARY:
			_merge_dictionary(target[key], incoming[key])
		else:
			target[key] = incoming[key]


func backup_corrupted_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var source := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if source == null:
		return
	var backup := FileAccess.open("user://hardest_game_save_corrupted.json", FileAccess.WRITE)
	if backup != null:
		backup.store_string(source.get_as_text())


func save_data() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))


func get_setting(key: String, fallback = null):
	return data.get("settings", {}).get(key, fallback)


func set_setting(key: String, value, persist := true) -> void:
	data["settings"][key] = value
	if persist:
		save_data()


func stats() -> Dictionary:
	return data["stats"]


func is_unlocked(id: String) -> bool:
	return bool(data["achievements"].get(id, false))


func unlock(id: String) -> bool:
	if is_unlocked(id):
		return false
	data["achievements"][id] = true
	save_data()
	return true


func record_difficulty_selection(difficulty: String) -> void:
	var selections: Dictionary = data["stats"]["difficulty_selections"]
	selections[difficulty] = int(selections.get(difficulty, 0)) + 1
	save_data()


func record_completion(difficulty: String, completion_time: float, shots: int, hits: int, misses: int) -> void:
	var s: Dictionary = data["stats"]
	s["total_campaign_completions"] = int(s["total_campaign_completions"]) + 1
	if float(s["fastest_campaign_time"]) <= 0.0 or completion_time < float(s["fastest_campaign_time"]):
		s["fastest_campaign_time"] = completion_time
	if completion_time > float(s["slowest_campaign_time"]):
		s["slowest_campaign_time"] = completion_time
	s["total_shots_fired"] = int(s["total_shots_fired"]) + shots
	s["total_successful_hits"] = int(s["total_successful_hits"]) + hits
	s["total_misses"] = int(s["total_misses"]) + misses
	var completions: Dictionary = s["difficulty_completions"]
	completions[difficulty] = int(completions.get(difficulty, 0)) + 1
	save_data()


func add_time(gameplay_delta: float, menu_delta: float) -> void:
	data["stats"]["total_time_playing"] = float(data["stats"]["total_time_playing"]) + gameplay_delta
	data["stats"]["total_time_menus"] = float(data["stats"]["total_time_menus"]) + menu_delta


func increment_stat(key: String, amount := 1) -> void:
	data["stats"][key] = data["stats"].get(key, 0) + amount
	save_data()


func most_selected_difficulty() -> String:
	var selections: Dictionary = data["stats"]["difficulty_selections"]
	var best := "None"
	var best_count := 0
	for difficulty in DIFFICULTIES:
		var count := int(selections.get(difficulty, 0))
		if count > best_count:
			best_count = count
			best = difficulty
	return best


func reset_progress() -> void:
	var settings_copy: Dictionary = data.get("settings", {}).duplicate(true)
	data = _default_data()
	data["settings"] = settings_copy
	save_data()

