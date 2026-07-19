extends Button
class_name CommandButton

var _normal_style: StyleBoxFlat
var _hover_style: StyleBoxFlat
var _pressed_style: StyleBoxFlat
var _focus_style: StyleBoxFlat
var _pointer_hovered := false
var _pointer_pressed := false


func set_command_styles(normal_style: StyleBoxFlat, hover_style: StyleBoxFlat, pressed_style: StyleBoxFlat, focus_style: StyleBoxFlat) -> void:
	_normal_style = normal_style
	_hover_style = hover_style
	_pressed_style = pressed_style
	_focus_style = focus_style
	add_theme_stylebox_override("focus", _focus_style)
	_apply_pointer_visual()


func set_pointer_hovered(value: bool) -> bool:
	if _pointer_hovered == value:
		return false
	_pointer_hovered = value
	_apply_pointer_visual()
	return value


func set_pointer_pressed(value: bool) -> void:
	_pointer_pressed = value
	_apply_pointer_visual()


func _apply_pointer_visual() -> void:
	if _normal_style == null:
		return
	var visual_style := _pressed_style if _pointer_pressed else (_hover_style if _pointer_hovered else _normal_style)
	add_theme_stylebox_override("normal", visual_style)
	add_theme_stylebox_override("hover", visual_style)
	add_theme_stylebox_override("pressed", visual_style)
