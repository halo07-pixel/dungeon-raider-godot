extends Node
class_name HurtboxComponent
## Thành phần NHẬN sát thương (Hurtbox) — tách ra từ enemy.gd (Phase 5: Hitbox/Hurtbox
## Component Pattern). Sở hữu toàn bộ state "tôi bị đánh thì chuyện gì xảy ra với tôi":
## hp/giáp, vật lý knockback (tính toán, KHÔNG tự áp velocity — việc đó vẫn thuộc
## _physics_process() của CharacterBody2D chủ sở hữu), và các trạng thái khống chế
## (choáng/chậm/chảy máu). KHÔNG biết gì về sprite, âm thanh, hiệu ứng hạt — những thứ
## đó là phản ứng UI/VFX, chủ sở hữu tự nghe signal rồi tự xử lý (đúng nguyên tắc
## "vật lý ở _physics_process, UI/âm thanh dùng Signal").
##
## Vì toàn dự án đang gọi enemy_instance.take_damage()/.apply_status() trực tiếp
## (duck-typing) ở ~15 nơi (bullet.gd, player.gd, boss.gd, spike_trap.gd,...), component
## này KHÔNG đổi giao diện bên ngoài — enemy.gd giữ take_damage()/apply_status() như cũ,
## chỉ còn 1 dòng forward vào đây.

signal hurt(amount: int, knockback_vec: Vector2, true_dmg: bool)
signal died

## "alive" KHÔNG tương đương "hp > 0": kill() (vd. frost_tiny tự huỷ sau khi chạm) có
## thể giết ngay cả khi hp còn dư, giữ đúng hành vi gốc của enemy.gd — nên để alive là
## 1 field riêng, không suy ra từ hp.
var alive: bool = true
var hp: float = 0.0
var max_hp: float = 0.0
var armor: float = 0.0
var cc_resist: float = 0.0
var weight: float = 1.0

var stun_timer: float = 0.0
var slow_timer: float = 0.0
var bleed_ticks: int = 0
var bleed_timer: float = 0.0

const BLEED_TICK_INTERVAL: float = 0.5
const BLEED_TICK_DAMAGE: int = 5

## Buff "Phá Giáp" (Sử Thi) của Player: mỗi đòn trúng cộng 1 stack, mỗi stack tăng %
## sát thương quái NÀY phải nhận, hết hạn nếu ngừng bị đánh trúng quá SUNDER_DURATION giây.
var sunder_stacks: int = 0
var sunder_timer: float = 0.0
const SUNDER_PER_STACK: float = 0.08
const SUNDER_MAX_STACKS: int = 5
const SUNDER_DURATION: float = 3.0

func apply_sunder() -> void:
	if not alive:
		return
	sunder_stacks = mini(sunder_stacks + 1, SUNDER_MAX_STACKS)
	sunder_timer = SUNDER_DURATION

func tick_sunder(delta: float) -> void:
	if sunder_stacks <= 0:
		return
	sunder_timer -= delta
	if sunder_timer <= 0.0:
		sunder_stacks = 0

## _owner2d: tham chiếu tới Node2D cha (Enemy) để lấy global_position khi tính hướng
## knockback — đây là component con đọc vị trí của node sở hữu trực tiếp nó, không phải
## kiểu get_parent().get_parent() xuyên cấp bị cấm.
@onready var _owner2d: Node2D = get_parent()

func setup(p_max_hp: float, p_armor: float, p_cc_resist: float, p_weight: float) -> void:
	alive = true
	max_hp = p_max_hp
	hp = p_max_hp
	armor = p_armor
	cc_resist = p_cc_resist
	weight = maxf(p_weight, 0.01)
	stun_timer = 0.0
	slow_timer = 0.0
	bleed_ticks = 0
	bleed_timer = 0.0

## Nhận 1 đòn đánh. Trả về sát thương thực nhận (để enemy.gd hiển thị số bay lên) —
## giữ nguyên công thức gốc từ enemy.gd.take_damage(): true_dmg bỏ qua giáp, còn lại
## trừ giáp nhưng tối thiểu 1 dmg.
func take_hit(amount: int, from_pos: Vector2 = Vector2.ZERO, knock: float = 200.0, true_dmg: bool = false) -> int:
	if not alive:
		return 0
	var actual_damage: int = amount
	if not true_dmg:
		actual_damage = maxi(1, amount - int(armor))
	if sunder_stacks > 0:
		actual_damage = int(float(actual_damage) * (1.0 + SUNDER_PER_STACK * float(sunder_stacks)))
	hp = maxf(hp - float(actual_damage), 0.0)
	var actual_knock: float = knock * (1.0 - cc_resist)
	var knockback_vec: Vector2 = (_owner2d.global_position - from_pos).normalized() * actual_knock / weight
	hurt.emit(actual_damage, knockback_vec, true_dmg)
	if hp <= 0.0:
		mark_dead()
	return actual_damage

## Giết ngay lập tức, không qua tính hp (vd. frost_tiny tự huỷ sau khi chạm dù hp còn
## dư) — idempotent, gọi nhiều lần không phát lại tín hiệu died.
func mark_dead() -> void:
	if not alive:
		return
	alive = false
	died.emit()

func apply_status(type: String, duration: float) -> void:
	if type == "stun":
		stun_timer = maxf(stun_timer, duration)
	elif type == "slow":
		slow_timer = maxf(slow_timer, duration)
	elif type == "bleed":
		bleed_ticks = 4 # Chảy máu 4 nhịp
		bleed_timer = BLEED_TICK_INTERVAL

func is_stunned() -> bool:
	return stun_timer > 0.0

func is_slowed() -> bool:
	return slow_timer > 0.0

## 3 hàm dưới đây được enemy.gd._physics_process() gọi riêng lẻ, theo ĐÚNG thứ tự và
## ngữ nghĩa gốc (bleed luôn chạy trước, stun kiểm tra+trừ+rẽ nhánh/return sớm, slow
## kiểm tra+trừ+nhân vào move) — tách makeý thành 3 hàm nhỏ thay vì 1 "tick_status" gộp
## để không làm lệch thứ tự frame so với enemy.gd.take_damage() gốc (vd. nếu gộp chung
## rồi trừ timer trước khi enemy.gd kịp đọc, stun/slow sẽ kết thúc sớm hơn gốc 1 frame).

func tick_bleed(delta: float) -> void:
	if not alive or bleed_ticks <= 0:
		return
	bleed_timer -= delta
	if bleed_timer <= 0.0:
		bleed_timer = BLEED_TICK_INTERVAL
		bleed_ticks -= 1
		take_hit(BLEED_TICK_DAMAGE, _owner2d.global_position, 0.0, true)
		Global.burst(_owner2d.global_position, Color.DARK_RED, 3, 50.0, 1.0)

## Trả về true nếu đang choáng NGAY TRƯỚC khi trừ delta (khớp semantics gốc: frame
## cuối cùng còn choáng vẫn được coi là choáng), đồng thời tự trừ timer.
func consume_stun(delta: float) -> bool:
	if stun_timer > 0.0:
		stun_timer -= delta
		return true
	return false

func consume_slow(delta: float) -> bool:
	if slow_timer > 0.0:
		slow_timer -= delta
		return true
	return false
