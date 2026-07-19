extends CanvasLayer
class_name TransitionManager

var overlay: ColorRect


func _ready() -> void:
	layer = 95
	overlay = ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.02, 0.03, 0.05, 0.0)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)


func flash(color := Color(1.0, 0.12, 0.05, 0.78), duration := 0.38) -> void:
	overlay.color = color
	var tween := create_tween()
	tween.tween_property(overlay, "color:a", 0.0, duration)


func fade_in(duration := 0.45) -> void:
	overlay.color = Color(0.0, 0.0, 0.0, 1.0)
	var tween := create_tween()
	tween.tween_property(overlay, "color:a", 0.0, duration)

