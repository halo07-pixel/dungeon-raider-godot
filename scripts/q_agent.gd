extends Node
## AI Tầng 2 (Q-Learning cơ bản bằng GDScript thuần, không thư viện ngoài) — component gắn
## vào quái Tinh Anh (enemy.gd::is_elite == true, xem setup()). Q-table lưu trong
## Global.elite_q_table (Dictionary lồng nhau), PERSIST qua save file (Global.save_game() /
## load_game()) — nghĩa là quái "nhớ" cách Player chơi xuyên NHIỀU ván, không chỉ 1 run.
##
## State = Khoảng cách (Gần/Xa) x Máu Player (Cao/Thấp) x Player đang né? x Player đang di chuyển?
##       = 16 state, dạng chuỗi "near|hp_high|idle|still".
## Action = ACTIONS bên dưới. enemy.gd thực thi thật cả 4:
##   shoot_straight / shoot_predict : bắn (reward do bullet.gd báo: +10 trúng, -5 trượt)
##   hold                            : nhịn bắn 0.6s
##   retreat                         : lùi + lách ngang 0.6s
##   (hold/retreat được enemy.gd chấm điểm sau 0.6s rồi gọi learn(): +4 nếu Player đang lăn né
##    trong lúc đó — nhịn đúng lúc; -3 nếu bỏ lỡ cơ hội khi Player đứng im; còn lại 0.)
## Cập nhật kiểu Q-learning chuẩn: Q(s,a) += ALPHA * (reward + GAMMA * max_a' Q(s',a') - Q(s,a)).
##
## Khám phá thích nghi: EPSILON của từng state giảm dần theo SỐ LẦN state đó đã được học
## (lưu ở khóa VISITS_KEY trong chính Q-table, nên persist theo). Sàn EPSILON_FLOOR vẫn giữ
## "Human Error" — quái không bao giờ hội tụ cứng về 1 nước đi.

const ACTIONS: Array = ["shoot_straight", "shoot_predict", "hold", "retreat"]
const SHOOT_ACTIONS: Array = ["shoot_straight", "shoot_predict"]
const PASSIVE_ACTIONS: Array = ["hold", "retreat"]
const ALPHA: float = 0.25
const GAMMA: float = 0.7
const EPSILON_START: float = 0.25   # state mới gặp: ưu tiên thử nghiệm
const EPSILON_FLOOR: float = 0.08   # state đã học nhiều: vẫn chừa 8% ngẫu nhiên
const EPSILON_DECAY_VISITS: float = 40.0
const NEAR_DIST: float = 160.0
const HP_LOW_RATIO: float = 0.4
const PLAYER_MOVING_SPEED: float = 60.0
## Chống "nhịn mãi" (hold/retreat không bị phạt trực tiếp nên dễ thành nước đi an toàn):
## tối đa MAX_PASSIVE_STREAK lần nhịn/lùi liên tiếp, sau đó buộc phải bắn.
const MAX_PASSIVE_STREAK: int = 2
const VISITS_KEY: String = "_n"

var owner_node: Node = null
var _last_state: String = ""
var _last_action: String = ""
var _passive_streak: int = 0
## Chỉ dùng cho test/debug: ép chọn 1 action cụ thể (bỏ qua epsilon-greedy).
var forced_action: String = ""


func attach(p_owner: Node) -> void:
	owner_node = p_owner


func _q_table() -> Dictionary:
	return Global.elite_q_table


func _state_now() -> String:
	var p = Global.player
	if not is_instance_valid(p) or not is_instance_valid(owner_node):
		return "far|hp_high|idle|still"
	var dist: float = owner_node.global_position.distance_to(p.global_position)
	var dist_tag: String = "near" if dist < NEAR_DIST else "far"
	var hp_ratio: float = float(p.hp) / float(maxi(1, p.max_hp))
	var hp_tag: String = "hp_low" if hp_ratio <= HP_LOW_RATIO else "hp_high"
	var dodge_tag: String = "dodging" if bool(p.get("rolling")) else "idle"
	var move_tag: String = "moving" if p.velocity.length() > PLAYER_MOVING_SPEED else "still"
	return dist_tag + "|" + hp_tag + "|" + dodge_tag + "|" + move_tag


func _q(state: String, action: String) -> float:
	return float(_q_table().get(state, {}).get(action, 0.0))


func _set_q(state: String, action: String, value: float) -> void:
	var t: Dictionary = _q_table()
	if not t.has(state):
		t[state] = {}
	t[state][action] = value


## Số lần state này đã được học (learn()).
func visits(state: String) -> int:
	return int(_q_table().get(state, {}).get(VISITS_KEY, 0))


## EPSILON thích nghi: 0.25 (mới gặp) -> 0.08 (đã học >= EPSILON_DECAY_VISITS lần).
func epsilon_for(state: String) -> float:
	var t: float = clampf(float(visits(state)) / EPSILON_DECAY_VISITS, 0.0, 1.0)
	return lerpf(EPSILON_START, EPSILON_FLOOR, t)


func _best_of(state: String, candidates: Array) -> String:
	var best_a: String = candidates[0]
	var best_q: float = -INF
	for a in candidates:
		var qv: float = _q(state, a)
		if qv > best_q:
			best_q = qv
			best_a = a
	return best_a


## Gọi mỗi khi quái Tinh Anh định ra đòn — trả về action đã chọn (epsilon-greedy), tự lưu
## lại state/action vừa chọn để learn() sau đó biết cần cập nhật đúng ô nào trong Q-table.
func choose_action() -> String:
	var state: String = _state_now()
	var action: String
	if forced_action != "":
		action = forced_action
	elif randf() < epsilon_for(state) or not _q_table().has(state):
		action = ACTIONS.pick_random()
	else:
		action = _best_of(state, ACTIONS)
	# Chống nhịn/lùi mãi: đủ streak thì buộc bắn (nước bắn tốt nhất theo Q).
	if forced_action == "" and PASSIVE_ACTIONS.has(action) and _passive_streak >= MAX_PASSIVE_STREAK:
		action = _best_of(state, SHOOT_ACTIONS)
	_passive_streak = _passive_streak + 1 if PASSIVE_ACTIONS.has(action) else 0
	_last_state = state
	_last_action = action
	return action


## Gọi khi biết kết quả đòn vừa chọn (bullet.gd gọi khi đạn trúng Player hoặc hết giờ/trượt;
## enemy.gd gọi sau 0.6s cho hold/retreat).
func learn(reward: float) -> void:
	if _last_state == "":
		return
	var next_state: String = _state_now()
	var best_next_q: float = 0.0
	for a in ACTIONS:
		best_next_q = maxf(best_next_q, _q(next_state, a))
	var old_q: float = _q(_last_state, _last_action)
	var new_q: float = old_q + ALPHA * (reward + GAMMA * best_next_q - old_q)
	_set_q(_last_state, _last_action, new_q)
	_q_table()[_last_state][VISITS_KEY] = visits(_last_state) + 1
