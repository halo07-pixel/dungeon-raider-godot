extends Camera2D
## Camera bám Player + rung màn hình (trauma giảm dần bằng Tween).

var trauma: float = 0.0
var max_offset: float = 18.0
var _tw: Tween


func _ready() -> void:
	Global.camera = self


func shake(strength: float, time: float = 0.2) -> void:
	trauma = minf(1.0, maxf(trauma, strength))
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(self, "trauma", 0.0, time)


func _process(_delta: float) -> void:
	var t: float = trauma * trauma
	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * max_offset * t
