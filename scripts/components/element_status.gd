extends RefCounted
## Trạng thái nguyên tố trên MỘT mục tiêu (quái hoặc boss): Thiêu Đốt, Độc cộng dồn, Băng Giá.
## Dùng chung cho hurtbox_component.gd (quái thường) và boss.gd — mỗi bên chỉ cần cấp 3 callable:
##   dot_cb(dmg: int, color: Color)  — gây sát thương theo thời gian (bỏ qua giáp)
##   slow_cb(duration: float)        — làm chậm (nếu mục tiêu hỗ trợ)
##   freeze_cb(duration: float)      — đóng băng/choáng (nếu mục tiêu hỗ trợ; boss không truyền)

const TICK: float = 0.5
const BURN_DURATION: float = 3.0
const POISON_DURATION: float = 4.0
const FROST_DECAY: float = 3.0
const FREEZE_DURATION: float = 1.2   # thời gian GỐC; hurtbox nhân CC_DURATION_MULT (0.5) -> ~0.6s ở tầng 1
const FREEZE_IMMUNE: float = 4.0

var dot_cb: Callable
var slow_cb: Callable
var freeze_cb: Callable

var burn_time: float = 0.0
var burn_dmg: int = 0
var _burn_tick: float = TICK

var poison_stacks: int = 0
var poison_time: float = 0.0
var poison_dmg: int = 0
var _poison_tick: float = TICK

var frost_stacks: int = 0
var frost_decay: float = 0.0
var freeze_immune: float = 0.0
var frozen_count: int = 0 # tổng số lần đã đóng băng (phục vụ test/thống kê)

func apply_burn(dmg_per_tick: int) -> void:
	burn_time = BURN_DURATION
	burn_dmg = maxi(burn_dmg, dmg_per_tick)

func apply_poison(dmg_per_stack: int, max_stacks: int) -> void:
	poison_stacks = mini(poison_stacks + 1, max_stacks)
	poison_time = POISON_DURATION
	poison_dmg = maxi(poison_dmg, dmg_per_stack)

## need: số stack để đóng băng (3, hoặc 2 khi buff cấp 2). can_freeze=false -> chỉ làm chậm (boss).
func apply_frost(need: int, can_freeze: bool) -> void:
	if freeze_immune > 0.0:
		return
	frost_stacks += 1
	frost_decay = FROST_DECAY
	if slow_cb.is_valid():
		slow_cb.call(1.5)
	if can_freeze and frost_stacks >= need and freeze_cb.is_valid():
		frost_stacks = 0
		freeze_immune = FREEZE_IMMUNE
		frozen_count += 1
		freeze_cb.call(FREEZE_DURATION)

func is_active() -> bool:
	return burn_time > 0.0 or poison_stacks > 0 or frost_stacks > 0 or freeze_immune > 0.0

func tick(delta: float) -> void:
	if freeze_immune > 0.0:
		freeze_immune = maxf(0.0, freeze_immune - delta)
	if frost_stacks > 0:
		frost_decay -= delta
		if frost_decay <= 0.0:
			frost_stacks = 0
	if burn_time > 0.0:
		burn_time -= delta
		_burn_tick -= delta
		if _burn_tick <= 0.0:
			_burn_tick = TICK
			dot_cb.call(burn_dmg, Color(1.0, 0.5, 0.1))
		if burn_time <= 0.0:
			burn_dmg = 0
	if poison_stacks > 0:
		poison_time -= delta
		_poison_tick -= delta
		if _poison_tick <= 0.0:
			_poison_tick = TICK
			dot_cb.call(poison_dmg * poison_stacks, Color(0.5, 0.9, 0.2))
		if poison_time <= 0.0:
			poison_stacks = 0
			poison_dmg = 0
