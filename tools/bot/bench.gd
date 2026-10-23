extends SceneTree
## Bài đo so sánh CLASS trong tình huống cố định (không chạy cả ván).
## Chạy: godot --headless --path . --script tools/bot/bench.gd -- --runs 10 --class ranger,brawler,mage,rogue --out /tmp/bench.json
## Mỗi tình huống: cùng tầng, cùng bộ buff, cùng cấp nâng cấp kỹ năng, cùng danh sách seed cho mọi class.
## Đo: tỉ lệ thắng, thời gian hạ (giây mô phỏng), DPS lên mục tiêu, sát thương nhận (% máu tối đa), số lần dùng skill/phút.
## Bot KHÔNG bất tử ở bài này (điều kiện thật); bot chơi kém hơn người, chỉ dùng để so SÁNH TƯƠNG ĐỐI giữa các class.

const BotBrain = preload("res://tools/bot/bot_brain.gd")

## floor: tầng dựng; skill_lv: số nâng cấp kỹ năng đã có (0 = trước mốc 5, 1 = sau mốc 5, 2 = sau mốc 10); buffs: buff cố định.
const SCENARIOS: Dictionary = {
	"warden": {"kind": "boss", "floor": 1, "skill_lv": 0, "buffs": [], "label": "Boss Warden (tầng 1, chưa nâng cấp skill)"},
	"swarm": {"kind": "swarm", "floor": 3, "skill_lv": 0, "buffs": [], "label": "Bầy quái 13 con (tầng 3, chưa nâng cấp skill)"},
	"necro": {"kind": "boss", "floor": 6, "skill_lv": 1, "buffs": ["buff_dmg", "buff_haste"], "label": "Boss Necromancer (tầng 6, sau mốc nâng cấp 1)"},
	"lord": {"kind": "boss", "floor": 10, "skill_lv": 2, "buffs": ["buff_dmg", "buff_haste", "buff_crit", "buff_reach"], "label": "Dungeon Lord (tầng 10, sau mốc nâng cấp 2)"},
}
const SWARM_KINDS: Array = ["slime", "slime", "slime", "slime", "slime", "slime", "slime", "slime", "archer", "archer", "archer", "brute", "brute"]
const CLASSES: Array = ["ranger", "brawler", "mage", "rogue"]

var G
var opts: Dictionary = {"runs": 5, "class": "ranger,brawler,mage,rogue", "scenarios": "warden,swarm,necro,lord", "speed": 14.0, "cap": 240.0, "trace": 0, "seed": 100, "out": ""}
var rows: Array = []

# trạng thái một lần đo
var _dmg_taken: int = 0
var _skill_uses: int = 0
var _boss = null

func _init() -> void:
	call_deferred("_main")

func _parse_args() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		var k: String = String(a[i]).trim_prefix("--")
		if i + 1 < a.size() and opts.has(k):
			var v: String = a[i + 1]
			if opts[k] is float: opts[k] = float(v)
			elif opts[k] is int: opts[k] = int(v)
			else: opts[k] = v
			i += 2
		else:
			i += 1

func _main() -> void:
	G = root.get_node("Global")
	_parse_args()
	G.save_path = "user://bench_save.dat"
	Engine.max_physics_steps_per_frame = 200
	var classes: Array = String(opts["class"]).split(",", false)
	var scen: Array = String(opts["scenarios"]).split(",", false)
	for sid in scen:
		if not SCENARIOS.has(sid):
			continue
		for cid in classes:
			for r in int(opts["runs"]):
				var row: Dictionary = await _measure(String(sid), String(cid), int(opts["seed"]) + r)
				rows.append(row)
				print("bench %-7s %-8s seed=%d %s ttk=%5.1fs dmg=%3d%% skill=%d" % [sid, cid, int(opts["seed"]) + r, "WIN " if row["win"] else row["end"].to_upper().substr(0, 4) + " ", row["time"], int(row["dmg_pct"]), row["skill_uses"]])
	_report(scen, classes)
	if String(opts["out"]) != "":
		var f := FileAccess.open(String(opts["out"]), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(rows, "\t"))
			f.close()
	Engine.time_scale = 1.0
	quit()

func _on_hurt(_source: String, amount: int) -> void:
	_dmg_taken += amount

func _on_skill(_id: String) -> void:
	_skill_uses += 1

func _on_boss_spawned(b) -> void:
	_boss = b

func _measure(sid: String, cid: String, seed_v: int) -> Dictionary:
	var sc: Dictionary = SCENARIOS[sid]
	paused = false
	Engine.time_scale = 1.0
	_dmg_taken = 0
	_skill_uses = 0
	_boss = null
	seed(seed_v)
	G.current_class = cid
	G.saved_run = {}
	G.heat_selected = {}
	change_scene_to_file("res://scenes/main.tscn")
	for i in 30:
		await physics_frame
	var main = current_scene
	# dựng tầng đúng như người chơi vừa tới đó
	G.floor_num = int(sc["floor"]) - 1
	main._next_floor()
	for i in 30:
		await physics_frame
	for b in sc["buffs"]:
		G.apply_buff(String(b))
	var skill_id: String = G.current_skill_id()
	var pool: Array = SkillUpgrades_available(skill_id)
	for i in mini(int(sc["skill_lv"]), pool.size()):
		G.skill_upgrades_taken.append(String(pool[i]))
	var player = main.player
	player.heal(player.max_hp)
	var dungeon = main.dungeon
	G.player_hurt_by.connect(_on_hurt)
	G.boss_spawned.connect(_on_boss_spawned)
	if player.get("class_skill") != null and is_instance_valid(player.class_skill):
		player.class_skill.skill_used.connect(_on_skill)
	var target_hp: float = 0.0
	var swarm: Array = []
	var brain_fail: bool = false
	if String(sc["kind"]) == "boss":
		var cell: Vector2i = dungeon.boss_cell
		dungeon.rooms[cell]["visited"] = false
		player.global_position = dungeon.room_center(cell) + Vector2(-280.0, 0.0)
		for i in 3:
			await physics_frame
		dungeon._enter_room(cell)
		for i in 5:
			await physics_frame
		if not is_instance_valid(_boss):
			brain_fail = true # boss không sinh ra: bỏ lượt đo thay vì tính thắng giả
		else:
			target_hp = float(_boss.max_hp)
	else:
		var cell2: Vector2i = dungeon.start_cell
		dungeon.rooms[cell2]["visited"] = true
		dungeon.current_cell = cell2
		var ctr: Vector2 = dungeon.room_center(cell2)
		player.global_position = ctr
		var n: int = SWARM_KINDS.size()
		for i in n:
			var ang: float = TAU * float(i) / float(n)
			var e = dungeon._spawn_enemy(String(SWARM_KINDS[i]), ctr + Vector2.from_angle(ang) * 230.0, cell2)
			target_hp += float(e.max_hp)
			swarm.append(e)
	if brain_fail:
		push_error("bench: boss không sinh ra (%s/%s)" % [sid, cid])
		G.player_hurt_by.disconnect(_on_hurt)
		G.boss_spawned.disconnect(_on_boss_spawned)
		return {"scenario": sid, "class": cid, "seed": seed_v, "win": false, "end": "nospawn", "time": 0.0, "dmg": 0, "dmg_pct": 0.0, "skill_uses": 0, "skill_per_min": 0.0, "dps": 0.0, "target_hp": 0.0, "max_hp": float(player.max_hp)}
	var brain = BotBrain.new()
	main.add_child(brain)
	brain.setup(main)
	brain.trace = int(opts["trace"]) > 0
	var speed: float = float(opts["speed"])
	var cap: float = float(opts["cap"])
	var t0: float = brain.sim_time
	var end: String = "timeout"
	var win: bool = false
	while true:
		await physics_frame
		if not G._hitstop_active:
			Engine.time_scale = speed
		if main.is_game_over:
			end = "death"
			break
		if String(sc["kind"]) == "boss":
			if is_instance_valid(_boss) == false or float(_boss.hp) <= 0.0:
				win = true
				end = "win"
				break
		elif dungeon.alive_enemies <= 0:
			win = true
			end = "win"
			break
		if brain.sim_time - t0 >= cap:
			break
	var t: float = brain.sim_time - t0
	var remaining: float = 0.0
	if String(sc["kind"]) == "boss":
		remaining = maxf(0.0, float(_boss.hp)) if is_instance_valid(_boss) else 0.0
	else:
		for e in swarm:
			if is_instance_valid(e):
				remaining += maxf(0.0, float(e.hp))
	var progress: float = clampf(1.0 - remaining / maxf(1.0, target_hp), 0.0, 1.0)
	var max_hp: float = float(player.max_hp)
	Engine.time_scale = 1.0
	paused = false
	G.player_hurt_by.disconnect(_on_hurt)
	G.boss_spawned.disconnect(_on_boss_spawned)
	brain.queue_free()
	return {"scenario": sid, "class": cid, "seed": seed_v, "win": win, "end": end, "time": t, "dmg": _dmg_taken, "dmg_pct": float(_dmg_taken) / maxf(1.0, max_hp) * 100.0,
		"skill_uses": _skill_uses, "skill_per_min": float(_skill_uses) / maxf(0.1, t / 60.0), "dps": target_hp / maxf(0.1, t) if win else 0.0, "progress": progress, "dps_eff": target_hp * progress / maxf(0.1, t), "target_hp": target_hp, "max_hp": max_hp}

func SkillUpgrades_available(skill_id: String) -> Array:
	var su = load("res://scripts/skill_upgrades.gd")
	return su.available(skill_id, [])

func _median(a: Array) -> float:
	if a.is_empty():
		return -1.0
	var s: Array = a.duplicate()
	s.sort()
	return float(s[s.size() / 2]) if s.size() % 2 == 1 else (float(s[s.size() / 2 - 1]) + float(s[s.size() / 2])) / 2.0

func _report(scen: Array, classes: Array) -> void:
	print("")
	print("===== SO SÁNH CLASS (trung vị; chỉ số: trung bình của các class = 100, cao hơn = tốt hơn) =====")
	for sid in scen:
		if not SCENARIOS.has(sid):
			continue
		print("")
		print("[%s]" % SCENARIOS[sid]["label"])
		print("class    | n  | thắng | TTK trung vị (min-max) | DPS hiệu dụng | tiến độ (% máu mục tiêu) | tồn tại (s) | sát thương nhận % máu | skill/phút | chỉ số DPS | chỉ số sống sót")
		var stat: Dictionary = {}
		for cid in classes:
			var mine: Array = rows.filter(func(r): return r["scenario"] == sid and r["class"] == cid)
			if mine.is_empty():
				continue
			var wins: Array = mine.filter(func(r): return r["win"])
			var ttks: Array = wins.map(func(r): return float(r["time"]))
			ttks.sort()
			stat[cid] = {"n": mine.size(), "win": float(wins.size()) / float(mine.size()), "ttk": _median(ttks), "min": ttks[0] if not ttks.is_empty() else -1.0, "max": ttks[-1] if not ttks.is_empty() else -1.0,
				"dps": _median(mine.map(func(r): return float(r["dps_eff"]))), "prog": _median(mine.map(func(r): return float(r["progress"]))), "surv": _median(mine.map(func(r): return float(r["time"]))), "dmg": _median(mine.map(func(r): return float(r["dmg_pct"]))), "spm": _median(mine.map(func(r): return float(r["skill_per_min"])))}
		var dps_vals: Array = []
		var surv_vals: Array = []
		for cid in stat:
			dps_vals.append(float(stat[cid]["dps"]))
			surv_vals.append(float(stat[cid]["surv"]))
		var ttk_mean: float = dps_vals.reduce(func(a, b): return a + b) / dps_vals.size() if not dps_vals.is_empty() else 0.0
		var surv_mean: float = surv_vals.reduce(func(a, b): return a + b) / surv_vals.size() if not surv_vals.is_empty() else 0.0
		for cid in classes:
			if not stat.has(cid):
				continue
			var s: Dictionary = stat[cid]
			var speed_idx: String = "%3d" % int(round(s["dps"] / ttk_mean * 100.0)) if ttk_mean > 0.0 else "  -"
			var surv_idx: String = "%3d" % int(round(s["surv"] / surv_mean * 100.0)) if surv_mean > 0.0 else "  -"
			var ttk_s: String = "%5.1fs (%.0f-%.0f)" % [s["ttk"], s["min"], s["max"]] if s["ttk"] > 0.0 else "      -      "
			print("%-8s | %2d | %3d%%  | %-22s | %5.1f | %3d%% | %5.0f | %5.0f%% | %5.1f | %s | %s" % [cid, s["n"], int(s["win"] * 100.0), ttk_s, s["dps"], int(s["prog"] * 100.0), s["surv"], s["dmg"], s["spm"], speed_idx, surv_idx])
	print("")
	print("Ghi chú: ván < 10 mẫu/class có độ nhiễu lớn; chênh dưới ~15% coi như hòa. TTK = thời gian hạ mục tiêu (giây mô phỏng).")
