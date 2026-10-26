extends Node2D
## Chế độ soi (F3): vẽ chồng mọi hộp thật đang dùng để thấy hình/hộp có khớp không. Chỉ đọc trạng thái, không thay đổi gì.
## Xanh lá = hộp người chơi, đỏ = vùng chém, vàng = thân quái/boss, cam = vùng gây sát thương, trắng = phần nhìn thấy của vật tương tác,
## xanh dương = vùng tương tác, đỏ đậm = gai, tím = cửa, lục lam = bục một chiều, xám = tường đặc.
var world: Node2D

func _ready() -> void:
	z_index = 100
	visible = false

func toggle() -> void:
	visible = not visible
	queue_redraw()

func _process(_d: float) -> void:
	if visible:
		queue_redraw()

func _box(r: Rect2, c: Color, w: float = 1.5) -> void:
	draw_rect(r, c, false, w)

func _draw() -> void:
	if world == null or not is_instance_valid(world.room) or not is_instance_valid(world.player):
		return
	var room: Node2D = world.room
	for r in room.solids:
		_box(r, Color(0.6, 0.6, 0.7, 0.35), 1.0)
	for r in room.oneways:
		_box(r, Color(0.2, 1, 0.9))
	for r in room.hazards:
		_box(r, Color(1, 0.15, 0.15))
	for ch in room.doors:
		_box(room.doors[ch], Color(0.9, 0.3, 1))
	for it in room.interactables:
		_box(it["rect"], Color(0.3, 0.5, 1))
		_box(it["vis"], Color(1, 1, 1, 0.8), 1.0)
	var p: Node2D = world.player
	_box(Rect2(p.global_position - p.BODY * 0.5, p.BODY), Color(0.2, 1, 0.3), 2.0)
	if p.is_attacking():
		_box(p.attack_rect(), Color(1, 0.2, 0.2), 2.0)
	for e in get_tree().get_nodes_in_group("hk_enemy"):
		_box(e.body_rect(), Color(1, 0.9, 0.2), 2.0)
		_box(e.contact_rect(), Color(1, 0.55, 0.1), 1.5)
	for b in get_tree().get_nodes_in_group("hk_boss"):
		_box(b.body_rect(), Color(1, 0.9, 0.2), 2.0)
		var ar: Rect2 = b.attack_rect()
		if ar.size != Vector2.ZERO:
			_box(ar, Color(1, 0.2, 0.2), 2.0)
	draw_string(ThemeDB.fallback_font, world.cam.global_position - Vector2(300, 190), "DEBUG F3: hộp thật", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 0.4))
