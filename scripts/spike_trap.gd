extends Area2D
## Bẫy gai sàn (phong cách Soul Knight): lặp vòng AN TOÀN -> NGUY HIỂM -> AN TOÀN.
## Gây sát thương định kỳ cho người chơi khi đang đứng lên lúc gai đang bung ra (frame 2-3).
## Dựng hoàn toàn bằng code (giống _spawn_chest_decor trong dungeon.gd) nên không cần file .tscn riêng.

var sprite: AnimatedSprite2D
var _t: float = 0.0
var player_inside: bool = false

const CYCLE: float = 2.4
const DANGER_START: float = 1.2
const DANGER_END: float = 2.0
const DAMAGE: int = 8

func _ready() -> void:
	collision_layer = 0
	collision_mask = Global.L_PLAYER
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(22.0, 22.0)
	shape.shape = rect
	add_child(shape)

	sprite = AnimatedSprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(2.0, 2.0)   # texture gốc 16px, khớp Global.TILE=32px
	add_child(sprite)
	var frames := SpriteFrames.new()
	frames.add_animation("cycle")
	frames.set_animation_loop("cycle", false)
	for i in 4:
		var img := Image.new()
		if img.load("res://assets/dungeon/floor_spikes_anim_f%d.png" % i) == OK:
			frames.add_frame("cycle", ImageTexture.create_from_image(img))
	sprite.sprite_frames = frames
	sprite.animation = "cycle"
	sprite.frame = 0

	_t = randf() * CYCLE   # lệch pha ngẫu nhiên để các bẫy không bung cùng lúc
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(b: Node) -> void:
	if b.is_in_group("player"):
		player_inside = true


func _on_body_exited(b: Node) -> void:
	if b.is_in_group("player"):
		player_inside = false


func _process(delta: float) -> void:
	_t = fmod(_t + delta, CYCLE)
	var danger: bool = _t >= DANGER_START and _t < DANGER_END
	if _t < DANGER_START:
		sprite.frame = 0
	elif _t < DANGER_START + 0.2:
		sprite.frame = 1
	elif _t < DANGER_END - 0.2:
		sprite.frame = 3
	elif _t < DANGER_END:
		sprite.frame = 2
	else:
		sprite.frame = 0
	if danger and player_inside:
		var p = Global.player
		if is_instance_valid(p) and p.has_method("take_damage"):
			p.take_damage(DAMAGE, global_position, 0.0)
