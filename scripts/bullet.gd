extends Area2D
## Đạn (Area2D) nâng cấp: Tích hợp hiệu ứng Sử thi/Huyền thoại (Xuyên, Nổ, Chậm, Xích sét).

var dir: Vector2 = Vector2.RIGHT
var damage: int = 10
var speed: float = 500.0
var life: float = 1.0
var color: Color = Color.WHITE
var radius: float = 5.0
var pierce: bool = false
var from_player: bool = true
var knock: float = 140.0
var effect: String = ""
var _hit: Array = []

@onready var life_timer: Timer = $Life

func setup(p_from_player: bool, p_dir: Vector2, p_dmg: int, p_speed: float, p_life: float, p_color: Color, p_rad: float, p_pierce: bool = false, p_effect: String = "") -> void:
	from_player = p_from_player
	dir = p_dir.normalized()
	damage = p_dmg
	speed = p_speed
	life = p_life
	color = p_color
	radius = p_rad
	pierce = p_pierce
	effect = p_effect
	knock = 140.0 if p_from_player else 220.0
	rotation = dir.angle()

func _ready() -> void:
	if from_player:
		collision_layer = Global.L_PBULLET
		collision_mask = Global.L_WORLD | Global.L_ENEMY
	else:
		collision_layer = Global.L_EBULLET
		collision_mask = Global.L_WORLD | Global.L_PLAYER
		add_to_group("enemy_bullets") # Để Dao găm nhận diện xóa đạn
		
	var s := CircleShape2D.new()
	s.radius = radius
	$Shape.shape = s
	body_entered.connect(_on_body_entered)
	life_timer.timeout.connect(_on_timeout)
	life_timer.start(life)

func _physics_process(delta: float) -> void:
	position += dir * speed * delta

func _on_body_entered(body: Node) -> void:
	if body.has_method("take_damage"):
		if not from_player and body.has_method("is_invulnerable") and body.is_invulnerable():
			return
		if pierce:
			if _hit.has(body):
				return
			_hit.append(body)
			
		body.take_damage(damage, global_position - dir * 8.0, knock)
		
		# Kích hoạt trạng thái lên quái (Sử thi / Huyền thoại)
		if from_player and body.has_method("apply_status"):
			if effect == "slow":
				body.apply_status("slow", 2.0)
			elif effect == "chain": # Xích sét laser Huyền thoại
				_chain_lightning(body)
				
		if not pierce:
			_impact()
	else:
		_impact()

func _chain_lightning(first_target: Node) -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != first_target and e.alive and e.global_position.distance_to(first_target.global_position) < 150.0:
			e.take_damage(int(damage * 0.5), first_target.global_position, 0.0)
			Global.burst(e.global_position, Color.YELLOW, 2, 80.0, 1.0)

func _on_timeout() -> void:
	_impact()

func _impact() -> void:
	if effect == "explode": # Shotgun Huyền thoại (Nổ dung nham)
		Global.burst(global_position, Color(1.0, 0.3, 0.1), 15, 150.0, 2.0)
		for e in get_tree().get_nodes_in_group("enemies"):
			if e.has_method("take_damage") and e.alive and e.global_position.distance_to(global_position) < 70.0:
				e.take_damage(damage, global_position, knock * 1.5)
	else:
		Global.burst(global_position, color, 5, 100.0, 1.0)
	queue_free()

func _draw() -> void:
	var trail: float = radius * (6.0 if pierce else 2.5)
	draw_line(Vector2(-trail, 0.0), Vector2.ZERO, Color(color, 0.5), radius * 1.4)
	draw_circle(Vector2.ZERO, radius, color)
	draw_circle(Vector2.ZERO, radius * 0.5, Color.WHITE)
