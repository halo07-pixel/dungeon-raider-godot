extends CanvasLayer
## HUD: thanh máu, thanh Dodge, thông tin tầng/súng/xu, thanh Boss, thông báo, minimap.
## Đã gỡ bỏ màn hình Title và Game Over (chuyển sang main.gd quản lý).

const MinimapScript = preload("res://scripts/minimap.gd")
const ShieldBarScript = preload("res://scripts/shield_bar.gd")
const BOSS_PHASE_COLORS: Array = [Color(0.7, 0.25, 0.85), Color(0.95, 0.55, 0.15), Color(0.95, 0.2, 0.2), Color(0.95, 0.95, 1.0)]

var hearts_box: HBoxContainer
var heart_icons: Array = []
var heart_tex: Dictionary = {}
var _hearts_max_hp: float = -1.0
var dodge_bar: ProgressBar
var shield_bar: Control
var vignette: TextureRect
var _vignette_tween: Tween
var boss_fill: StyleBoxFlat
var boss_ticks: Control
var _boss_phases: int = 3
var info_label: Label
var skill_label: Label
var weapon_bar: ProgressBar ## cung: mức căng dây; vũ khí khác: hồi đòn
var weapon_bar_fill: StyleBoxFlat
var weapon_labels: Array = [] ## 2 nhãn, mỗi nhãn một ô vũ khí (ô đang cầm sáng + có dấu ">")
var boss_box: Control
var boss_bar: ProgressBar
var boss_label: Label
var msg_label: Label
var minimap: Control
var _msg_tween: Tween
var debug_label: Label ## TẠM: hiện thông tin phòng/quái để bắt bug "spawn sai phòng". Xoá sau khi tìm ra nguyên nhân.
var _dungeon_ref: Node = null

func _ready() -> void:
	_build_ui()
	Global.boss_spawned.connect(_on_boss_spawned)
	Global.boss_hp_changed.connect(_on_boss_hp)
	Global.boss_defeated.connect(_on_boss_defeated)
	Global.message.connect(_show_message)
	Global.player_damaged.connect(_on_player_damaged)

	# Đảm bảo game chạy ngay lập tức, không bị pause
	get_tree().paused = false

	var d_node = get_tree().get_first_node_in_group("dungeon")
	if d_node:
		minimap.dungeon = d_node
		_dungeon_ref = d_node

func _process(_delta: float) -> void:
	var p = Global.player
	if not is_instance_valid(p):
		return
	_update_hearts(float(p.hp), float(p.max_hp))
	dodge_bar.value = p.dodge_ratio() * 100.0
	_update_shield(p)
	
	info_label.text = "Floor %d   ·   Gold: %d" % [Global.floor_num, Global.coins]
	_update_weapon_labels(p)
	_update_weapon_bar(p)
	_update_skill_label(p)
	_update_debug_label()

## Hai ô vũ khí: ô đang cầm có dấu ">" và sáng; ô kia mờ (đổi bằng phím swap_weapon). Màu chữ theo độ hiếm.
func _update_weapon_labels(p) -> void:
	var slots = p.get("weapon_slots")
	if not (slots is Array):
		return
	var swap_key: String = Global.key_name_for_action("swap_weapon")
	for i in weapon_labels.size():
		var lbl: Label = weapon_labels[i]
		var slot: Dictionary = slots[i] if i < slots.size() else {}
		if slot.is_empty():
			lbl.text = "  [%d] - empty -" % (i + 1)
			lbl.modulate = Color(0.55, 0.55, 0.55, 0.7)
			continue
		var w: Dictionary = Global.weapons[String(slot["id"])]
		var r: Dictionary = Global.rarities[String(slot["rarity"])]
		var active: bool = (i == int(p.active_slot))
		lbl.text = "%s[%d] %s (%s)%s" % ["> " if active else "  ", i + 1, w["name"], r["name"], ("   [%s] swap" % swap_key) if active and not _other_empty(slots, i) else ""]
		var c: Color = r["color"]
		lbl.modulate = c if active else Color(c.r, c.g, c.b, 0.55)

## Thanh dưới ô vũ khí: cung hiện mức căng dây (vàng khi đầy), vũ khí khác hiện hồi đòn (ẩn khi đã sẵn sàng).
func _update_weapon_bar(p) -> void:
	var charge_weapon: bool = p.get("weapon") != null and p.weapon.has("charge_time")
	if charge_weapon and bool(p.charging):
		var r: float = float(p.charge_ratio())
		weapon_bar.visible = true
		weapon_bar.value = r * 100.0
		weapon_bar_fill.bg_color = Color(1.0, 0.9, 0.35) if r >= 1.0 else Color(0.75, 0.85, 1.0)
		return
	var ft: Timer = p.get("fire_timer")
	if ft != null and not ft.is_stopped() and ft.wait_time > 0.0:
		weapon_bar.visible = true
		weapon_bar.value = (1.0 - ft.time_left / ft.wait_time) * 100.0
		weapon_bar_fill.bg_color = Color(0.6, 0.6, 0.65)
	else:
		weapon_bar.visible = false

func _other_empty(slots: Array, i: int) -> bool:
	var j: int = 1 - i
	return j >= slots.size() or (slots[j] as Dictionary).is_empty()

## Chỉ báo kỹ năng class tiến hoá: "[Q] Barrage READY" hoặc đếm ngược hồi chiêu.
func _update_skill_label(p) -> void:
	var sk = p.get("class_skill")
	if sk == null or not is_instance_valid(sk):
		skill_label.visible = false
		return
	skill_label.visible = true
	var ups: int = Global.skill_upgrade_count(String(sk.skill_id))
	var up_tag: String = (" +%d" % ups) if ups > 0 else ""
	if sk.active_left > 0.0:
		skill_label.text = "[Q] %s%s  ACTIVE %.1fs" % [sk.skill_name, up_tag, sk.active_left]
		skill_label.modulate = Color(1.0, 0.6, 0.2)
	elif sk.is_ready():
		skill_label.text = "[Q] %s%s  READY" % [sk.skill_name, up_tag]
		skill_label.modulate = Color(1.0, 0.9, 0.4)
	else:
		skill_label.text = "[Q] %s%s  %.1fs" % [sk.skill_name, up_tag, sk.cooldown_left]
		skill_label.modulate = Color(0.7, 0.7, 0.7)

## TẠM: debug overlay bắt bug "qua tầng mới spawn vào phòng quái thay vì phòng start"
## và bug "quái hết mà cổng không mở". Xoá khi tìm ra nguyên nhân.
func _update_debug_label() -> void:
	if not is_instance_valid(debug_label):
		return
	if not is_instance_valid(_dungeon_ref):
		_dungeon_ref = get_tree().get_first_node_in_group("dungeon")
		if not is_instance_valid(_dungeon_ref):
			debug_label.text = "DBG: no dungeon ref"
			return
	var cell = _dungeon_ref.current_cell
	var rtype := "?"
	var cleared = "?"
	var visited = "?"
	if _dungeon_ref.rooms.has(cell):
		rtype = str(_dungeon_ref.rooms[cell].get("type", "?"))
		cleared = str(_dungeon_ref.rooms[cell].get("cleared", "?"))
		visited = str(_dungeon_ref.rooms[cell].get("visited", "?"))
	var group_alive := 0
	var group_total := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			group_total += 1
			if e.has_method("kill") and e.alive:
				group_alive += 1
	debug_label.text = "DBG room=%s type=%s cleared=%s visited=%s | counter=%d | group_alive=%d/%d" % [cell, rtype, cleared, visited, _dungeon_ref.alive_enemies, group_alive, group_total]

# ------------------------------------------------------------------ Sự kiện
func _on_boss_spawned(boss) -> void:
	boss_box.visible = true
	boss_label.text = "%s" % [boss.BOSS_NAME]
	boss_bar.max_value = boss.max_hp
	boss_bar.value = boss.hp
	var cfg = boss.BOSS_DATA.get(boss.kind, null)
	_boss_phases = int(cfg["phases"]) if cfg != null else 3
	boss_fill.bg_color = BOSS_PHASE_COLORS[0]
	boss_ticks.queue_redraw()

func _on_boss_hp(hp: float, max_hp: float, phase: int, boss_name: String) -> void:
	boss_bar.max_value = max_hp
	boss_bar.value = hp
	boss_label.text = "%s" % [boss_name]
	boss_fill.bg_color = BOSS_PHASE_COLORS[clampi(phase - 1, 0, BOSS_PHASE_COLORS.size() - 1)]

## Đòn nặng (>= 25% máu tối đa) → nháy viền đỏ quanh màn hình.
func _on_player_damaged(amount: int, max_hp: int) -> void:
	if max_hp <= 0 or float(amount) < 0.25 * float(max_hp):
		return
	vignette.modulate.a = 0.9
	if _vignette_tween: _vignette_tween.kill()
	_vignette_tween = create_tween()
	_vignette_tween.tween_property(vignette, "modulate:a", 0.0, 0.5)

func _draw_boss_ticks() -> void:
	var w: float = boss_ticks.size.x
	var h: float = boss_ticks.size.y
	for i in range(1, _boss_phases):
		var x: float = w * (1.0 - float(i) / float(_boss_phases))
		boss_ticks.draw_line(Vector2(x, 0.0), Vector2(x, h), Color(1, 1, 1, 0.75), 2.0)

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
		var tex := Global.load_tex("res://assets/dungeon/ui_heart_%s.png" % state)
		if tex:
			heart_tex[state] = tex


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


func _update_shield(p) -> void:
	shield_bar.max_value = float(maxi(1, p.max_shield))
	shield_bar.value = p.shield

func _build_ui() -> void:
	_load_heart_tex()
	hearts_box = HBoxContainer.new()
	hearts_box.position = Vector2(20.0, 16.0)
	hearts_box.add_theme_constant_override("separation", 2)
	add_child(hearts_box)
	shield_bar = Control.new()
	shield_bar.set_script(ShieldBarScript)
	shield_bar.position = Vector2(20.0, 48.0)
	shield_bar.size = Vector2(280.0, 12.0)
	add_child(shield_bar)
	dodge_bar = _bar(self, Vector2(20.0, 64.0), Vector2(280.0, 4.0), Color(0.4, 0.8, 1.0))
	dodge_bar.max_value = 100.0
	info_label = _label(self, "", 16, Vector2(20.0, 72.0), Vector2(500.0, 26.0))
	skill_label = _label(self, "", 14, Vector2(20.0, 98.0), Vector2(300.0, 22.0))
	skill_label.visible = false
	for i in Global.MAX_WEAPON_SLOTS:
		weapon_labels.append(_label(self, "", 14, Vector2(20.0, 122.0 + 20.0 * float(i)), Vector2(360.0, 22.0)))
	weapon_bar = _bar(self, Vector2(20.0, 126.0 + 20.0 * float(Global.MAX_WEAPON_SLOTS)), Vector2(220.0, 6.0), Color(0.6, 0.6, 0.65))
	weapon_bar.visible = false
	weapon_bar_fill = weapon_bar.get_theme_stylebox("fill") as StyleBoxFlat

	var grad := Gradient.new()
	grad.set_color(0, Color(0.9, 0.0, 0.0, 0.0))
	grad.set_color(1, Color(0.9, 0.0, 0.0, 0.85))
	grad.set_offset(0, 0.55)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	vignette = TextureRect.new()
	vignette.texture = gt
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.modulate.a = 0.0
	add_child(vignette)

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
	boss_fill = boss_bar.get_theme_stylebox("fill") as StyleBoxFlat
	boss_ticks = Control.new()
	boss_ticks.position = Vector2(0.0, 24.0)
	boss_ticks.size = Vector2(600.0, 16.0)
	boss_ticks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_ticks.draw.connect(_draw_boss_ticks)
	boss_box.add_child(boss_ticks)

	msg_label = _label(self, "", 28, Vector2(0.0, 110.0), Vector2(1280.0, 44.0), HORIZONTAL_ALIGNMENT_CENTER)
	msg_label.modulate.a = 0.0

	# TẠM: overlay debug góc dưới trái, màu vàng nổi bật để dễ nhận ra là tạm thời.
	debug_label = _label(self, "", 14, Vector2(20.0, 660.0), Vector2(900.0, 24.0))
	debug_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
