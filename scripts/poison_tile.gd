extends Area2D
## Ô Độc (bẫy sàn Biome 2 - Dark Necromancer, thay cho bẫy gai): KHÁC bẫy gai ở chỗ
## LUÔN "mở" (không có chu kỳ an toàn/nguy hiểm), gây sát thương liên tục định kỳ
## khi người chơi đứng trong vùng. Dựng hoàn toàn bằng code, theo mẫu spike_trap.gd.

var sprite: AnimatedSprite2D
var player_inside: bool = false
var _tick_t: float = 0.0

const TICK_INTERVAL: float = 0.5
const DAMAGE: int = 6

static var _frames_cache: SpriteFrames

func _ready() -> void:
	collision_layer = 0
	collision_mask = Global.L_PLAYER
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(24.0, 24.0)
	shape.shape = rect
	add_child(shape)

	sprite = AnimatedSprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(2.0, 2.0)
	add_child(sprite)
	if _frames_cache == null:
		_frames_cache = SpriteFrames.new()
		_frames_cache.add_animation("bubble")
		_frames_cache.set_animation_speed("bubble", 3.0)
		_frames_cache.set_animation_loop("bubble", true)
		for i in 4:
			var tex := Global.load_tex("res://assets/dungeon/floor_poison_anim_f%d.png" % i)
			if tex:
				_frames_cache.add_frame("bubble", tex)
	sprite.sprite_frames = _frames_cache
	sprite.play("bubble")

	_tick_t = randf() * TICK_INTERVAL # lệch pha ngẫu nhiên giữa các ô độc
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(b: Node) -> void:
	if b.is_in_group("player"):
		player_inside = true


func _on_body_exited(b: Node) -> void:
	if b.is_in_group("player"):
		player_inside = false


func _process(delta: float) -> void:
	_tick_t += delta
	if _tick_t >= TICK_INTERVAL:
		_tick_t = 0.0
		if player_inside:
			var p = Global.player
			if is_instance_valid(p) and p.has_method("take_damage"):
				if not (p.has_method("is_invulnerable") and p.is_invulnerable()):
					p.take_damage(DAMAGE, global_position, 0.0)
