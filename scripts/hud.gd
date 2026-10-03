extends CanvasLayer
## HUD: thanh máu, thanh Dodge, thông tin tầng/súng/xu, thanh Boss, thông báo, minimap.
## Đã gỡ bỏ màn hình Title và Game Over (chuyển sang main.gd quản lý).

const MinimapScript = preload("res://scripts/minimap.gd")

var hp_bar: ProgressBar
var hp_label: Label
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
	hp_bar.max_value = float(p.max_hp)
	hp_bar.value = float(p.hp)
	hp_label.text = "HP %d / %d" % [p.hp, p.max_hp]
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

func _build_ui() -> void:
	hp_bar = _bar(self, Vector2(20.0, 20.0), Vector2(280.0, 24.0), Color(0.85, 0.2, 0.25))
	hp_label = _label(self, "HP", 16, Vector2(20.0, 20.0), Vector2(280.0, 24.0), HORIZONTAL_ALIGNMENT_CENTER)
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
