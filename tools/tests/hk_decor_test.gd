extends SceneTree
## Test trang trí phòng: loại hợp lệ + có sprite, ô phủ trống, tối đa 5/phòng (3 đứng sàn + 2 treo tường), chỉ trang trí (không hộp), bật/tắt theo Atmosphere.
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func _init() -> void:
	await process_frame
	var St = load("res://hk/state.gd")
	var WD = load("res://hk/world_data.gd")
	var SP = load("res://hk/sprites.gd")
	var DEC = load("res://hk/decor.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_decor_save.json"
	St.delete_save()
	var height: Dictionary = {"column": 3, "column_wall": 3, "crate": 2, "skull": 1, "fountain_red": 3, "fountain_blue": 3, "tome": 1, "sigil": 1, "banner_red": 1, "banner_blue": 1, "banner_green": 1, "banner_yellow": 1, "hole": 1, "goo": 2}
	var rooms: Dictionary = WD.load_all()
	var total: int = 0
	for rid in rooms:
		var items: Array = rooms[rid]["decor"]
		total += items.size()
		ck(items.size() <= 5, "%s: tối đa 5 món (%d)" % [rid, items.size()])
		var per: Dictionary = {}
		for d in items:
			per[d["kind"]] = int(per.get(d["kind"], 0)) + 1
		for k in per:
			ck(int(per[k]) <= 3, "%s: loại %s lặp %d lần (tối đa 3)" % [rid, k, per[k]])
		var g: Array = rooms[rid]["grid"]
		for d in items:
			var k: String = String(d["kind"])
			ck(height.has(k), "%s: loại lạ %s" % [rid, k])
			if not height.has(k):
				continue
			var base: String = DEC.base_of(k)
			ck(SP.anim(base, 4.0) != null, "%s: thiếu sprite %s" % [rid, base])
			for y in range(int(d["row"]) - int(height[k]) + 1, int(d["row"]) + 1):
				for x in range(int(d["col"]) - 1, int(d["col"]) + 2):
					ck(String(g[y])[x] == ".", "%s: %s đè ô (%d,%d)" % [rid, k, x, y])
	ck(total >= 40 and total <= 5 * rooms.size(), "có trang trí vừa phải trong các phòng (%d)" % total)
	# trong phòng thật: là node con chỉ để vẽ, bật/tắt theo STATE.atmosphere_on
	var w := Node2D.new()
	w.set_script(load("res://hk/world.gd"))
	root.add_child(w)
	await create_timer(0.3).timeout
	var dn: Node = null
	for c in w.room.get_children():
		if c.get_script() == DEC:
			dn = c
	ck(dn != null, "phòng đầu có node trang trí")
	if dn:
		ck(not dn.items.is_empty(), "node có món")
		ck(dn.visible, "mặc định hiện")
		St.atmosphere_on = false
		await process_frame
		await process_frame
		ck(not dn.visible, "tắt Atmosphere thì ẩn")
		St.atmosphere_on = true
		await process_frame
		await process_frame
		ck(dn.visible, "bật lại thì hiện")
	St.delete_save()
	print("hk_decor_test: ", "OK" if fails == 0 else "%d lỗi" % fails)
	quit(1 if fails > 0 else 0)
