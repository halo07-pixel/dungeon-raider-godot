extends Node
class_name MeleeHitboxComponent
## Thành phần GÂY sát thương cận chiến (Hitbox) — tách ra từ enemy.gd::_touch_attack()/
## _apply_touch_effect() (Phase 5: Hitbox/Hurtbox Component Pattern). Tự lắng nghe
## Area2D "TouchZone" (đổi tên từ "$Hitbox" cũ — bản chất nó là vùng CẢM BIẾN tầm đánh,
## không phải thứ trực tiếp gây damage, nên đổi tên cho đúng nghĩa) và tự quản lý
## cooldown riêng, tách bạch khỏi ActionTimer (giờ chỉ còn lo bắn/slam tầm xa).
##
## Chủ sở hữu (Enemy) gọi setup() đúng 1 lần ở _ready() để trao tham chiếu — không
## get_parent().get_parent(), không tự ý đi tìm Node bằng đường dẫn cứng.

@onready var cooldown: Timer = $Cooldown

var _owner2d: CharacterBody2D
var _hurtbox: HurtboxComponent
var _data: Dictionary = {}
var _in_touch: bool = false

func setup(p_owner: CharacterBody2D, p_hurtbox: HurtboxComponent, p_touch_zone: Area2D, p_data: Dictionary) -> void:
	_owner2d = p_owner
	_hurtbox = p_hurtbox
	_data = p_data
	cooldown.one_shot = true
	cooldown.timeout.connect(_on_cooldown_timeout)
	p_touch_zone.body_entered.connect(_on_zone_entered)
	p_touch_zone.body_exited.connect(_on_zone_exited)

func _on_zone_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_in_touch = true
		try_attack()

func _on_zone_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_in_touch = false

func _on_cooldown_timeout() -> void:
	if _in_touch:
		try_attack()

func is_in_touch() -> bool:
	return _in_touch

## Gọi khi vào tầm (va chạm), khi hồi chiêu xong mà vẫn còn trong tầm, hoặc khi quái
## vừa spawn xong (_owner2d.active chuyển true) mà người chơi đã đứng sẵn trong tầm.
func try_attack() -> void:
	if not _owner2d.active or not _owner2d.alive or not _in_touch:
		return
	if _hurtbox.is_stunned():
		return
	if not cooldown.is_stopped():
		return
	var p = Global.player
	if not is_instance_valid(p) or not p.alive:
		return
	p.take_damage(int(_data["touch"]), _owner2d.global_position, float(_data["touch_knock"]))
	_apply_touch_effect(p)
	if _owner2d.kind == "frost_tiny":
		_owner2d.kill() # Vỡ Băng: lao tới, chạm 1 phát rồi tự huỷ, không trụ lại đánh dai dẳng
		return
	cooldown.start(float(_data["touch_cd"]))

## Hiệu ứng ĐẶC TRƯNG BIOME gắn kèm đòn chạm — chỉ đúng 1 nhánh khớp "kind" hiện tại,
## các loại quái không có nhánh riêng (slime/archer/brute/frost_zombie base...) thì bỏ qua.
func _apply_touch_effect(p) -> void:
	if not p.has_method("apply_status"):
		return
	match _owner2d.kind:
		"chort":
			p.apply_status("poison", 2, 3) # Cắn Độc: độc nhẹ, cộng dồn được với Shaman
		"masked_orc":
			p.apply_status("slow", 1.0) # Trì Trệ Đầm Lầy: ghì chân để Shaman/Chort dồn độc
		"frost_zombie":
			p.apply_status("slide", 0.5) # Chạm Giá: mất lái, nguy hiểm gần bẫy/Ô Băng
