extends Area2D
## Lò Rèn (Forge): đứng cạnh Thương gia ở phòng xuất phát các tầng chẵn. Nâng cấp +1..+5 bằng vàng, reroll dòng phụ
## và phân rã bằng Phế Liệu, ghép 2 cây cùng loại/độ hiếm lên bậc kế. Luật nằm ở scripts/forge_logic.gd; file này chỉ lo giao diện.
const WeaponInstance = preload("res://scripts/weapon_instance.gd")
const ForgeLogic = preload("res://scripts/forge_logic.gd")
const Art = preload("res://scripts/art.gd")

const INTERACT_RADIUS: float = 80.0

var player_in_range: bool = false
var ui: CanvasLayer
var box: VBoxContainer
var interact_label: Label
var _t: float = 0.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 15
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = INTERACT_RADIUS
	cs.shape = shape
	add_child(cs)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	interact_label = Label.new()
	interact_label.text = "[ENTER] Open Forge"
	interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interact_label.position = Vector2(-75, -64)
	_font(interact_label, 14)
	interact_label.add_theme_color_override("font_outline_color", Color.BLACK)
	interact_label.add_theme_constant_override("outline_size", 4)
	interact_label.hide()
	add_child(interact_label)
	_build_ui()

func _font(c: Control, size: int) -> void:
	c.add_theme_font_override("font", Global.pixel_font())
	c.add_theme_font_size_override("font_size", size)

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

## Đe + lò rèn: sprite 32x24 có 4 khung (tools/gen_art_pass.py), phóng 2x; ánh lửa vẽ thêm bằng code.
const SPRITE_SCALE: float = 2.0
func _draw() -> void:
	var flick: float = 0.5 + 0.5 * sin(_t * 9.0)
	draw_set_transform(Vector2(0, 14), 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, 34.0, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(Vector2(12, 0), 34.0 + 5.0 * flick, Color(1.0, 0.45, 0.1, 0.07 + 0.04 * flick)) # ánh lò
	var tex: Texture2D = Art.frame("forge_anim", 4, _t, 6.0)
	if tex == null:
		return
	var sz: Vector2 = tex.get_size() * SPRITE_SCALE
	draw_texture_rect(tex, Rect2(Vector2(-sz.x * 0.5, 14.0 - sz.y), sz), false)

func _on_body_entered(body: Node2D) -> void:
	if body.name.to_lower() == "player":
		player_in_range = true
		interact_label.show()

func _on_body_exited(body: Node2D) -> void:
	if body.name.to_lower() == "player":
		player_in_range = false
		interact_label.hide()
		_close()

func _input(event: InputEvent) -> void:
	if player_in_range and not ui.visible and event.is_action_pressed("ui_accept"):
		_open()
		get_viewport().set_input_as_handled()
	elif ui.visible and event.is_action_pressed("ui_cancel"):
		_close()

func _open() -> void:
	get_tree().paused = true
	_refresh()
	ui.show()

func _close() -> void:
	if ui.visible:
		ui.hide()
		get_tree().paused = false

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 105
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.04, 0.04, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(center)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	ui.hide()

func _btn(text: String, action: Callable, min_size: Vector2, color: Color, enabled: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.disabled = not enabled
	_font(b, 13)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color if enabled else Color(0.25, 0.25, 0.28)
	sb.set_corner_radius_all(8)
	sb.border_width_bottom = 5
	sb.border_color = sb.bg_color.darkened(0.4)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("disabled", sb)
	var hv: StyleBoxFlat = sb.duplicate()
	hv.bg_color = color.lightened(0.2)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(action)
	return b

func _lbl(text: String, size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	_font(l, size)
	return l

func _refresh() -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var p = Global.player
	if not is_instance_valid(p):
		return
	box.add_child(_lbl("THE FORGE", 24, Color(1.0, 0.6, 0.2)))
	box.add_child(_lbl("Gold: %d      Scrap: %d" % [Global.coins, Global.scrap], 16, Color(1.0, 0.85, 0.3)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	for i in 2:
		row.add_child(_slot_column(p, i))
	var fi: Dictionary = ForgeLogic.fuse_info(p.weapon_slots[0], p.weapon_slots[1])
	var fuse_text: String = fi["why"]
	var fuse_ok: bool = false
	if bool(fi["ok"]):
		fuse_text = "FUSE both -> %s   (%d gold%s)" % [String(Global.rarities[fi["result_rarity"]]["name"]), int(fi["gold"]), (" + %d scrap" % int(fi["scrap"])) if int(fi["scrap"]) > 0 else ""]
		fuse_ok = ForgeLogic.can_afford(int(fi["gold"]), int(fi["scrap"]))
	box.add_child(_btn(fuse_text, func(): _do(ForgeLogic.fuse(p)), Vector2(620, 50), Color(0.6, 0.3, 0.6), fuse_ok))
	box.add_child(_btn("Leave Forge", _close, Vector2(620, 46), Color(0.5, 0.2, 0.2)))

func _slot_column(p, i: int) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(300, 0)
	var inst: Dictionary = p.weapon_slots[i]
	if inst.is_empty():
		col.add_child(_lbl("[%d] - empty -" % (i + 1), 14, Color(0.5, 0.5, 0.5)))
		return col
	var r: Dictionary = Global.rarities[inst["rarity"]]
	var held: String = " (in hand)" if i == p.active_slot else ""
	col.add_child(_lbl("[%d] %s%s" % [i + 1, WeaponInstance.display_name(inst), held], 15, r["color"]))
	col.add_child(_lbl(String(r["name"]), 12, r["color"]))
	var lines: Array = WeaponInstance.affix_lines(inst)
	if inst["rarity"] == "mythic":
		var mt: Dictionary = WeaponInstance.mythic_trait(String(inst["id"]))
		if not mt.is_empty():
			lines.append("%s: %s" % [mt["name"], mt["desc"]])
	for ln in lines:
		var l := _lbl(String(ln), 11, Color(0.8, 0.85, 1.0))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(290, 0)
		col.add_child(l)
	var uc: int = ForgeLogic.upgrade_cost(inst)
	if uc < 0:
		col.add_child(_btn("Max level +%d" % WeaponInstance.MAX_LEVEL, func(): pass, Vector2(290, 44), Color(0.3, 0.3, 0.3), false))
	else:
		col.add_child(_btn("Upgrade to +%d - %d gold" % [int(inst["level"]) + 1, uc], func(): _do(ForgeLogic.upgrade(p, i)), Vector2(290, 44), Color(0.2, 0.5, 0.3), ForgeLogic.can_afford(uc, 0)))
	var rc: int = ForgeLogic.reroll_cost(inst)
	var rtxt: String = "Reroll affixes - %d scrap" % rc if rc >= 0 else ("Mythic: affixes locked" if inst["rarity"] == "mythic" else "No affixes to reroll")
	col.add_child(_btn(rtxt, func(): _do(ForgeLogic.reroll(p, i)), Vector2(290, 44), Color(0.2, 0.4, 0.6), rc >= 0 and ForgeLogic.can_afford(0, rc)))
	var sv: int = ForgeLogic.salvage_value(inst)
	var last: bool = p.weapon_slots[1 - i].is_empty()
	col.add_child(_btn("Salvage -> +%d scrap" % sv if not last else "Salvage (keep 1 weapon)", func(): _do(ForgeLogic.salvage(p, i)), Vector2(290, 44), Color(0.6, 0.35, 0.2), not last))
	return col

func _do(ok: bool) -> void:
	Global.sfx("pickup" if ok else "hit")
	_refresh()
