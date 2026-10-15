extends Node
## AI Tầng 2 (Q-Learning cơ bản bằng GDScript thuần, không thư viện ngoài) — component gắn
## vào quái Tinh Anh (enemy.gd::is_elite == true, xem setup()). Q-table lưu trong
## Global.elite_q_table (Dictionary lồng nhau), PERSIST qua save file (Global.save_game() /
## load_game()) — nghĩa là quái "nhớ" cách Player chơi xuyên NHIỀU ván, không chỉ 1 run.
##
## State = (Khoảng cách Gần/Xa) x (Máu Player Cao/Thấp) x (Player đang né hay không) = 8 state.
## Action = ACTIONS bên dưới (bullet.gd/enemy.gd quyết định hành vi thật ứng với mỗi action).
## Reward: +10 khi đòn vừa chọn trúng Player, -5 khi trượt/hết giờ không trúng.
## Cập nhật kiểu Q-learning chuẩn: Q(s,a) += ALPHA * (reward + GAMMA * max_a' Q(s',a') - Q(s,a)).
## EPSILON luôn chừa % hành động ngẫu nhiên — "Human Error" ở tầng này — để quái Tinh Anh
## không hội tụ cứng về 1 nước đi duy nhất, dù đã học rất nhiều.

const ACTIONS: Array = ["shoot_straight", "shoot_predict", "hold", "retreat"]
const ALPHA: float = 0.25
const GAMMA: float = 0.7
const EPSILON: float = 0.15
const NEAR_DIST: float = 160.0
const HP_LOW_RATIO: float = 0.4

var owner_node: Node = null
var _last_state: String = ""
var _last_action: String = ""


func attach(p_owner: Node) -> void:
	owner_node = p_owner


func _q_table() -> Dictionary:
	return Global.elite_q_table


func _state_now() -> String:
	var p = Global.player
	if not is_instance_valid(p) or not is_instance_valid(owner_node):
		return "far|hp_high|idle"
	var dist: float = owner_node.global_position.distance_to(p.global_position)
	var dist_tag: String = "near" if dist < NEAR_DIST else "far"
	var hp_ratio: float = float(p.hp) / float(maxi(1, p.max_hp))
	var hp_tag: String = "hp_low" if hp_ratio <= HP_LOW_RATIO else "hp_high"
	var dodge_tag: String = "dodging" if bool(p.get("rolling")) else "idle"
	return dist_tag + "|" + hp_tag + "|" + dodge_tag


func _q(state: String, action: String) -> float:
	return float(_q_table().get(state, {}).get(action, 0.0))


func _set_q(state: String, action: String, value: float) -> void:
	var t: Dictionary = _q_table()
	if not t.has(state):
		t[state] = {}
	t[state][action] = value


## Gọi mỗi khi quái Tinh Anh định ra đòn — trả về action đã chọn (epsilon-greedy), tự lưu
## lại state/action vừa chọn để learn() sau đó biết cần cập nhật đúng ô nào trong Q-table.
func choose_action() -> String:
	var state: String = _state_now()
	var action: String
	if randf() < EPSILON or not _q_table().has(state):
		action = ACTIONS.pick_random()
	else:
		var best_a: String = ACTIONS[0]
		var best_q: float = -INF
		for a in ACTIONS:
			var qv: float = _q(state, a)
			if qv > best_q:
				best_q = qv
				best_a = a
		action = best_a
	_last_state = state
	_last_action = action
	return action


## Gọi khi biết kết quả đòn vừa chọn (bullet.gd gọi khi đạn trúng Player hoặc hết giờ/trượt).
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
