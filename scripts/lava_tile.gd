extends Area2D
## Ô Dung Nham (bẫy sàn Biome 4 - Địa Ngục): luôn "mở", gây sát thương theo nhịp
## và áp trạng thái Burn khi người chơi đứng trong vùng. Mẫu theo poison_tile.gd.

const TICK_INTERVAL: float = 0.6
const DAMAGE: int = 5
const BURN_TICKS: int = 3

var player_inside: bool = false
var _tick_t: float = 0.0

static var _frames_cache: SpriteFrames

func _ready() -> void:
	collision_layer = 0
	collision_mask = Global.L_PLAYER
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(24.0, 24.0)
	shape.shape = rect
	add_child(shape)

	var sprite := AnimatedSprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(2.0, 2.0)
	add_child(sprite)
	if _frames_cache == null:
		_frames_cache = SpriteFrames.new()
		_frames_cache.add_animation("lava")
		_frames_cache.set_animation_speed("lava", 3.0)
		_frames_cache.set_animation_loop("lava", true)
		for i in 4:
			var tex := Global.load_tex("res://assets/dungeon/floor_lava_anim_f%d.png" % i)
			if tex:
				_frames_cache.add_frame("lava", tex)
	sprite.sprite_frames = _frames_cache
	sprite.play("lava")

	_tick_t = randf() * TICK_INTERVAL
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(b: Node) -> void:
	if b.is_in_group("player"):
		player_inside = true


func _on_body_exited(b: Node) -> void:
	if b.is_in_group("player"):
		player_inside = false


func _process(delta: float) -> void:
	if not player_inside:
		return
	_tick_t += delta
	if _tick_t >= TICK_INTERVAL:
		_tick_t = 0.0
		var p = Global.player
		if is_instance_valid(p) and p.has_method("take_damage"):
			if p.has_method("apply_status"):
				p.apply_status("burn", BURN_TICKS)
			if not (p.has_method("is_invulnerable") and p.is_invulnerable()):
				p.take_damage(DAMAGE, global_position, 0.0, false, true, "hazard:lava")
