extends Node
class_name AudioManager

var sfx_player: AudioStreamPlayer
var music_player: AudioStreamPlayer
var ambience_player: AudioStreamPlayer
var cache: Dictionary = {}
var master_volume := 0.85
var music_volume := 0.60
var sfx_volume := 0.85


func _ready() -> void:
	sfx_player = AudioStreamPlayer.new()
	music_player = AudioStreamPlayer.new()
	ambience_player = AudioStreamPlayer.new()
	add_child(sfx_player)
	add_child(music_player)
	add_child(ambience_player)
	_apply_volumes()


func set_volumes(master: float, music: float, sfx: float) -> void:
	master_volume = master
	music_volume = music
	sfx_volume = sfx
	_apply_volumes()


func _apply_volumes() -> void:
	if not is_instance_valid(sfx_player):
		return
	sfx_player.volume_db = linear_to_db(max(0.001, master_volume * sfx_volume))
	music_player.volume_db = linear_to_db(max(0.001, master_volume * music_volume))
	ambience_player.volume_db = linear_to_db(max(0.001, master_volume * music_volume * 0.55))


func play_sfx(event_name: String) -> void:
	if not cache.has(event_name):
		cache[event_name] = _create_event(event_name)
	var stream: AudioStream = cache[event_name]
	if stream != null:
		sfx_player.stream = stream
		sfx_player.play()


func play_music(cue: String) -> void:
	stop_music()
	if cue == "none":
		return
	var key := "music_" + cue
	if not cache.has(key):
		match cue:
			"menu":
				var title_music: AudioStream = _load_music_track("res://assets/audio/title_music_epic.mp3", true)
				cache[key] = title_music if title_music != null else _make_melody([110.0, 138.59, 164.81, 138.59], 0.42, true)
			"battle":
				var battle_music: AudioStream = _load_music_track("res://assets/audio/in_game_music.mp3", true)
				cache[key] = battle_music if battle_music != null else _make_melody([73.42, 73.42, 98.0, 82.41], 0.28, true)
			"victory":
				var victory_music: AudioStream = _load_music_track("res://assets/audio/beat_the_game_music.mp3", true)
				cache[key] = victory_music if victory_music != null else _make_melody([261.63, 329.63, 392.0, 523.25, 659.25], 0.32, false)
			"credits":
				var credits_music: AudioStream = _load_music_track("res://assets/audio/credits_music.mp3", false)
				cache[key] = credits_music if credits_music != null else _make_melody([130.81, 164.81, 196.0, 246.94, 196.0, 164.81], 0.55, false)
			"poster_death":
				var death_music: AudioStream = _load_music_track("res://assets/audio/tragic_poster_miscalculation.mp3", false)
				cache[key] = death_music if death_music != null else _make_melody([110.0, 82.41, 55.0], 0.38, false)
			_: cache[key] = _make_melody([110.0], 1.0, true)
	music_player.stream = cache[key]
	music_player.play(0.0)


func stop_music() -> void:
	if not is_instance_valid(music_player):
		return
	music_player.stop()
	music_player.seek(0.0)


func _load_music_track(path: String, should_loop: bool) -> AudioStream:
	var track: AudioStream = load(path)
	if track is AudioStreamMP3:
		track.loop = should_loop
		track.loop_offset = 0.0
	return track


func play_ambience(enabled: bool) -> void:
	if not enabled:
		ambience_player.stop()
		return
	if not cache.has("ambience"):
		cache["ambience"] = _make_ambience()
	ambience_player.stream = cache["ambience"]
	ambience_player.play()


func _create_event(event_name: String) -> AudioStream:
	match event_name:
		"menu_move": return _make_tone(720.0, 0.045, 0.08, 0.0)
		"menu_confirm": return _make_tone(420.0, 0.14, 0.22, 0.0)
		"warning": return _make_melody([110.0, 82.41], 0.20, false)
		"loading": return _make_tone(260.0, 0.08, 0.12, 0.0)
		"gunshot":
			var gunshot: AudioStream = load("res://assets/audio/gunshot.mp3")
			return gunshot if gunshot != null else _make_tone(78.0, 0.23, 0.45, 0.82)
		"duck_quack":
			var duck_quack: AudioStream = load("res://assets/audio/duck_quack.mp3")
			return duck_quack if duck_quack != null else _make_tone(480.0, 0.28, 0.32, 0.12)
		"impact": return _make_tone(145.0, 0.18, 0.34, 0.44)
		"confetti": return _make_tone(900.0, 0.35, 0.18, 0.55)
		"achievement": return _make_melody([523.25, 659.25, 783.99], 0.13, false)
		"countdown": return _make_tone(330.0, 0.10, 0.16, 0.0)
		_: return _make_tone(440.0, 0.08, 0.10, 0.0)


func _make_tone(frequency: float, duration: float, amplitude: float, noise_mix: float) -> AudioStreamWAV:
	var sample_rate := 22050
	var sample_count := int(duration * sample_rate)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for i in sample_count:
		var t := float(i) / sample_rate
		var envelope := pow(1.0 - float(i) / max(1.0, sample_count), 2.0)
		var tonal := sin(TAU * frequency * t) + 0.35 * sin(TAU * frequency * 2.01 * t)
		var noise := randf_range(-1.0, 1.0)
		var sample := ((1.0 - noise_mix) * tonal + noise_mix * noise) * amplitude * envelope
		_write_sample(bytes, i, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = bytes
	return stream


func _make_melody(notes: Array, note_duration: float, looped: bool) -> AudioStreamWAV:
	var sample_rate := 22050
	var note_samples := int(note_duration * sample_rate)
	var sample_count := note_samples * notes.size()
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for i in sample_count:
		var note_index := mini(int(i / note_samples), notes.size() - 1)
		var local_i := i % note_samples
		var t := float(local_i) / sample_rate
		var env: float = min(1.0, float(local_i) / 300.0) * pow(1.0 - float(local_i) / note_samples, 0.6)
		var f := float(notes[note_index])
		var sample: float = (sin(TAU * f * t) + 0.24 * sin(TAU * f * 2.0 * t)) * 0.16 * env
		_write_sample(bytes, i, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = bytes
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = sample_count
	return stream


func _make_ambience() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 4.0
	var sample_count := int(duration * sample_rate)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for i in sample_count:
		var t := float(i) / sample_rate
		var pulse := 0.55 + 0.45 * sin(TAU * 0.25 * t)
		var sample := (sin(TAU * 48.0 * t) * 0.055 + sin(TAU * 61.0 * t) * 0.025) * pulse
		_write_sample(bytes, i, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = sample_count
	return stream


func _write_sample(bytes: PackedByteArray, index: int, sample: float) -> void:
	var value := clampi(int(sample * 32767.0), -32768, 32767)
	if value < 0:
		value += 65536
	bytes[index * 2] = value & 255
	bytes[index * 2 + 1] = (value >> 8) & 255
