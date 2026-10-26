extends Node2D
## Phòng nhìn ngang: danh sách hình chữ nhật đặc (sàn, tường, bục). Vừa vẽ vừa tạo va chạm (layer 1 = world).
var rects: Array = []
const FILL := Color(0.10, 0.11, 0.16)
const EDGE := Color(0.32, 0.36, 0.50)

func _ready() -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	add_child(body)
	for r in rects:
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size = r.size
		cs.shape = sh
		cs.position = r.position + r.size * 0.5
		body.add_child(cs)

func _draw() -> void:
	for r in rects:
		draw_rect(r, FILL)
		draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), EDGE)

func bounds() -> Rect2:
	var b: Rect2 = rects[0]
	for r in rects:
		b = b.merge(r)
	return b
