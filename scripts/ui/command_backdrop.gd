extends Control
class_name CommandBackdrop

var start_color := Color("#02070d")
var end_color := Color("#10222d")
var _phase := 0.0
var _redraw_clock := 0.0


func configure(start_tint: Color, end_tint: Color) -> void:
	start_color = start_tint
	end_color = end_tint
	queue_redraw()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _process(delta: float) -> void:
	_phase = fmod(_phase + delta, 12.0)
	_redraw_clock += delta
	if _redraw_clock >= 0.08:
		_redraw_clock = 0.0
		queue_redraw()


func _draw() -> void:
	var canvas_size := size
	if canvas_size.x < 2.0 or canvas_size.y < 2.0:
		return
	for band in range(14):
		var t := float(band) / 13.0
		var band_color := start_color.lerp(end_color, t).darkened(0.20)
		draw_rect(Rect2(0.0, canvas_size.y * t, canvas_size.x, canvas_size.y / 13.0 + 2.0), band_color, true)

	var grid_color := Color(0.18, 0.50, 0.62, 0.065)
	var grid_step := maxf(38.0, canvas_size.x / 28.0)
	for x in range(0, int(canvas_size.x) + int(grid_step), int(grid_step)):
		draw_line(Vector2(x, 0), Vector2(x, canvas_size.y), grid_color, 1.0)
	for y in range(0, int(canvas_size.y) + int(grid_step), int(grid_step)):
		draw_line(Vector2(0, y), Vector2(canvas_size.x, y), grid_color, 1.0)

	_draw_monitor_bank(canvas_size)
	_draw_tactical_map(canvas_size)
	_draw_emblem(canvas_size)
	_draw_hud_marks(canvas_size)
	var scan_y := lerpf(canvas_size.y * 0.10, canvas_size.y * 0.90, _phase / 12.0)
	draw_rect(Rect2(0, scan_y, canvas_size.x, 2), Color(0.30, 0.84, 0.94, 0.10), true)
	draw_rect(Rect2(0, scan_y + 2, canvas_size.x, 16), Color(0.15, 0.55, 0.68, 0.018), true)


func _draw_monitor_bank(canvas_size: Vector2) -> void:
	var bank := Rect2(canvas_size.x * 0.54, canvas_size.y * 0.15, canvas_size.x * 0.34, canvas_size.y * 0.58)
	draw_rect(bank, Color(0.015, 0.045, 0.070, 0.36), true)
	draw_rect(bank, Color(0.20, 0.57, 0.68, 0.15), false, 1.0)
	for row in range(6):
		var y := bank.position.y + 24.0 + row * (bank.size.y - 48.0) / 5.0
		draw_line(Vector2(bank.position.x + 18.0, y), Vector2(bank.end.x - 18.0, y), Color(0.22, 0.69, 0.80, 0.13), 1.0)
		var pulse_width := 46.0 + fmod(_phase * 36.0 + row * 33.0, 110.0)
		draw_rect(Rect2(bank.position.x + 34.0, y - 4.0, pulse_width, 3.0), Color(0.32, 0.84, 0.94, 0.22), true)
	for column in range(4):
		var x := bank.position.x + 26.0 + column * (bank.size.x - 52.0) / 3.0
		draw_line(Vector2(x, bank.position.y + 20.0), Vector2(x, bank.end.y - 20.0), Color(0.18, 0.52, 0.66, 0.09), 1.0)


func _draw_tactical_map(canvas_size: Vector2) -> void:
	var map_rect := Rect2(canvas_size.x * 0.43, canvas_size.y * 0.49, canvas_size.x * 0.31, canvas_size.y * 0.28)
	draw_rect(map_rect, Color(0.01, 0.06, 0.08, 0.28), true)
	draw_rect(map_rect, Color(0.28, 0.64, 0.72, 0.12), false, 1.0)
	var points := PackedVector2Array([
		map_rect.position + Vector2(22, 48), map_rect.position + Vector2(55, 30), map_rect.position + Vector2(92, 45),
		map_rect.position + Vector2(126, 25), map_rect.position + Vector2(172, 48), map_rect.position + Vector2(210, 32),
		map_rect.position + Vector2(244, 57), map_rect.position + Vector2(222, 94), map_rect.position + Vector2(180, 82),
		map_rect.position + Vector2(140, 114), map_rect.position + Vector2(92, 88), map_rect.position + Vector2(48, 106)
	])
	for index in range(points.size()):
		var next_index := (index + 1) % points.size()
		draw_line(points[index], points[next_index], Color(0.34, 0.66, 0.74, 0.20), 1.0)
	var target_point := map_rect.position + Vector2(map_rect.size.x * 0.72, map_rect.size.y * 0.60)
	draw_circle(target_point, 5.0 + sin(_phase * 3.0) * 1.5, Color(1.0, 0.16, 0.08, 0.55))
	draw_arc(target_point, 18.0, 0.0, TAU, 28, Color(1.0, 0.20, 0.12, 0.48), 1.0)
	draw_line(target_point - Vector2(26, 0), target_point + Vector2(26, 0), Color(1.0, 0.20, 0.12, 0.38), 1.0)
	draw_line(target_point - Vector2(0, 26), target_point + Vector2(0, 26), Color(1.0, 0.20, 0.12, 0.38), 1.0)


func _draw_emblem(canvas_size: Vector2) -> void:
	var center := Vector2(canvas_size.x * 0.56, canvas_size.y * 0.20)
	var color := Color(0.34, 0.70, 0.80, 0.12)
	draw_arc(center, 48.0, 0.0, TAU, 40, color, 2.0)
	draw_arc(center, 38.0, 0.0, TAU, 40, Color(0.34, 0.70, 0.80, 0.08), 1.0)
	draw_line(center + Vector2(0, -38), center + Vector2(0, 42), color, 2.0)
	draw_line(center + Vector2(-36, 10), center + Vector2(0, 42), color, 2.0)
	draw_line(center + Vector2(36, 10), center + Vector2(0, 42), color, 2.0)
	draw_circle(center + Vector2(0, -10), 5.0, Color(0.50, 0.82, 0.90, 0.20))


func _draw_hud_marks(canvas_size: Vector2) -> void:
	for point in [Vector2(28, 28), Vector2(canvas_size.x - 58, 28), Vector2(28, canvas_size.y - 48), Vector2(canvas_size.x - 58, canvas_size.y - 48)]:
		draw_line(point, point + Vector2(24, 0), Color(0.28, 0.68, 0.78, 0.38), 1.0)
		draw_line(point, point + Vector2(0, 18), Color(0.28, 0.68, 0.78, 0.38), 1.0)
	for index in range(18):
		var x := fmod(float(index) * 79.0 + _phase * 22.0, canvas_size.x)
		var y := canvas_size.y * (0.12 + float(index % 7) * 0.11)
		draw_rect(Rect2(x, y, 2.0, 2.0), Color(0.35, 0.80, 0.90, 0.16), true)
