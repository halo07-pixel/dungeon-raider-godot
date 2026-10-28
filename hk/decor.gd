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

func _draw() -> void:
	for d in items:
		var foot := Vector2((float(d["col"]) + 0.5) * TILE, (float(d["row"]) + 1.0) * TILE)
		SPRITES.draw_body(self, base_of(String(d["kind"])), foot, 2.0, false, Color(0.8, 0.8, 0.85), 4.0)
