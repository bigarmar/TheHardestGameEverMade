extends TextureRect
class_name PortraitController

const EXPRESSIONS := {
	"determined": 0,
	"impatient": 1,
	"concerned": 2,
	"disappointed": 3,
	"shocked": 4,
	"proud": 5,
	"exhausted": 6
}

var source_texture: Texture2D
var current_expression := "determined"
var blink_timer := 2.5


func _ready() -> void:
	if ResourceLoader.exists("res://assets/portraits/hero_expressions.png"):
		source_texture = load("res://assets/portraits/hero_expressions.png")
		set_expression(current_expression)
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_expression(expression: String) -> void:
	current_expression = expression if EXPRESSIONS.has(expression) else "determined"
	if source_texture == null:
		return
	var index := int(EXPRESSIONS[current_expression])
	var panel_width := source_texture.get_width() / 7.0
	var atlas := AtlasTexture.new()
	atlas.atlas = source_texture
	atlas.region = Rect2(panel_width * index + 4.0, 105.0, panel_width - 8.0, 470.0)
	texture = atlas
	_pulse()


func _process(delta: float) -> void:
	blink_timer -= delta
	if blink_timer <= 0.0:
		blink_timer = randf_range(2.0, 4.5)
		var tween := create_tween()
		tween.tween_property(self, "modulate", Color(0.55, 0.55, 0.55, 1.0), 0.055)
		tween.tween_property(self, "modulate", Color.WHITE, 0.075)


func _pulse() -> void:
	scale = Vector2(1.06, 1.06)
	pivot_offset = size * 0.5
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.24)

