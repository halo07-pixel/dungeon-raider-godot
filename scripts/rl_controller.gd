extends Node
## AI Tầng 3 — KHUNG HẠ TẦNG cho Machine Learning thực thụ (Godot RL Agents / PPO / .onnx).
## File này CHỈ định nghĩa interface thu thập observation + nhận action; KHÔNG chứa thuật
## toán huấn luyện (PPO chạy offline bên ngoài, bằng Python + addon godot_rl_agents, rồi xuất
## file .onnx để nạp lại). Gắn node này làm con của Boss (hoặc quái bất kỳ) để dùng.
##
## Cách dùng sau này:
##   - Huấn luyện: addon godot_rl_agents gọi get_obs() mỗi bước, gửi action về set_action().
##   - Suy luận (inference): thay bằng node ONNXInference của addon, dùng đúng get_obs() này
##     làm đầu vào và set_action() làm đầu ra -> KHÔNG cần sửa logic boss.
##
## Observation vector cố định độ dài OBS_SIZE (chuẩn hoá về ~[-1, 1] để mạng học ổn định).
## Action là vector liên tục ACTION_SIZE phần tử trong [-1, 1] (xem ACTION_* bên dưới).
##
## NÂNG CẤP — Bộ điều khiển chiến thuật tự vận hành (không cần file .onnx):
##   decide_action() là CHÍNH SÁCH NỘI BỘ: tầng tuyến tính nhỏ (4 x FEAT_SIZE trọng số + bias, qua tanh)
##   trên vector get_obs() (+2 đặc trưng dẫn xuất: tốc độ Player, khoảng cách), khởi tạo bằng bộ
##   trọng số "tiên nghiệm" viết tay (lò xo giữ khoảng cách + lách ngang + né tường + thiên lệch chọn
##   đòn) rồi tự tinh chỉnh nhẹ sau mỗi nhịp bằng Policy Gradient kiểu Bandit (adapt()) dựa trên
##   compute_reward(). Độ lệch so với tiên nghiệm bị chặn (MAX_DELTA) để Boss không bao giờ "hỏng".
##   Thành thật về giới hạn: 1 trận boss chỉ có vài chục nhịp, nên đây là "thích nghi nhẹ" chứ
##   không phải học sâu — mô hình .onnx thật sau này vẫn cắm vào qua get_obs()/set_action().

const OBS_SIZE: int = 16
const ACTION_SIZE: int = 4
const ARENA_NORM: float = 600.0     # chia toạ độ/khoảng cách cho hằng này để ~[-1,1]
const SPEED_NORM: float = 400.0
const RAY_COUNT: int = 8             # 8 raycast quanh thân (mỗi 45°) đo khoảng cách tới tường
const RAY_LENGTH: float = 400.0

## Chỉ số action: [0]=hướng di chuyển x, [1]=hướng y, [2]=ngưỡng "ra đòn" (>0 = tấn công),
## [3]=chọn đòn (map về index trong attack pool của boss, do nơi áp dụng quyết định).
enum {ACTION_MOVE_X, ACTION_MOVE_Y, ACTION_ATTACK, ACTION_PICK}

const FEAT_SIZE: int = OBS_SIZE + 2  # obs + [tốc độ Player, khoảng cách tới Player]
const NOISE_STD: float = 0.12        # nhiễu khám phá của chính sách
const LEARN_RATE: float = 0.08
const MAX_DELTA: float = 0.6         # |trọng số - tiên nghiệm| tối đa
const BASELINE_EMA: float = 0.1

var owner_body: CharacterBody2D = null
var last_action: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var episode_reward: float = 0.0


func attach(p_owner: CharacterBody2D) -> void:
	owner_body = p_owner


## Observation mỗi bước (độ dài đúng OBS_SIZE):
##  [0..1]  vị trí tương đối Player so với quái (dx, dy) / ARENA_NORM
##  [2..3]  vận tốc Player / SPEED_NORM
##  [4..5]  vận tốc của chính quái / SPEED_NORM
##  [6]     máu quái (0..1)        [7] máu Player (0..1)
##  [8]     Player đang né? (0/1)  [9] pha hiện tại / số pha tối đa
##  [10..11] hướng Player (đơn vị) — dư thừa có chủ đích, giúp mạng học nhanh hơn
##  [12..15] 4 trong 8 raycast khoảng cách tường (xem _wall_rays, rút gọn cho obs nhỏ gọn)
func get_obs() -> PackedFloat32Array:
	var obs := PackedFloat32Array()
	obs.resize(OBS_SIZE)
	var p = Global.player
	if not is_instance_valid(owner_body) or not is_instance_valid(p):
		return obs # toàn 0 khi chưa đủ dữ liệu
	var rel: Vector2 = p.global_position - owner_body.global_position
	obs[0] = clampf(rel.x / ARENA_NORM, -1.0, 1.0)
	obs[1] = clampf(rel.y / ARENA_NORM, -1.0, 1.0)
	obs[2] = clampf(p.velocity.x / SPEED_NORM, -1.0, 1.0)
	obs[3] = clampf(p.velocity.y / SPEED_NORM, -1.0, 1.0)
	obs[4] = clampf(owner_body.velocity.x / SPEED_NORM, -1.0, 1.0)
	obs[5] = clampf(owner_body.velocity.y / SPEED_NORM, -1.0, 1.0)
	var own_max: float = float(owner_body.get("max_hp")) if owner_body.get("max_hp") != null else 1.0
	var own_hp: float = float(owner_body.get("hp")) if owner_body.get("hp") != null else own_max
	obs[6] = clampf(own_hp / maxf(own_max, 1.0), 0.0, 1.0)
	obs[7] = clampf(float(p.hp) / float(maxi(1, p.max_hp)), 0.0, 1.0)
	obs[8] = 1.0 if bool(p.get("rolling")) else 0.0
	var phase: float = float(owner_body.get("phase")) if owner_body.get("phase") != null else 1.0
	obs[9] = clampf(phase / 4.0, 0.0, 1.0)
	var dir: Vector2 = rel.normalized()
	obs[10] = dir.x
	obs[11] = dir.y
	var rays: PackedFloat32Array = _wall_rays()
	for i in 4:
		obs[12 + i] = rays[i * 2] # lấy mỗi tia cách 1 (0°,90°,180°,270°)
	return obs


## Raycast khoảng cách tới tường (chuẩn hoá 0..1, 1 = trống đến hết RAY_LENGTH).
func _wall_rays() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(RAY_COUNT)
	for i in RAY_COUNT:
		out[i] = 1.0
	if not is_instance_valid(owner_body) or not owner_body.is_inside_tree():
		return out
	var space := owner_body.get_world_2d().direct_space_state
	for i in RAY_COUNT:
		var ang: float = TAU * float(i) / float(RAY_COUNT)
		var from: Vector2 = owner_body.global_position
		var to: Vector2 = from + Vector2.from_angle(ang) * RAY_LENGTH
		var q := PhysicsRayQueryParameters2D.create(from, to, Global.L_WORLD)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			out[i] = from.distance_to(hit["position"]) / RAY_LENGTH
	return out


## Nhận action từ mô hình (huấn luyện hoặc ONNX). Lưu lại để nơi áp dụng (boss.gd) đọc;
## interface cố ý KHÔNG tự di chuyển boss — quyết định áp dụng thế nào thuộc về boss.gd.
func set_action(action: PackedFloat32Array) -> void:
	if action.size() < ACTION_SIZE:
		return
	last_action = action


## Reward mỗi bước cho huấn luyện: thưởng khi gây sát thương/áp sát vừa đủ, phạt khi đứng
## yên hoặc Player thoát hẳn khỏi tầm. Đây là KHUNG gợi ý — tinh chỉnh khi huấn luyện thật.
func compute_reward(damage_dealt: float, damage_taken: float) -> float:
	var r: float = damage_dealt * 0.05 - damage_taken * 0.02
	episode_reward += r
	return r


func reset_episode() -> void:
	episode_reward = 0.0
	last_action = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])


# ==============================================================================
# CHÍNH SÁCH NỘI BỘ (Built-in Policy / Contextual Bandit)
# ==============================================================================
## weights[k] = PackedFloat32Array(FEAT_SIZE) cho action k; bias[k] là hệ số tự do.
var weights: Array = []
var bias: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _prior_weights: Array = []
var _prior_bias: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _last_feat: PackedFloat32Array = PackedFloat32Array()
var _last_noise: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _have_step: bool = false
var baseline: float = 0.0
var decisions: int = 0
var adapt_steps: int = 0
## Hệ số riêng từ file chính sách đã huấn luyện (< 0 = không có -> boss dùng hằng số mặc định của nó).
var move_blend: float = -1.0
var pick_bias: float = -1.0
var policy_loaded: bool = false


func _init() -> void:
	reset_policy()


## Đưa chính sách về bộ trọng số tiên nghiệm viết tay.
func reset_policy() -> void:
	weights.clear()
	for k in ACTION_SIZE:
		var w := PackedFloat32Array()
		w.resize(FEAT_SIZE)
		weights.append(w)
	bias = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	# Chỉ số đặc trưng: 0,1 = vị trí tương đối Player; 6 = máu quái; 7 = máu Player; 8 = Player né;
	# 10,11 = hướng Player; 12..15 = tia tường (phải, dưới, trái, trên); 16 = tốc độ Player; 17 = khoảng cách.
	# MOVE: lò xo (kéo về Player theo khoảng cách, đẩy ra theo hướng đơn vị => cân bằng ~200px)
	#       + lách ngang (xoay vector tương đối) + đẩy tránh tường gần.
	const SPRING: float = 1.5
	const PUSH: float = 0.5
	const STRAFE: float = 0.4
	const WALL: float = 0.6
	weights[ACTION_MOVE_X][0] = SPRING
	weights[ACTION_MOVE_X][1] = -STRAFE
	weights[ACTION_MOVE_X][10] = -PUSH
	weights[ACTION_MOVE_X][12] = WALL
	weights[ACTION_MOVE_X][14] = -WALL
	weights[ACTION_MOVE_Y][1] = SPRING
	weights[ACTION_MOVE_Y][0] = STRAFE
	weights[ACTION_MOVE_Y][11] = -PUSH
	weights[ACTION_MOVE_Y][13] = WALL
	weights[ACTION_MOVE_Y][15] = -WALL
	# ATTACK: mặc định hơi dương; Player đang né thì kìm lại; Player yếu máu thì hung hăng hơn.
	bias[ACTION_ATTACK] = 0.3
	weights[ACTION_ATTACK][8] = -0.8
	weights[ACTION_ATTACK][7] = -0.3
	# PICK (>0 = ưu tiên đòn diện rộng/đón đầu, <0 = đòn trực diện): Player ở xa hoặc chạy nhanh -> dương.
	bias[ACTION_PICK] = -1.02
	weights[ACTION_PICK][16] = 1.5
	weights[ACTION_PICK][17] = 2.0
	_prior_weights.clear()
	for k in ACTION_SIZE:
		_prior_weights.append(PackedFloat32Array(weights[k]))
	_prior_bias = PackedFloat32Array(bias)
	baseline = 0.0
	_have_step = false


## Nạp chính sách đã huấn luyện offline (tools/rl/train_lord.py -> assets/ai/*.json) làm ĐIỂM XUẤT PHÁT mới
## thay cho bộ tiên nghiệm viết tay; adapt() trong trận vẫn tinh chỉnh quanh bộ này (kẹp MAX_DELTA).
## Trả về false (và giữ nguyên chính sách hiện tại) nếu thiếu file hoặc file sai kích thước.
func load_policy(path: String) -> bool:
	var data = null
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is JSON:
			data = (res as JSON).data
	elif FileAccess.file_exists(path):
		data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var w_in = data.get("weights")
	var b_in = data.get("bias")
	if typeof(w_in) != TYPE_ARRAY or typeof(b_in) != TYPE_ARRAY or w_in.size() != ACTION_SIZE or b_in.size() != ACTION_SIZE:
		push_warning("RLController: file chính sách sai kích thước: " + path)
		return false
	var new_w: Array = []
	for k in ACTION_SIZE:
		var row = w_in[k]
		if typeof(row) != TYPE_ARRAY or row.size() != FEAT_SIZE:
			push_warning("RLController: file chính sách sai kích thước: " + path)
			return false
		new_w.append(PackedFloat32Array(row))
	weights = new_w
	bias = PackedFloat32Array(b_in)
	_prior_weights.clear()
	for k in ACTION_SIZE:
		_prior_weights.append(PackedFloat32Array(weights[k]))
	_prior_bias = PackedFloat32Array(bias)
	baseline = 0.0
	_have_step = false
	move_blend = clampf(float(data.get("move_blend", -1.0)), -1.0, 1.0)
	pick_bias = clampf(float(data.get("pick_bias", -1.0)), -1.0, 3.0)
	policy_loaded = true
	return true


## Vector đặc trưng = get_obs() + [tốc độ Player, khoảng cách tới Player] (suy ra từ chính obs).
func _features(obs: PackedFloat32Array) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	f.resize(FEAT_SIZE)
	for i in OBS_SIZE:
		f[i] = obs[i]
	f[OBS_SIZE] = Vector2(obs[2], obs[3]).length()
	f[OBS_SIZE + 1] = Vector2(obs[0], obs[1]).length()
	return f


## Quyết định action từ chính sách nội bộ: tanh(W·f + b) + nhiễu nhỏ, kẹp [-1, 1].
## Đồng thời lưu (đặc trưng, nhiễu) để adapt() cập nhật. Trả về và đặt last_action.
func decide_action() -> PackedFloat32Array:
	var feat: PackedFloat32Array = _features(get_obs())
	var out := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var noise := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	for k in ACTION_SIZE:
		var z: float = bias[k]
		var w: PackedFloat32Array = weights[k]
		for i in FEAT_SIZE:
			z += w[i] * feat[i]
		var n: float = randfn(0.0, NOISE_STD)
		noise[k] = n
		out[k] = clampf(tanh(z) + n, -1.0, 1.0)
	_last_feat = feat
	_last_noise = noise
	_have_step = true
	decisions += 1
	last_action = out
	return out


## Tự tinh chỉnh nhẹ: Policy Gradient kiểu Bandit với nhiễu Gauss (REINFORCE, baseline = EMA reward).
## Trọng số không bao giờ lệch quá MAX_DELTA so với bộ tiên nghiệm.
func adapt(reward: float) -> void:
	if not _have_step:
		return
	var adv: float = reward - baseline
	baseline = lerpf(baseline, reward, BASELINE_EMA)
	for k in ACTION_SIZE:
		var w: PackedFloat32Array = weights[k]
		var pw: PackedFloat32Array = _prior_weights[k]
		var g: float = LEARN_RATE * adv * (_last_noise[k] / NOISE_STD)
		for i in FEAT_SIZE:
			w[i] = clampf(w[i] + g * _last_feat[i], pw[i] - MAX_DELTA, pw[i] + MAX_DELTA)
		weights[k] = w
		bias[k] = clampf(bias[k] + g, _prior_bias[k] - MAX_DELTA, _prior_bias[k] + MAX_DELTA)
	adapt_steps += 1


## Một nhịp học trọn vẹn: tính reward rồi adapt(). Gọi trước decide_action() của nhịp kế tiếp.
func reward_step(damage_dealt: float, damage_taken: float) -> float:
	var r: float = compute_reward(damage_dealt, damage_taken)
	adapt(r)
	return r
