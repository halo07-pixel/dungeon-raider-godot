extends CanvasLayer
## HUD: thanh máu, thanh Dodge, thông tin tầng/súng/xu, thanh Boss, thông báo, minimap.
## Đã gỡ bỏ màn hình Title và Game Over (chuyển sang main.gd quản lý).

const MinimapScript = preload("res://scripts/minimap.gd")

var hearts_box: HBoxContainer
var heart_icons: Array = []
var heart_tex: Dictionary = {}
var _hearts_max_hp: float = -1.0
var dodge_bar: ProgressBar
var info_label: Label
var boss_box: Control
var boss_bar: ProgressBar
var boss_label: Label
var msg_label: Label
var minimap: Control
var _msg_tween: Tween

func _ready() -> void:
	_build_ui()
	Global.boss_spawned.connect(_on_boss_spawned)
	Global.boss_hp_changed.connect(_on_boss_hp)
	Global.boss_defeated.connect(_on_boss_defeated)
	Global.message.connect(_show_message)
	
	# Đảm bảo game chạy ngay lập tức, không bị pause
	get_tree().paused = false 
	
	var d_node = get_tree().get_first_node_in_group("dungeon")
	if d_node:
		minimap.dungeon = d_node

func _process(_delta: float) -> void:
	var p = Global.player
	if not is_instance_valid(p):
		return
	_update_hearts(float(p.hp), float(p.max_hp))
	dodge_bar.value = p.dodge_ratio() * 100.0
	
	var w_name = "Chưa có"
	if p.get("weapon") and p.weapon.has("name"):
		w_name = p.weapon["name"]
	info_label.text = "Tầng %d   ·   %s   ·   Xu: %d" % [Global.floor_num, w_name, Global.coins]

# ------------------------------------------------------------------ Sự kiện
func _on_boss_spawned(boss) -> void:
	boss_box.visible = true
	boss_label.text = "%s" % [boss.BOSS_NAME]
	boss_bar.max_value = boss.max_hp
	boss_bar.value = boss.hp

func _on_boss_hp(hp: float, max_hp: float, phase: int, boss_name: String) -> void:
	boss_bar.max_value = max_hp
	boss_bar.value = hp
	boss_label.text = "%s" % [boss_name]

func _on_boss_defeated() -> void:
	boss_box.visible = false

func _show_message(text: String, color: Color) -> void:
	msg_label.text = text
	msg_label.add_theme_color_override("font_color", color)
	msg_label.modulate.a = 1.0
	if _msg_tween != null and _msg_tween.is_valid():
		_msg_tween.kill()
	_msg_tween = create_tween()
	_msg_tween.tween_interval(1.8)
	_msg_tween.tween_property(msg_label, "modulate:a", 0.0, 0.6)

# ------------------------------------------------------------------ Dựng UI
func _label(parent: Node, text: String, font_size: int, pos: Vector2, sz: Vector2, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = sz
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l)
	return l

func _bar(parent: Node, pos: Vector2, sz: Vector2, fill: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.position = pos
	b.size = sz
	b.show_percentage = false
	var f := StyleBoxFlat.new()
	f.bg_color = fill
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	b.add_theme_stylebox_override("fill", f)
	b.add_theme_stylebox_override("background", bg)
	parent.add_child(b)
	return b

## Nạp 3 trạng thái tim (đầy/nửa/rỗng) từ asset 0x72 — dùng chung 1 lần cho mọi icon.
func _load_heart_tex() -> void:
	for state in ["full", "half", "empty"]:
		var img := Image.new()
		if img.load("res://assets/dungeon/ui_heart_%s.png" % state) == OK:
			heart_tex[state] = ImageTexture.create_from_image(img)


## Mỗi tim đại diện 1/10 máu tối đa — luôn hiện đúng 10 tim bất kể HP gốc bao nhiêu
## (Xạ Thủ 100 HP hay Đấu Sĩ 200 HP đều hiện 10 tim, chỉ khác "nặng" mỗi tim).
func _update_hearts(hp: float, max_hp: float) -> void:
	if max_hp <= 0.0:
		return
	if not is_equal_approx(max_hp, _hearts_max_hp):
		_hearts_max_hp = max_hp
		for h in heart_icons:
			h.queue_free()
		heart_icons.clear()
		for i in 10:
			var t := TextureRect.new()
			t.custom_minimum_size = Vector2(28.0, 28.0)
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			hearts_box.add_child(t)
			heart_icons.append(t)
	var per_heart: float = max_hp / 10.0
	for i in heart_icons.size():
		var fill: float = clampf((hp - float(i) * per_heart) / per_heart, 0.0, 1.0)
		var state: String = "empty"
		if fill >= 0.75: state = "full"
		elif fill >= 0.25: state = "half"
		if heart_tex.has(state):
			heart_icons[i].texture = heart_tex[state]


func _build_ui() -> void:
	_load_heart_tex()
	hearts_box = HBoxContainer.new()
	hearts_box.position = Vector2(20.0, 16.0)
	hearts_box.add_theme_constant_override("separation", 2)
	add_child(hearts_box)
	dodge_bar = _bar(self, Vector2(20.0, 50.0), Vector2(280.0, 8.0), Color(0.4, 0.8, 1.0))
	dodge_bar.max_value = 100.0
	info_label = _label(self, "", 16, Vector2(20.0, 64.0), Vector2(500.0, 26.0))

	minimap = Control.new()
	minimap.set_script(MinimapScript)
	minimap.position = Vector2(1170.0, 20.0)
	minimap.size = Vector2(90.0, 65.0)
	add_child(minimap)

	boss_box = Control.new()
	boss_box.position = Vector2(340.0, 20.0)
	boss_box.size = Vector2(600.0, 44.0)
	boss_box.visible = false
	add_child(boss_box)
	boss_label = _label(boss_box, "", 16, Vector2(0.0, 0.0), Vector2(600.0, 22.0), HORIZONTAL_ALIGNMENT_CENTER)
	boss_bar = _bar(boss_box, Vector2(0.0, 24.0), Vector2(600.0, 16.0), Color(0.7, 0.2, 0.8))

	msg_label = _label(self, "", 28, Vector2(0.0, 110.0), Vector2(1280.0, 44.0), HORIZONTAL_ALIGNMENT_CENTER)
	msg_label.modulate.a = 0.0
