extends Node2D
## Trang trí phòng (cột, cờ, đài phun, sọ...): chỉ vẽ, không va chạm, không đụng hộp. Tắt cùng tuỳ chọn Atmosphere.
const TILE: int = 32
const STATE = preload("res://hk/state.gd")
const SPRITES = preload("res://hk/sprites.gd")
var items: Array = []   # {kind, col, row} từ header `deco:`; (col,row) = ô chứa chân sprite

## Tên ảnh của loại trang trí; hai sprite có sẵn (column, crate) và hoạt ảnh có tên riêng.
static func base_of(kind: String) -> String:
	if kind.begins_with("fountain"):
		return "decor_%s_anim" % kind
	if kind in ["column", "crate"]:
		return kind
	if kind in ["tome", "sigil"]:
		return kind + "_anim"
	return "decor_" + kind

func _process(_d: float) -> void:
	visible = STATE.atmosphere_on
	if visible:
		queue_redraw()

## Độ lắc ngang (px) của món trang trí khi người chơi chạy qua gần: mạnh dần khi lại gần, tối đa SWAY_MAX, đứng yên thì không lắc.
const SWAY_RANGE: float = 120.0
const SWAY_MAX: float = 3.0
func sway(foot: Vector2, player_pos: Vector2, speed: float) -> float:
	var near: float = clampf(1.0 - foot.distance_to(player_pos) / SWAY_RANGE, 0.0, 1.0)
	return near * SWAY_MAX * clampf(speed / 150.0, 0.0, 1.0) * sin(Time.get_ticks_msec() * 0.012)

func _draw() -> void:
	var ps := get_tree().get_nodes_in_group("hk_player")
	for d in items:
		var foot := Vector2((float(d["col"]) + 0.5) * TILE, (float(d["row"]) + 1.0) * TILE)
		if not ps.is_empty():
			draw_set_transform(Vector2(sway(foot, ps[0].global_position, absf(ps[0].velocity.x)), 0.0))
		SPRITES.draw_body(self, base_of(String(d["kind"])), foot, 2.0, false, Color(0.8, 0.8, 0.85), 4.0)
