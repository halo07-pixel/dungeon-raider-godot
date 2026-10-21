extends Node
## Điều phối nhóm quái của phòng hiện tại. KHÔNG viết AI riêng cho từng loại quái: điều phối chỉ ghi
## 3 giá trị cho mỗi quái, quái tự đọc và cộng vào hướng đuổi sẵn có:
##   squad_offset - độ lệch hướng (gọng kìm: đi vòng sang các phía khác nhau của người chơi)
##   squad_speed  - hệ số tốc độ (nhóm nhanh chờ nhóm chậm cho tới cùng lúc)
##   squad_anchor - điểm đứng sau quái trâu bò cho quái tầm xa (Vector2.ZERO = không dùng)
## Quái đăng ký bằng signal `squad_register` (call down, signal up); điều phối tự loại quái đã chết.
## Tắt cả hệ thống: đặt ENABLED = false.

const SquadAdapt = preload("res://scripts/squad_adapt.gd")

const ENABLED: bool = true
const UPDATE_INTERVAL: float = 0.5
const MIN_SQUAD: int = 3              # ít hơn số quái này thì không phối hợp (đánh thẳng như cũ)
const TANKS: Array = ["brute", "masked_orc", "frost_big_zombie", "hell_ogre"]
const RANGED: Array = ["archer", "shaman", "hell_imp"]
const FLANK_ENGAGE_DIST: float = 150.0 # xa hơn mức này mới đi vòng; gần hơn thì lao thẳng vào
const FLANK_RADIUS: float = 110.0      # bán kính vòng quanh người chơi chứa các điểm gọng kìm
const FLANK_WEIGHT: float = 0.8        # độ mạnh của độ lệch so với hướng thẳng
const WAIT_ENGAGE_DIST: float = 220.0  # chỉ chờ nhau khi còn xa hơn mức này
const WAIT_FAST_RATIO: float = 0.6     # ETA nhỏ hơn 60% trung bình = "nhanh quá"
const WAIT_SLOW_MULT: float = 0.7      # quái nhanh quá bị giảm còn 70% tốc độ
const RANGED_BEHIND_DIST: float = 90.0 # quái tầm xa đứng sau trâu bò bấy nhiêu px (xa người chơi hơn)

var _members: Array = []
var _t: float = 0.0

func register(e: Node) -> void:
	if not _members.has(e):
		_members.append(e)

func _eligible(e) -> bool:
	if not is_instance_valid(e) or not bool(e.get("alive")) or not bool(e.get("active")):
		return false
	if e.kind == "mimic" or e.q_agent != null or e.has_meta("summoner") or e.has_meta("split_child"):
		return false
	return true

func _process(delta: float) -> void:
	if not ENABLED:
		return
	_t += delta
	if _t < UPDATE_INTERVAL:
		return
	_t = 0.0
	_update()

func _reset(e) -> void:
	e.squad_offset = Vector2.ZERO
	e.squad_speed = 1.0
	e.squad_anchor = Vector2.ZERO

func _update() -> void:
	_members = _members.filter(func(e): return is_instance_valid(e) and bool(e.get("alive")))
	var p = Global.player
	var squad: Array = _members.filter(_eligible)
	for e in _members:
		_reset(e)
	if squad.size() < MIN_SQUAD or not is_instance_valid(p) or not p.alive:
		return
	var pp: Vector2 = p.global_position
	var tac: Dictionary = SquadAdapt.tactics(PlayerProfiler.profile(), Global.floor_num) # đội thích nghi lối chơi
	_record_adaptation(tac)

	# --- Gọng kìm: quái cận chiến (không phải trâu bò/tầm xa) xếp đều quanh người chơi theo thứ tự góc hiện tại.
	var flankers: Array = squad.filter(func(e): return not TANKS.has(e.kind) and not RANGED.has(e.kind))
	flankers.sort_custom(func(a, b): return (a.global_position - pp).angle() < (b.global_position - pp).angle())
	var n: int = flankers.size()
	if n >= 2:
		var base: float = (flankers[0].global_position - pp).angle()
		for i in n:
			var e = flankers[i]
			var to_p: Vector2 = pp - e.global_position
			if to_p.length() <= FLANK_ENGAGE_DIST:
				continue
			var slot: Vector2 = pp + Vector2.from_angle(base + TAU * float(i) / float(n)) * FLANK_RADIUS * float(tac["flank_radius_mult"])
			var want: Vector2 = (slot - e.global_position).normalized()
			e.squad_offset = (want - to_p.normalized()) * FLANK_WEIGHT * float(tac["flank_weight_mult"])

	# --- Tầm xa đứng sau trâu bò gần nhất (phía xa người chơi hơn).
	var tanks: Array = squad.filter(func(e): return TANKS.has(e.kind))
	if not tanks.is_empty():
		for e in squad:
			if not RANGED.has(e.kind):
				continue
			var best = tanks[0]
			for t in tanks:
				if t.global_position.distance_to(e.global_position) < best.global_position.distance_to(e.global_position):
					best = t
			var away: Vector2 = (best.global_position - pp).normalized()
			e.squad_anchor = best.global_position + away * RANGED_BEHIND_DIST * float(tac["ranged_behind_mult"])

	# --- Nhóm nhanh chờ nhóm chậm: so ETA tới người chơi.
	var etas: Dictionary = {}
	var sum: float = 0.0
	var far_count: int = 0
	for e in squad:
		var d: float = e.global_position.distance_to(pp)
		if d <= WAIT_ENGAGE_DIST * float(tac["wait_dist_mult"]):
			continue
		var eta: float = d / maxf(1.0, float(e.data["speed"]))
		etas[e] = eta
		sum += eta
		far_count += 1
	if far_count >= 2:
		var mean: float = sum / float(far_count)
		var fast_ratio: float = maxf(WAIT_FAST_RATIO, float(tac["wait_fast_ratio"]))
		for e in etas:
			if float(etas[e]) < mean * fast_ratio:
				e.squad_speed = WAIT_SLOW_MULT
	_apply_adaptive_melee(squad, pp, tac)

## Phần thích nghi dành cho quái đánh gần (không phải tầm xa): đón đầu hướng né, và chạy nhanh hơn một chút
## khi người chơi hay đứng xa (chỉ khi quái còn ở xa và chưa bị bắt chờ).
func _apply_adaptive_melee(squad: Array, pp: Vector2, tac: Dictionary) -> void:
	if not bool(tac["active"]):
		return
	var lead: float = float(tac["lead"])
	var chase: float = float(tac["chase_speed"])
	for e in squad:
		if RANGED.has(e.kind):
			continue
		var to_p: Vector2 = pp - e.global_position
		var d: float = to_p.length()
		if lead != 0.0 and d >= SquadAdapt.LEAD_MIN_DIST and d <= SquadAdapt.LEAD_MAX_DIST:
			# bên người chơi hay né tới (trục x), lấy phần vuông góc với hướng đuổi; né dọc theo hướng đuổi thì không lệch
			var fwd: Vector2 = to_p / d
			var side: Vector2 = Vector2(signf(lead), 0.0)
			side -= fwd * side.dot(fwd)
			if side.length() > 0.2:
				e.squad_offset += side.normalized() * absf(lead) * minf(1.0, side.length())
		if chase > 1.0 and d > FLANK_ENGAGE_DIST and e.squad_speed >= 1.0:
			e.squad_speed = chase

## Ghi nhãn thích nghi vào thống kê ván (để màn Game Over nói cho người chơi biết quái đã học gì).
func _record_adaptation(tac: Dictionary) -> void:
	if not bool(tac["active"]):
		return
	var seen = Global.run_stats.get("adapted")
	if not (seen is Dictionary):
		seen = {}
		Global.run_stats["adapted"] = seen
	for tag in tac["tags"]:
		seen[String(tag)] = true
