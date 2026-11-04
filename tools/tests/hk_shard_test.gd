extends SceneTree
## Mảnh mặt nạ: đủ SHARDS_PER thì +1 mặt nạ tối đa (một lần), save/load, save hỏng sai kiểu, rương hốc cho mảnh rồi Geo khi đã đủ.
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func _init() -> void:
	await process_frame
	var St = load("res://hk/state.gd")
	St.reset()
	var base: int = St.max_hp()
	for i in St.SHARDS_PER - 1:
		ck(not St.add_shard(), "chưa đủ bộ")
	ck(St.max_hp() == base, "chưa đủ mảnh: mặt nạ không đổi")
	ck(St.add_shard(), "mảnh cuối báo đủ bộ")
	ck(St.max_hp() == base + 1, "đủ bộ: +1 mặt nạ tối đa (%d -> %d)" % [base, St.max_hp()])
	ck(not St.add_shard() and St.shards == St.SHARDS_PER and St.max_hp() == base + 1, "đủ rồi không nhận thêm")
	var d: Dictionary = St.to_dict()
	St.reset()
	ck(St.shards == 0 and St.max_hp() == base, "reset xoá mảnh")
	St.from_dict(d)
	ck(St.shards == St.SHARDS_PER and St.max_hp() == base + 1, "save/load giữ mảnh")
	for bad in [[], "x", null, -3, 99, {}]:
		d["shards"] = bad
		St.from_dict(d)
		ck(St.shards >= 0 and St.shards <= St.SHARDS_PER, "shards hỏng %s không lỗi, nằm trong khoảng" % str(bad))
	St.reset()
	St.hp_bonus = 2
	for i in St.SHARDS_PER:
		St.add_shard()
	ck(St.max_hp() == base + 3, "cộng với mặt nạ mua ở shop (trần 2) = +3")
	print("DONE fails=", fails)
	quit()
