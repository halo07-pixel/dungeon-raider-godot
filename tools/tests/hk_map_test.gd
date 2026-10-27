extends SceneTree
## Test bản đồ: biểu tượng (bench/thương nhân/vật chưa lấy/boss chưa hạ/rương/cửa chưa đến), ghim (đặt/gỡ/giới hạn/lưu/đọc/dữ liệu hỏng).
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func kinds(icons: Array) -> Array:
	var out: Array = []
	for i in icons:
		out.append(String(i["k"]))
	return out

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	var WD = load("res://hk/world_data.gd")
	var Menu = load("res://hk/menu.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_map_save.json"
	St.delete_save()
	var rooms: Dictionary = WD.load_all()
	# bench + cửa chưa đến
	var g1: Dictionary = rooms["gate_1"].duplicate()
	g1["id"] = "gate_1"
	var k: Array = kinds(Menu.map_icons(g1))
	ck("bench" in k, "gate_1 có bench trên bản đồ")
	ck("exit" in k, "cửa tới phòng chưa đến hiện dấu exit")
	St.visit("gate_2")
	ck(not ("exit" in kinds(Menu.map_icons(g1))), "đã đến phòng đích thì hết dấu exit")
	# thương nhân
	var g4: Dictionary = rooms["gate_4"].duplicate()
	g4["id"] = "gate_4"
	ck("shop" in kinds(Menu.map_icons(g4)), "gate_4 có thương nhân")
	# vật chưa lấy: bàn thờ, bùa; boss chưa hạ
	var g8: Dictionary = rooms["gate_8"].duplicate()
	g8["id"] = "gate_8"
	ck("item" in kinds(Menu.map_icons(g8)), "bàn thờ dash chưa lấy hiện biểu tượng")
	St.set_flag("got_dash")
	ck(not ("item" in kinds(Menu.map_icons(g8))), "lấy rồi thì biểu tượng biến mất")
	var g6: Dictionary = rooms["gate_6"].duplicate()
	g6["id"] = "gate_6"
	ck("boss" in kinds(Menu.map_icons(g6)), "boss chưa hạ hiện biểu tượng")
	St.set_flag("boss_warden")
	ck(not ("boss" in kinds(Menu.map_icons(g6))), "hạ boss rồi thì hết biểu tượng")
	# rương: cờ theo đúng khoá của room.gd
	var g3: Dictionary = rooms["gate_3"].duplicate()
	g3["id"] = "gate_3"
	var chest: Dictionary = {}
	for i in Menu.map_icons(g3):
		if i["k"] == "cache":
			chest = i
	ck(not chest.is_empty(), "gate_3 có rương")
	if not chest.is_empty():
		St.set_flag("cache_gate_3:%d:%d" % [int(chest["c"].x), int(chest["c"].y)])
		ck(not ("cache" in kinds(Menu.map_icons(g3))), "mở rương rồi thì biểu tượng biến mất")
	# ghim
	St.pins = []
	ck(St.toggle_pin("gate_1", Vector2(100, 500)) == true and St.pins.size() == 1, "đặt ghim")
	ck(St.toggle_pin("gate_1", Vector2(120, 510)) == false and St.pins.is_empty(), "bấm gần ghim cũ thì gỡ")
	St.toggle_pin("gate_1", Vector2(100, 500))
	St.toggle_pin("gate_2", Vector2(100, 500))
	ck(St.pins.size() == 2, "hai phòng khác nhau, hai ghim")
	for i in 20:
		St.toggle_pin("gate_3", Vector2(float(i) * 200.0, 100))
	ck(St.pins.size() == St.MAX_PINS, "không quá %d ghim (%d)" % [St.MAX_PINS, St.pins.size()])
	ck(St.save(), "ghi save")
	var saved: Array = St.pins.duplicate(true)
	St.pins = []
	ck(St.load_save() and St.pins.size() == saved.size() and String(St.pins[0]["room"]) == "gate_1", "đọc lại đúng ghim")
	var d: Dictionary = St.to_dict()
	d["pins"] = [{"room": "gate_1", "x": 5, "y": 6}, "rác", {"room": 3, "x": 1, "y": 1}, {"room": "a"}, {"room": "gate_2", "x": "no", "y": 1}, null]
	St.from_dict(d)
	ck(St.pins.size() == 1 and String(St.pins[0]["room"]) == "gate_1", "save hỏng: chỉ giữ ghim hợp lệ (%d)" % St.pins.size())
	d.erase("pins")
	St.from_dict(d)
	ck(St.pins.is_empty(), "save cũ không có khoá pins: rỗng")
	St.reset()
	St.toggle_pin("gate_1", Vector2(1, 1))
	St.reset()
	ck(St.pins.is_empty(), "ván mới xoá ghim")
	St.delete_save()
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
