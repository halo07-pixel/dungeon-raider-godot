extends Control
## Minimap: hiện phòng đã vào + phòng kề cửa đã biết.

const CW: float = 18.0
const CH: float = 13.0

var dungeon = null


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if dungeon == null or not is_instance_valid(dungeon) or dungeon.rooms.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.5))
	for c in dungeon.rooms:
		var room: Dictionary = dungeon.rooms[c]
		var known: bool = room["visited"]
		if not known:
			for d in room["doors"]:
				if dungeon.rooms[c + d]["visited"]:
					known = true
		if not known:
			continue
		var col: Color = Color(0.5, 0.5, 0.55)
		if room["type"] == "boss":
			col = Color(0.9, 0.2, 0.2)
		elif room["type"] == "treasure":
			col = Color(1.0, 0.85, 0.3)
		if not room["visited"]:
			col = col.darkened(0.45)
		if c == dungeon.current_cell:
			col = Color.WHITE
		draw_rect(Rect2(Vector2(c.x * CW + 2.0, c.y * CH + 2.0), Vector2(CW - 4.0, CH - 4.0)), col)
