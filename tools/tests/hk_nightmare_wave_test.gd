extends SceneTree
## Nightmare: đợt quái thứ hai của phòng khoá (ordeal.gd wave2_due/wave2_plan).
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func _init() -> void:
	var O = load("res://hk/ordeal.gd")
	ck(O.wave2_due(0, 40.0, false), "hết quái, còn giờ: sinh")
	ck(O.wave2_due(1, 40.0, false), "còn 1 quái: sinh")
	ck(not O.wave2_due(2, 40.0, false), "còn 2 quái: chưa")
	ck(not O.wave2_due(0, 40.0, true), "đã sinh: không sinh lại")
	ck(not O.wave2_due(0, O.WAVE2_LEFT - 0.1, false), "còn dưới %ds: không sinh" % int(O.WAVE2_LEFT))
	var sp: Array = [
		{"type": "d", "pos": Vector2(10, 0)},
		{"type": "c", "pos": Vector2(100, 0)},
		{"type": "f", "pos": Vector2(900, 0)},
		{"type": "c", "pos": Vector2(500, 0)}]
	var plan: Array = O.wave2_plan(sp, Vector2(0, 0))
	ck(plan.size() == O.WAVE2_N, "đúng số quái")
	for p in plan:
		ck(p["type"] == "c", "loại mặt đất đầu tiên (bỏ dropper)")
		ck(p["pos"] != Vector2(10, 0), "không dùng điểm dropper")
	ck(plan[0]["pos"] == Vector2(900, 0), "ưu tiên điểm xa người chơi nhất")
	ck(O.wave2_plan([{"type": "d", "pos": Vector2.ZERO}], Vector2.ZERO).is_empty(), "chỉ có dropper: không đợt 2")
	ck(O.wave2_plan([{"type": "c", "pos": Vector2(5, 5)}], Vector2.ZERO).size() == O.WAVE2_N, "một điểm vẫn đủ số quái")
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
