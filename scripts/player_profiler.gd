extends Node
## AI Tầng 1 (Heuristic/Adaptive) — Autoload theo dõi thói quen Player bằng rolling-average
## (EMA) HOÀN TOÀN cục bộ, KHÔNG dùng API ngoài. Quái tầm xa (enemy.gd::_shoot) đọc dữ liệu
## này để "đoán" người chơi thay vì luôn bắn thẳng. reset() được gọi từ Global.reset_run()
## để thói quen của ván trước không áp sang ván mới.
##
## Lưu ý thiết kế (chống Aimbot): mọi nơi dùng dữ liệu này PHẢI cộng thêm "Human Error" —
## xem human_error_rad() — biên độ lệch góc giảm dần khi _confidence tăng (càng nhiều dữ
## liệu, quái càng "đọc vị" đúng hơn), KHÔNG BAO GIỜ về 0 hẳn để tránh né là vô nghĩa.

var dodge_bias: float = 0.0        # EMA: -1 = hay né trái, +1 = hay né phải
var melee_bias: float = 0.0        # EMA: -1 = hay đứng xa xả súng, +1 = hay lao cận chiến
var shots_per_sec: float = 0.0     # EMA tần suất ra đòn gần đây

var _confidence: float = 0.0       # 0..1 — càng nhiều mẫu quan sát càng tự tin
const EMA_RATE: float = 0.15
const CONF_GROW: float = 0.05

var _last_attack_t: float = 0.0
var _attack_interval_ema: float = 0.6


func reset() -> void:
	dodge_bias = 0.0
	melee_bias = 0.0
	shots_per_sec = 0.0
	_confidence = 0.0
	_last_attack_t = 0.0
	_attack_interval_ema = 0.6


## Gọi từ player.gd::_start_roll() mỗi lần né — dir_x: thành phần ngang của hướng né.
func record_dodge(dir_x: float) -> void:
	if absf(dir_x) < 0.01:
		return
	dodge_bias = lerpf(dodge_bias, signf(dir_x), EMA_RATE)
	_confidence = minf(1.0, _confidence + CONF_GROW)


## Gọi từ player.gd::_shoot()/_swing() mỗi lần ra đòn.
func record_attack(is_melee: bool) -> void:
	melee_bias = lerpf(melee_bias, 1.0 if is_melee else -1.0, EMA_RATE)
	var now: float = Time.get_ticks_msec() / 1000.0
	if _last_attack_t > 0.0:
		var interval: float = maxf(0.05, now - _last_attack_t)
		_attack_interval_ema = lerpf(_attack_interval_ema, interval, EMA_RATE)
		shots_per_sec = 1.0 / _attack_interval_ema
	_last_attack_t = now
	_confidence = minf(1.0, _confidence + CONF_GROW)


## Biên độ lệch góc ngẫu nhiên ("Human Error") quái nên cộng thêm khi dùng dữ liệu dự đoán —
## 18° khi gần như chưa có dữ liệu, giảm dần còn 4° khi đã quan sát đủ lâu (không bao giờ = 0).
func human_error_rad() -> float:
	return deg_to_rad(lerpf(18.0, 4.0, _confidence))


## Trọng số 0..1 cho việc "đón đầu" theo dodge_bias/vận tốc — nhân với biên độ dự đoán ở nơi gọi.
func predictive_lead_weight() -> float:
	return lerpf(0.0, 1.0, _confidence)
