extends Node
## Chạy hiệu ứng Sigil theo sự kiện của kỹ năng (Node con của Player). Tách khỏi vật lý: chỉ nghe tín hiệu —
##   on_cast  : ClassSkill/TomeSkill.skill_used (bind đích "class"/"tome")
##   _on_hit  : Global.skill_hit_landed(src, target, dmg) — chỉ đòn do kỹ năng/lính của kỹ năng đó gây ra
## Hiệu ứng nào cũng đọc Sigil qua Global.run_sigils[đích] nên đổi Sigil giữa ván có tác dụng ngay.

const Sigils = preload("res://scripts/sigils.gd")

const SIPHON_INTERVAL: float = 0.33
const RECAST_DELAY: float = 0.45
const SLOW_SECONDS: float = 1.5
const CHAIN_FRACTION: float = 0.5
const CHAIN_TARGETS: int = 2
const BURN_FRACTION: float = 0.12

var player: Node = null
var _siphon_t: float = 0.0

func setup(p_player: Node) -> void:
	player = p_player
	Global.skill_hit_landed.connect(_on_hit)

func _exit_tree() -> void:
	if Global.skill_hit_landed.is_connected(_on_hit):
		Global.skill_hit_landed.disconnect(_on_hit)

func _process(delta: float) -> void:
	_siphon_t = maxf(0.0, _siphon_t - delta)

func total(target: String, key: String) -> float:
	return Sigils.total(Global.run_sigils.get(target, []), key)

func _skill_node(target: String) -> Node:
	return player.class_skill if target == "class" else player.tome_skill

# ---------------------------------------------------------------- Khi tung kỹ năng
func on_cast(_skill_id: String, target: String) -> void:
	if not is_instance_valid(player) or not player.alive:
		return
	var shield: float = total(target, "shield")
	if shield > 0.0:
		player.shield = minf(float(player.max_shield), player.shield + shield)
		Global.float_text(player.global_position + Vector2(0, -52), "+%d SHIELD" % int(shield), Color(0.6, 0.85, 1.0), 14)
	var crits: int = int(total(target, "crits"))
	if crits > 0:
		player.grant_skill_crits(crits)
	var rc: float = total(target, "recast")
	if rc > 0.0 and randf() < rc:
		recast(target)

## Tung lại kỹ năng miễn phí sau một nhịp ngắn (không tốn hồi chiêu, không kích hoạt lại Sigil "khi tung").
func recast(target: String) -> void:
	await get_tree().create_timer(RECAST_DELAY).timeout
	if not is_instance_valid(player) or not player.alive:
		return
	var node: Node = _skill_node(target)
	if node != null and is_instance_valid(node):
		Global.float_text(player.global_position + Vector2(0, -52), "ECHO", Color(0.8, 0.6, 1.0), 16)
		node.execute_free()

# ---------------------------------------------------------------- Khi kỹ năng trúng đòn
func _on_hit(src: String, target: Node, dmg: int) -> void:
	if not Sigils.TARGETS.has(src) or not is_instance_valid(target) or not is_instance_valid(player):
		return
	var burn: float = total(src, "burn")
	if burn > 0.0 and randf() < burn and target.has_method("apply_element") and bool(target.get("alive")):
		target.apply_element("burn", maxi(2, int(float(dmg) * BURN_FRACTION)), 0)
	var slow: float = total(src, "slow")
	if slow > 0.0 and randf() < slow and target.has_method("apply_status") and bool(target.get("alive")):
		target.apply_status("slow", SLOW_SECONDS)
	var heal: float = total(src, "heal")
	if heal > 0.0 and _siphon_t <= 0.0 and player.alive:
		_siphon_t = SIPHON_INTERVAL
		player.leech(int(heal))
	if total(src, "sunder") > 0.0 and target.has_method("apply_sunder") and bool(target.get("alive")):
		target.apply_sunder()
	var chain: float = total(src, "chain")
	if chain > 0.0 and randf() < chain and bool(target.get("alive")):
		Global.chain_lightning(target, int(float(dmg) * CHAIN_FRACTION), CHAIN_TARGETS)
	var refund: float = total(src, "refund")
	if refund > 0.0 and not bool(target.get("alive")):
		var node: Node = _skill_node(src)
		if node != null and is_instance_valid(node):
			node.refund_cooldown(refund)
