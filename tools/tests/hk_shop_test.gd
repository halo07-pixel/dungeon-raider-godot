extends SceneTree
## Cửa hàng theo khu + giá mới + tiền thưởng boss lần đầu: mỗi khu bán bộ bùa riêng, mặt nạ/notch theo cấp, giá thấp hơn bản cũ,
## mua đúng trừ tiền, thưởng boss chỉ nhận một lần.
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func ids(stock: Array) -> Array:
	var out: Array = []
	for it in stock:
		out.append(it["id"])
	return out

func _init() -> void:
	await process_frame
	load("res://hk/input.gd").ensure()
	var St = load("res://hk/state.gd")
	var Shop = load("res://hk/shop.gd")
	var B = load("res://hk/boss.gd")
	St.boot = "keep"
	St.reset()
	St.save_path = "user://hk_shop_test_save.json"
	St.delete_save()
	var shop = Shop.new()
	root.add_child(shop)
	var gate: Array = ids(shop._stock("gate"))
	var vault: Array = ids(shop._stock("vault"))
	var arc: Array = ids(shop._stock("archive"))
	ck("swift_edge" in gate and "fortune" in gate and not ("frugal_soul" in gate), "gate bán bộ bùa của gate (%s)" % str(gate))
	ck("frugal_soul" in vault and "spring_nail" in vault and not ("swift_edge" in vault), "vault bán bộ bùa của vault (%s)" % str(vault))
	ck("second_wind" in arc and "shade_cloak" in arc and not ("fortune" in arc), "archive bán bộ bùa của archive (%s)" % str(arc))
	ck(shop._stock("").size() >= 9, "không chỉ định khu thì bán tất cả (test cũ)")
	# giá hạ so với bản cũ: bùa 120+40*cost, mặt nạ 250, notch 300
	for cid in ["swift_edge", "long_reach", "quick_focus"]:
		ck(Shop.charm_price(cid) < 120 + 40 * int(St.CHARMS[cid]["cost"]), "giá bùa %s thấp hơn bản cũ" % cid)
	ck(Shop.mask_price() < 250 and Shop.notch_price() < 300, "mặt nạ/notch rẻ hơn bản cũ")
	# cấp: gate chỉ bán cấp 1, vault bán cấp 2
	St.hp_bonus = 1
	ck(not ("mask" in ids(shop._stock("gate"))) and ("mask" in ids(shop._stock("vault"))), "mặt nạ thứ 2 chỉ bán từ vault")
	St.hp_bonus = 0
	# mua: trừ tiền, nhận bùa
	St.geo = 100
	shop.open(null, "gate")
	var idx: int = ids(shop._items).find("swift_edge")
	ck(idx >= 0, "gate có swift_edge")
	var price: int = int(shop._items[idx]["price"])
	shop._buy(shop._items[idx])
	ck(St.geo == 100 - price and "swift_edge" in St.charms_owned, "mua bùa: trừ %d Geo và nhận bùa" % price)
	ck(not ("swift_edge" in ids(shop._items)), "mua rồi thì hết hàng đó")
	ck(not ("frugal_soul" in ids(shop._items)) and not ("mask" in ids(shop._items) and St.hp_bonus >= 1), "mua xong hàng vẫn theo khu gate (không lộ bùa khu khác)")
	St.geo = 0
	var n0: int = St.charms_owned.size()
	shop._buy(shop._items[0])
	ck(St.charms_owned.size() == n0 and St.hp_bonus == 0, "không đủ tiền thì không mua được")
	# tiền thưởng boss
	for k in ["warden", "hexer", "brute", "wraith", "colossus", "lord"]:
		ck(int(B.BOUNTY.get(k, 0)) > 0, "boss %s có tiền thưởng" % k)
	St.reset()
	St.bench_room = "gate_6"
	var w := Node2D.new()
	w.set_script(load("res://hk/world.gd"))
	root.add_child(w)
	await create_timer(0.3).timeout
	var g0: int = St.geo
	w._on_boss_defeated("warden")
	ck(St.geo == g0 + int(B.BOUNTY["warden"]), "hạ boss lần đầu nhận thưởng (%d -> %d)" % [g0, St.geo])
	w._on_boss_defeated("warden")
	ck(St.geo == g0 + int(B.BOUNTY["warden"]), "hạ lại không nhận thêm")
	St.delete_save()
	print("hk_shop_test: ", "OK" if fails == 0 else "%d lỗi" % fails)
	quit(1 if fails > 0 else 0)
