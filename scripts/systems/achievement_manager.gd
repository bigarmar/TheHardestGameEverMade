extends Node
class_name AchievementManager

const DEFINITIONS := {
	"against_all_odds": ["AGAINST ALL ODDS", "Complete Impossible Mode."],
	"speedrunner": ["SPEEDRUNNER", "Complete the campaign in under five seconds."],
	"faster_than_intended": ["FASTER THAN INTENDED", "Complete the campaign in under two seconds."],
	"warning_shot": ["WARNING SHOT", "Miss the first shot."],
	"how_did_you_miss": ["HOW DID YOU MISS?", "Miss five times during one campaign."],
	"pacifist_ending": ["PACIFIST ENDING", "Remain in the room for thirty seconds without firing."],
	"credits_enjoyer": ["CREDITS ENJOYER", "Watch the complete credits."],
	"you_looked": ["You Looked", "The tiny duck was behind you the entire time."],
	"self_sabotage": ["Self-Sabotage", "Disable every tactical ceiling light."],
	"exact_same_experience": ["THE EXACT SAME EXPERIENCE", "Complete both Easy and Impossible Mode."],
	"veteran": ["VETERAN", "Complete the campaign ten times."],
	"touch_grass": ["TOUCH GRASS", "Complete the campaign one hundred times."]
}

var save_manager: SaveManager
var notify_callback: Callable


func setup(manager: SaveManager, notifier: Callable) -> void:
	save_manager = manager
	notify_callback = notifier


func unlock(id: String) -> void:
	if not DEFINITIONS.has(id) or save_manager == null:
		return
	if save_manager.unlock(id) and notify_callback.is_valid():
		var definition: Array = DEFINITIONS[id]
		notify_callback.call(definition[0], definition[1])


func on_shot(shots: int, misses: int) -> void:
	if shots == 1 and misses == 1:
		unlock("warning_shot")
	if misses >= 5:
		unlock("how_did_you_miss")


func on_pacifist() -> void:
	unlock("pacifist_ending")


func on_credits_completed() -> void:
	unlock("credits_enjoyer")


func on_completion(difficulty: String, completion_time: float) -> void:
	if difficulty == "Impossible":
		unlock("against_all_odds")
	if completion_time < 5.0:
		unlock("speedrunner")
	if completion_time < 2.0:
		unlock("faster_than_intended")
	var s := save_manager.stats()
	var completions: Dictionary = s["difficulty_completions"]
	if int(completions.get("Easy", 0)) > 0 and int(completions.get("Impossible", 0)) > 0:
		unlock("exact_same_experience")
	if int(s["total_campaign_completions"]) >= 10:
		unlock("veteran")
	if int(s["total_campaign_completions"]) >= 100:
		unlock("touch_grass")


func entries() -> Array:
	var result := []
	for id in DEFINITIONS:
		var definition: Array = DEFINITIONS[id]
		result.append({
			"id": id,
			"title": definition[0],
			"description": definition[1],
			"unlocked": save_manager != null and save_manager.is_unlocked(id)
		})
	return result
