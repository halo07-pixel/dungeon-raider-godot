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

const OBS_SIZE: int = 16
const ACTION_SIZE: int = 4
const ARENA_NORM: float = 600.0     # chia toạ độ/khoảng cách cho hằng này để ~[-1,1]
const SPEED_NORM: float = 400.0
const RAY_COUNT: int = 8             # 8 raycast quanh thân (mỗi 45°) đo khoảng cách tới tường
const RAY_LENGTH: float = 400.0

## Chỉ số action: [0]=hướng di chuyển x, [1]=hướng y, [2]=ngưỡng "ra đòn" (>0 = tấn công),
## [3]=chọn đòn (map về index trong attack pool của boss, do nơi áp dụng quyết định).
enum {ACTION_MOVE_X, ACTION_MOVE_Y, ACTION_ATTACK, ACTION_PICK}

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
