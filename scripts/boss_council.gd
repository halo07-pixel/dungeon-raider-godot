extends Node
## Hội Đồng Bốn Boss (Council Trial): Warden + Necromancer + Frozen Horror + Dungeon Lord trong một đấu trường.
## Bốn boss đánh đủ bộ cùng lúc sẽ thành "chết phi lý", nên council điều phối bằng 3 luật:
##   1. Thẻ tấn công: tại mỗi thời điểm chỉ một số boss được ra đòn (boss xin qua signal token_requested,
##      council cấp bằng cách đặt has_token). Boss không có thẻ vẫn đi áp sát nhưng chưa ra đòn. Mỗi boss
##      gục thì số thẻ tăng -> trận càng cuối càng dồn dập.
##   2. Thứ tự hạ gục: khi một boss (khác Necromancer) sắp chết mà Necromancer còn sống, nó được hồi sinh MỘT
##      LẦN với một phần máu -> nên ưu tiên hạ Necromancer.
##   3. Gục là nổi giận: boss gục thì các boss còn lại lên một pha và để lại vũng nguy hiểm tại chỗ ngã.
## Council chỉ giao tiếp bằng signal với boss (call down, signal up) và phát all_defeated đúng một lần.

signal all_defeated
signal boss_fell(boss)
signal revived(boss)

const BOSS_HAZARD = preload("res://scripts/boss_hazard.gd")

const KINDS: Array = ["warden", "necromancer", "frost", "lord"]
const HP_MULT: float = 0.42              # máu mỗi boss so với bản đơn lẻ; tổng bốn con ~1.5 lần một Lord
const TOKENS_START: int = 2              # số boss được ra đòn cùng lúc khi còn đủ bốn
const TOKENS_MAX: int = 4
const REVIVE_HP_FRACTION: float = 0.35
const REVIVE_INVULN: float = 1.5
const LORD_FINAL_ALIVE: int = 2          # còn ít hơn hoặc bằng chừng này boss thì nhạc chuyển sang cao trào
const CORPSE_HAZARD_RADIUS: float = 70.0
const CORPSE_HAZARD_DAMAGE: int = 6
const CORPSE_HAZARD_DURATION: float = 4.0
const CORPSE_HAZARD_TICK: float = 0.6

var bosses: Array = []
var _in_use: Array = []          # boss đang giữ thẻ
var revive_used: bool = false
var _finished: bool = false

func setup(p_bosses: Array) -> void:
	bosses = p_bosses.duplicate()
	for b in bosses:
		b.set_council(self)
		b.token_requested.connect(_on_token_requested)
		b.token_released.connect(_on_token_released)
		b.died.connect(_on_boss_died.bind(b))

# --- Thẻ tấn công ---
static func tokens_for(dead_count: int) -> int:
	return clampi(TOKENS_START + dead_count, 1, TOKENS_MAX)

func alive_bosses() -> Array:
	return bosses.filter(func(b): return is_instance_valid(b) and bool(b.alive))

func dead_count() -> int:
	return bosses.size() - alive_bosses().size()

func max_tokens() -> int:
	return tokens_for(dead_count())

func tokens_in_use() -> int:
	_in_use = _in_use.filter(func(b): return is_instance_valid(b) and bool(b.alive))
	return _in_use.size()

func _on_token_requested(b) -> void:
	if not bool(b.alive) or _in_use.has(b):
		return
	if tokens_in_use() < max_tokens():
		b.has_token = true
		_in_use.append(b)

func _on_token_released(b) -> void:
	_in_use.erase(b)

# --- Hồi sinh ---
## Boss gọi khi máu về 0. true = council đã cứu boss (boss không chết).
func try_revive(b) -> bool:
	if revive_used or b.kind == "necromancer":
		return false
	var necro = null
	for o in alive_bosses():
		if o.kind == "necromancer":
			necro = o
	if necro == null:
		return false
	revive_used = true
	b.begin_rebirth(REVIVE_HP_FRACTION, REVIVE_INVULN)
	Global.sfx("council_revive")
	Global.burst(necro.global_position, Color(0.7, 0.3, 0.9), 20, 200.0, 1.8)
	Global.message.emit("The Necromancer revives %s!" % String(b.BOSS_NAME), Color(0.75, 0.4, 1.0))
	revived.emit(b)
	return true

# --- Gục và nổi giận ---
func _on_boss_died(b) -> void:
	_in_use.erase(b)
	boss_fell.emit(b)
	_spawn_corpse_hazard(b.global_position)
	var left: Array = alive_bosses()
	if left.is_empty():
		if not _finished:
			_finished = true
			all_defeated.emit()
		return
	Global.sfx("council_rage")
	Global.message.emit("The Council is enraged!", Color(1.0, 0.3, 0.2))
	for o in left:
		o.council_rage()
	if left.size() <= LORD_FINAL_ALIVE:
		# Nhạc nghe boss_hp_changed (phase >= 3 của Lord) để chuyển sang cao trào.
		Global.boss_hp_changed.emit(1.0, 1.0, 3, "Council")

func _spawn_corpse_hazard(pos: Vector2) -> void:
	var hz := Area2D.new()
	hz.set_script(BOSS_HAZARD)
	hz.damage = CORPSE_HAZARD_DAMAGE
	hz.radius = CORPSE_HAZARD_RADIUS
	hz.duration = CORPSE_HAZARD_DURATION
	hz.tick_interval = CORPSE_HAZARD_TICK
	hz.telegraph_time = 0.5
	hz.apply_burn_ticks = 2
	hz.color = Color(0.8, 0.25, 0.9, 0.4)
	Global.world.add_child.call_deferred(hz)
	hz.set_deferred("global_position", pos)
