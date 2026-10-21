extends SceneTree
## Kiểm tra cân bằng vũ khí (chạy: godot --headless --path . -s tools/tests/weapon_dps_test.gd).
## Đo DPS "tối đa lý thuyết" (mọi viên đạn trúng 1 mục tiêu, cung căng đầy, không buff) của mọi vũ khí x mọi độ hiếm
## bằng cách bắn/chém thật qua Player rồi cộng sát thương / thời gian hồi. Thoát code 1 nếu có chỉ số lệch khỏi dải cho phép.
## Dải (chỉnh ở đây khi cố ý đổi cân bằng):
const COMMON_BAND: Vector2 = Vector2(0.5, 1.5)        # DPS Common so với trung vị các vũ khí
const MAX_LEGEND_RATIO: float = 3.6                   # Legendary / Common
const MAX_MYTHIC_OVER_LEGEND: float = 1.6             # Mythic / Legendary
const RARITIES: Array = ["common", "rare", "epic", "legendary", "mythic"]

var fails: int = 0

const DUMMY_SRC := """
extends Node2D
var alive: bool = true
var data: Dictionary = {"radius": 14.0}
var total: int = 0
func kill() -> void: pass
func hurt_center() -> Vector2: return global_position
func take_damage(d: int, _pos = Vector2.ZERO, _k = 0.0, _t = false) -> void: total += d
func apply_element(_a = null, _b = null, _c = null) -> void: pass
func apply_status(_a = null, _b = null, _c = null) -> void: pass
func apply_sunder() -> void: pass
"""

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func _init() -> void:
	await process_frame
	var WI = load("res://scripts/weapon_instance.gd")
	var G = root.get_node("Global")
	G.current_class = "mage" # lớp không có nội tại sát thương vũ khí -> số đo trung tính
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var p = main.player
	var B = load("res://scripts/bullet.gd")
	var dummy_script := GDScript.new()
	dummy_script.source_code = DUMMY_SRC
	dummy_script.reload()
	var table: Dictionary = {}
	for id in G.weapons:
		var melee: bool = bool(G.weapons[id].get("is_melee", false))
		table[id] = {}
		for r in RARITIES:
			p.set_slot(p.active_slot, WI.make(id, r))
			p.aim_dir = Vector2.RIGHT
			p.fire_timer.stop()
			p.shot_count = 0
			p.swing_count = 0
			var total: int = 0
			var cd: float = 0.0
			if melee:
				var d = Node2D.new()
				d.set_script(dummy_script)
				d.add_to_group("enemies")
				G.world.add_child(d)
				d.global_position = p.global_position + Vector2(24.0, 0.0)
				p.swinging = false
				p._swing()
				total = int(d.total)
				cd = p.fire_timer.wait_time
				d.queue_free()
			else:
				for n in G.world.get_children():
					if n.get_script() == B:
						n.queue_free()
				await process_frame
				p._shoot(1.0, false)
				for n in G.world.get_children():
					if n.get_script() == B and not n.is_queued_for_deletion():
						total += int(n.damage)
				cd = p.fire_timer.wait_time + float(G.weapons[id].get("charge_time", 0.0))
			table[id][r] = float(total) / maxf(cd, 0.05)
			await process_frame
	# --- báo cáo ---
	var commons: Array = []
	for id in table:
		commons.append(table[id]["common"])
	commons.sort()
	var median: float = commons[commons.size() / 2]
	print("median common DPS = %.1f" % median)
	for id in table:
		var t: Dictionary = table[id]
		print("%-13s %s" % [id, "  ".join(RARITIES.map(func(r): return "%s %6.1f" % [r.substr(0, 3), t[r]]))])
		ck(t["common"] >= median * COMMON_BAND.x and t["common"] <= median * COMMON_BAND.y, "%s common DPS %.1f out of band" % [id, t["common"]])
		for i in range(1, RARITIES.size()):
			ck(t[RARITIES[i]] >= t[RARITIES[i - 1]] * 0.98, "%s: %s weaker than %s" % [id, RARITIES[i], RARITIES[i - 1]])
		ck(t["legendary"] <= t["common"] * MAX_LEGEND_RATIO, "%s legendary %.1fx common" % [id, t["legendary"] / t["common"]])
		ck(t["mythic"] <= t["legendary"] * MAX_MYTHIC_OVER_LEGEND, "%s mythic %.2fx legendary" % [id, t["mythic"] / t["legendary"]])
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
