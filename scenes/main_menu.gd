extends Control
## Main Menu: nền ghép từ tile hầm ngục thật (asset 0x72), sprite nhân vật chạy idle
## đứng cạnh nút bấm, font pixel riêng (Press Start 2P) thay cho font mặc định + emoji.
## Có nút Tiếp Tục khi có file lưu, màn hình chọn lớp nhân vật, cẩm nang tra cứu,
## và cây kỹ năng vĩnh viễn.

const BG_SCALE: float = 2.0 # 32px gốc -> 64px trên màn hình
const SETTINGS_MENU_SCENE = preload("res://scenes/settings_menu.tscn")
const ClassSkillScript = preload("res://scripts/class_skill.gd")

## Ánh xạ lớp nhân vật -> bộ sprite 0x72 dùng làm thân người (khớp với player.gd).
const SPRITE_SET: Dictionary = {
	"ranger": "elf_m",
	"brawler": "knight_m",
	"mage": "wizard_m",
	"rogue": "lizard_m",
	"summoner": "necromancer",
}

var ui_layer: CanvasLayer
var main_node: CenterContainer
var index_node: MarginContainer
var class_node: CenterContainer
var upgrade_node: MarginContainer # Node cho Cây Kỹ Năng
var profile_node: MarginContainer # Trang hồ sơ + tiến hoá class
var profile_box: VBoxContainer

# --- Dữ liệu hệ thống Kỹ năng ---
var upg_data = {
	"hp_boost": {"name": "Iron Physique", "desc": "+10 Max HP per level.", "max": 10},
	"start_coin": {"name": "Starting Capital", "desc": "+10 starting gold per level.", "max": 5},
	"mastery": {"name": "Weapon Mastery", "desc": "+5% base damage per level.", "max": 5},
	"revive": {"name": "Phoenix Rebirth", "desc": "Revive once with 50% HP on death.", "max": 1}
}
const SkillTree = preload("res://scripts/skill_tree.gd")
var tree_ui_elements = {}
var upg_ui_elements = {} # Lưu trữ các nút/chữ để tự động cập nhật
var gem_label: Label

func _ready() -> void:
	for c in get_children():
		c.queue_free()

	ui_layer = CanvasLayer.new()
	add_child(ui_layer)

	_build_background()
	_build_main_menu()
	_build_index_menu()
	_build_class_menu()
	_build_upgrade_menu() # Xây Cây Kỹ Năng
	_build_profile_menu()

	show_main_menu()


func _apply_font(ctrl: Control, size: int) -> void:
	ctrl.add_theme_font_override("font", Global.pixel_font())
	ctrl.add_theme_font_size_override("font_size", size)


func _add_tile(parent: Node2D, filename: String, grid_x: int, grid_y: int) -> void:
	var tex := Global.load_tex("res://assets/dungeon/" + filename)
	if tex == null:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.scale = Vector2(BG_SCALE, BG_SCALE)
	var cell: float = 32.0 * BG_SCALE
	s.position = Vector2(float(grid_x) * cell + cell * 0.5, float(grid_y) * cell + cell * 0.5)
	parent.add_child(s)


# ==========================================
# 0. NỀN GHÉP TỪ TILE HẦM NGỤC THẬT
# ==========================================
func _build_background() -> void:
	var bg_root = Node2D.new()
	ui_layer.add_child(bg_root)

	var cell: float = 32.0 * BG_SCALE
	var cols: int = int(ceil(1280.0 / cell)) + 1
	var rows: int = int(ceil(720.0 / cell)) + 1

	var floor_variants := ["floor_1.png", "floor_1.png", "floor_1.png", "floor_2.png", "floor_3.png", "floor_5.png"]

	# Hàng 0: viền tường trên cùng. Hàng 1: mặt tường. Từ hàng 2 trở đi: sàn.
	for x in cols:
		if x == 0:
			_add_tile(bg_root, "wall_top_left.png", x, 0)
		elif x == cols - 1:
			_add_tile(bg_root, "wall_top_right.png", x, 0)
		else:
			_add_tile(bg_root, "wall_top_mid.png", x, 0)
		_add_tile(bg_root, "wall_mid.png", x, 1)

	for y in range(2, rows):
		for x in cols:
			_add_tile(bg_root, floor_variants[randi() % floor_variants.size()], x, y)

	# Vài cây cột trang trí cho có chiều sâu.
	_add_tile(bg_root, "column.png", 3, 3)
	_add_tile(bg_root, "column.png", cols - 4, 3)

	# Phủ tối để chữ/nút bấm luôn rõ, nhưng vẫn thấy nền hầm ngục phía sau.
	var overlay = ColorRect.new()
	overlay.color = Color(0.05, 0.05, 0.08, 0.6)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(overlay)


## Dựng bộ khung idle animation cho 1 class (dùng chung công thức với player.gd).
func _build_idle_frames(prefix: String) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 6.0)
	frames.set_animation_loop("idle", true)
	for i in 4:
		var path: String = "res://assets/dungeon/%s_idle_anim_f%d.png" % [prefix, i]
		var tex := Global.load_tex(path)
		if tex:
			frames.add_frame("idle", tex)
	return frames


func _make_class_preview(prefix: String, box_size: Vector2, sprite_scale: float) -> Control:
	var box := Control.new()
	box.custom_minimum_size = box_size
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = _build_idle_frames(prefix)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(sprite_scale, sprite_scale)
	sprite.position = box_size * 0.5
	box.add_child(sprite)
	sprite.play("idle")
	return box


# ==========================================
# 1. XÂY DỰNG SẢNH CHÍNH (MAIN MENU)
# ==========================================
func _build_main_menu() -> void:
	main_node = CenterContainer.new()
	main_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(main_node)

	var outer_vbox = VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 30)
	outer_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_node.add_child(outer_vbox)

	var title = Label.new()
	title.text = "DUNGEON RAIDER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(title, 40)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	title.add_theme_color_override("font_shadow_color", Color(0.8, 0.2, 0.1))
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 10)
	outer_vbox.add_child(title)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 50)
	outer_vbox.add_child(hbox)

	var prefix: String = SPRITE_SET.get(Global.current_class, "knight_m")
	hbox.add_child(_make_class_preview(prefix, Vector2(180, 220), 4.5))

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(vbox)

	var has_save = not Global.saved_run.is_empty()

	if has_save:
		vbox.add_child(_create_btn("CONTINUE", _continue_game, Vector2(400, 60), Color(0.3, 0.8, 0.4)))
		vbox.add_child(_create_btn("NEW GAME", show_class_menu, Vector2(400, 60), Color(0.8, 0.3, 0.3)))
	else:
		vbox.add_child(_create_btn("START GAME", show_class_menu, Vector2(400, 60)))

	vbox.add_child(_create_btn("SKILL TREE", show_upgrade_menu, Vector2(400, 60), Color(0.6, 0.2, 0.8)))
	vbox.add_child(_create_btn("PROFILE", show_profile, Vector2(400, 60), Color(0.8, 0.6, 0.2)))
	vbox.add_child(_create_btn("SURVIVAL GUIDE", show_index, Vector2(400, 60)))
	vbox.add_child(_create_btn("SETTINGS", _open_settings, Vector2(400, 60), Color(0.3, 0.5, 0.7)))
	vbox.add_child(_create_btn("QUIT", _quit_game, Vector2(400, 60), Color(0.5, 0.2, 0.2)))

# ==========================================
# 2. XÂY DỰNG MÀN HÌNH CHỌN CLASS
# ==========================================
func _build_class_menu() -> void:
	class_node = CenterContainer.new()
	class_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(class_node)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	class_node.add_child(vbox)

	var title = Label.new()
	title.text = "CHOOSE YOUR CLASS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(title, 22)
	vbox.add_child(title)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	hbox.add_child(_build_class_option("elf_m", _class_card_text("ranger", "HP: 100\nWeapon: Pistol"), func(): _start_new_game("ranger"), Color(0.2, 0.5, 0.8)))
	hbox.add_child(_build_class_option("knight_m", _class_card_text("brawler", "HP: 200\nWeapon: Longsword"), func(): _start_new_game("brawler"), Color(0.8, 0.3, 0.2)))
	hbox.add_child(_build_class_option("wizard_m", _class_card_text("mage", "HP: 80\nWeapon: Arcane Staff"), func(): _start_new_game("mage"), Color(0.6, 0.35, 0.9)))
	hbox.add_child(_build_class_option("lizard_m", _class_card_text("rogue", "HP: 90\nWeapon: Daggers"), func(): _start_new_game("rogue"), Color(0.3, 0.7, 0.3)))
	hbox.add_child(_build_class_option("necromancer", _class_card_text("summoner", "HP: 85\nWeapon: Chakram"), func(): _start_new_game("summoner"), Color(0.75, 0.4, 0.85)))

	_build_heat_panel(vbox)
	var back_btn: Control = _create_btn("BACK", show_main_menu, Vector2(250, 60), Color(0.4, 0.4, 0.4))
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(back_btn)
	class_node.hide()


## --- Chế độ Heat (scripts/heat.gd): chọn điều kiện khó hơn trước khi vào ván, đổi lấy nhiều Ngọc Tím hơn ---
var heat_summary: Label

func _build_heat_panel(parent: Node) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(col)
	var title := Label.new()
	title.text = "HEAT (optional): harder runs, more Purple Gems"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.55, 0.25))
	_apply_font(title, 14)
	col.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 4)
	col.add_child(grid)
	for id in Global.HeatScript.ORDER:
		var m: Dictionary = Global.HeatScript.MODS[id]
		var cell := VBoxContainer.new()
		cell.custom_minimum_size = Vector2(300, 0)
		var cb := CheckButton.new()
		cb.text = "%s  [%d]" % [m["name"], int(m["cost"])]
		cb.button_pressed = Global.heat_selected.has(id)
		cb.tooltip_text = String(m["desc"])
		_apply_font(cb, 12)
		cb.toggled.connect(_on_heat_toggled.bind(id))
		cell.add_child(cb)
		var d := Label.new()
		d.text = String(m["desc"])
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
		_apply_font(d, 10)
		cell.add_child(d)
		grid.add_child(cell)
	heat_summary = Label.new()
	heat_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(heat_summary, 13)
	col.add_child(heat_summary)
	_update_heat_summary()

func _on_heat_toggled(on: bool, id: String) -> void:
	if on:
		Global.heat_selected[id] = true
	else:
		Global.heat_selected.erase(id)
	Global.save_game()
	_update_heat_summary()

func _update_heat_summary() -> void:
	var ids: Array = Global.selected_heat_ids()
	var pts: int = Global.HeatScript.total(ids)
	if pts <= 0:
		heat_summary.text = "Heat 0 - normal run"
		heat_summary.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	else:
		heat_summary.text = "Heat %d: +%d%% Purple Gems" % [pts, int(round((Global.HeatScript.gem_mult(ids) - 1.0) * 100.0))]
		heat_summary.add_theme_color_override("font_color", Color(1.0, 0.6, 0.25))


## Chữ trên thẻ chọn class: tên theo bậc tiến hoá + kỹ năng riêng (nếu đã mở).
func _class_card_text(cid: String, stats: String) -> String:
	var P: Dictionary = Global.profile
	var nm: String = Global.MetaProgress.display_name(P, cid, String(Global.classes[cid]["name"])).to_upper()
	var t: String = "%s\n\n%s" % [nm, stats]
	var sid: String = Global.class_skill_id_for(cid)
	if sid != "":
		t += "\nSkill: %s" % String(ClassSkillScript.SKILLS.get(sid, {}).get("name", sid))
	return t

func _build_class_option(prefix: String, label_text: String, action: Callable, color: Color) -> Control:
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_make_class_preview(prefix, Vector2(140, 150), 3.5))
	col.add_child(_create_btn(label_text, action, Vector2(228, 170), color, 14))
	return col

# ==========================================
# 3. XÂY DỰNG CÂY KỸ NĂNG (UPGRADES)
# ==========================================
func _build_upgrade_menu() -> void:
	upgrade_node = MarginContainer.new()
	upgrade_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	upgrade_node.add_theme_constant_override("margin_left", 200)
	upgrade_node.add_theme_constant_override("margin_right", 200)
	upgrade_node.add_theme_constant_override("margin_top", 80)
	upgrade_node.add_theme_constant_override("margin_bottom", 80)
	ui_layer.add_child(upgrade_node)

	var panel = Panel.new()
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	p_style.border_width_left = 4; p_style.border_width_right = 4
	p_style.border_width_top = 4; p_style.border_width_bottom = 4
	p_style.border_color = Color(0.7, 0.2, 0.9)
	p_style.corner_radius_top_left = 15; p_style.corner_radius_top_right = 15
	p_style.corner_radius_bottom_left = 15; p_style.corner_radius_bottom_right = 15
	panel.add_theme_stylebox_override("panel", p_style)
	upgrade_node.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	upgrade_node.add_child(vbox)

	var header_box = VBoxContainer.new()
	vbox.add_child(header_box)

	var title = Label.new()
	title.text = "SKILL TREE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(title, 24)
	title.add_theme_color_override("font_color", Color(0.8, 0.4, 1.0))
	header_box.add_child(title)

	gem_label = Label.new()
	gem_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(gem_label, 16)
	gem_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	header_box.add_child(gem_label)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	# Danh sách các kỹ năng
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	var list_vbox = VBoxContainer.new()
	list_vbox.add_theme_constant_override("separation", 10)
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_vbox)

	for key in upg_data:
		var row = HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		list_vbox.add_child(row)

		# Thông tin kỹ năng
		var info = Label.new()
		info.custom_minimum_size = Vector2(500, 0)
		_apply_font(info, 12)
		row.add_child(info)

		# Nút Nâng cấp
		var btn = _create_btn("Upgrade", func(): _buy_upgrade(key), Vector2(180, 50), Color(0.2, 0.6, 0.3), 12)
		row.add_child(btn)

		upg_ui_elements[key] = {"info": info, "btn": btn}

	# Cây mở rộng (scripts/skill_tree.gd): hai nhánh, mỗi nút mua một lần, có thể cần nút trước.
	for branch in SkillTree.BRANCH_ORDER:
		var head = Label.new()
		head.text = "— %s —" % SkillTree.BRANCH_TITLE[branch]
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_apply_font(head, 14)
		head.add_theme_color_override("font_color", Color(0.8, 0.6, 1.0))
		list_vbox.add_child(head)
		for id in SkillTree.ids():
			if String(SkillTree.NODES[id]["branch"]) != branch:
				continue
			var trow = HBoxContainer.new()
			trow.alignment = BoxContainer.ALIGNMENT_CENTER
			list_vbox.add_child(trow)
			var tinfo = Label.new()
			tinfo.custom_minimum_size = Vector2(500, 0)
			tinfo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_apply_font(tinfo, 12)
			trow.add_child(tinfo)
			var tbtn = _create_btn("Unlock", func(): _buy_tree_node(id), Vector2(180, 50), Color(0.2, 0.6, 0.3), 12)
			trow.add_child(tbtn)
			tree_ui_elements[id] = {"info": tinfo, "btn": tbtn}

	var center_btn = CenterContainer.new()
	vbox.add_child(center_btn)
	center_btn.add_child(_create_btn("BACK", show_main_menu, Vector2(300, 60), Color(0.5, 0.5, 0.5)))

	upgrade_node.hide()

# ==========================================
# 3b. HỒ SƠ: thống kê vĩnh viễn + tiến hoá class
# ==========================================
func _build_profile_menu() -> void:
	profile_node = MarginContainer.new()
	profile_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		profile_node.add_theme_constant_override("margin_" + side, 200)
	for side in ["top", "bottom"]:
		profile_node.add_theme_constant_override("margin_" + side, 60)
	ui_layer.add_child(profile_node)

	var panel = Panel.new()
	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	st.set_border_width_all(4)
	st.border_color = Color(0.9, 0.7, 0.2)
	st.set_corner_radius_all(15)
	panel.add_theme_stylebox_override("panel", st)
	profile_node.add_child(panel)

	profile_box = VBoxContainer.new()
	profile_box.add_theme_constant_override("separation", 12)
	profile_node.add_child(profile_box)
	profile_node.hide()

func _profile_label(text: String, size: int, color: Color = Color.WHITE) -> Label:
	var l = Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(l, size)
	l.add_theme_color_override("font_color", color)
	return l

func _refresh_profile() -> void:
	for c in profile_box.get_children():
		c.queue_free()
	var P: Dictionary = Global.profile
	profile_box.add_child(_profile_label("PROFILE", 24, Color(1.0, 0.8, 0.3)))
	profile_box.add_child(_profile_label("Runs: %d   Wins: %d   Best floor: %d   Kills: %d   Secrets: %d" % [P["runs"], P["wins"], P["best_floor"], P["kills"], int(P.get("secrets", 0))], 12))
	profile_box.add_child(HSeparator.new())

	for cid in ["ranger", "brawler", "mage", "rogue", "summoner"]:
		var C: Dictionary = Global.MetaProgress.cls(P, cid)
		var base: String = String(Global.classes[cid]["name"])
		var shown: String = Global.MetaProgress.display_name(P, cid, base)
		var lords: int = int(C["bosses"].get("lord", 0))
		var head = "%s   Runs: %d   Best floor: %d   Lords: %d" % [shown.to_upper(), C["runs"], C["best_floor"], lords]
		profile_box.add_child(_profile_label(head, 13, Color(0.9, 0.9, 1.0)))

		var evo: Dictionary = Global.MetaProgress.next_evolution(P, cid)
		var skill_id: String = Global.MetaProgress.active_skill(P, cid)
		if skill_id != "":
			var cur: Dictionary = Global.MetaProgress.current_evolution(P, cid)
			profile_box.add_child(_profile_label("%s: %s" % [cur["skill_name"], cur["desc"]], 11, Color(0.6, 1.0, 0.6)))
			_add_branch_switch(cid)
		else:
			var base_sk: Dictionary = ClassSkillScript.SKILLS.get(Global.class_skill_id_for(cid), {})
			if not base_sk.is_empty():
				profile_box.add_child(_profile_label("%s: %s" % [base_sk["name"], base_sk["desc"]], 11, Color(0.6, 1.0, 0.6)))
		if not evo.is_empty():
			var pr: Array = Global.MetaProgress.progress(P, cid)
			var req: Dictionary = evo["req"]
			var goal: String = ("Defeat Dungeon Lord" if req["type"] == "boss" else "Reach floor %d" % req["value"])
			profile_box.add_child(_profile_label("Next: %s - %s  %d/%d" % [evo["name"], goal, pr[0], pr[1]], 11, Color(1.0, 0.85, 0.5)))
			if Global.MetaProgress.can_evolve(P, cid):
				_add_evolve_choice(cid)
		profile_box.add_child(HSeparator.new())

	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	profile_box.add_child(spacer)
	var back = CenterContainer.new()
	back.add_child(_create_btn("BACK", show_main_menu, Vector2(300, 60), Color(0.5, 0.5, 0.5)))
	profile_box.add_child(back)

## Tiến hoá: chọn 1 trong 2 hướng (A: kỹ năng cũ, B: kỹ năng mới) — xem MetaProgress.EVOLUTION_ALT.
func _add_evolve_choice(cid: String) -> void:
	var P: Dictionary = Global.profile
	var t: int = Global.MetaProgress.tier_of(P, cid) + 1
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	for br in ["a", "b"]:
		var evo: Dictionary = Global.MetaProgress.evolution_at(cid, t, br)
		if evo.is_empty():
			continue
		var branch: String = br
		row.add_child(_create_btn("EVOLVE: %s\n%s" % [String(evo["name"]).to_upper(), String(evo["skill_name"])], func(): _evolve(cid, branch), Vector2(300, 56), Color(0.8, 0.6, 0.1) if br == "a" else Color(0.55, 0.45, 0.9), 12))
	profile_box.add_child(row)

## Đã tiến hoá: hai nút đổi hướng (hướng đang chọn bị làm mờ). Đổi tự do giữa các ván.
func _add_branch_switch(cid: String) -> void:
	var P: Dictionary = Global.profile
	if not Global.MetaProgress.EVOLUTION_ALT.has(cid):
		return
	var t: int = mini(Global.MetaProgress.tier_of(P, cid), Global.MetaProgress.EVOLUTIONS[cid].size())
	var cur_branch: String = Global.MetaProgress.branch_of(P, cid)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	for br in ["a", "b"]:
		var evo: Dictionary = Global.MetaProgress.evolution_at(cid, t, br)
		var branch: String = br
		var btn: Control = _create_btn("%s: %s%s" % [br.to_upper(), String(evo["skill_name"]), "  (active)" if br == cur_branch else ""], func(): _switch_branch(cid, branch), Vector2(250, 36), Color(0.35, 0.35, 0.45) if br == cur_branch else Color(0.55, 0.45, 0.9), 11)
		if br == cur_branch:
			btn.modulate = Color(0.7, 0.7, 0.7)
		row.add_child(btn)
	profile_box.add_child(row)

func _evolve(cid: String, branch: String = "a") -> void:
	if Global.MetaProgress.evolve(Global.profile, cid, branch):
		Global.save_game()
		_refresh_profile()

func _switch_branch(cid: String, branch: String) -> void:
	if Global.MetaProgress.set_branch(Global.profile, cid, branch):
		Global.save_game()
		_refresh_profile()

func _update_upgrade_ui() -> void:
	gem_label.text = "Gems: %d" % Global.purple_gems
	_update_tree_ui()

	for key in upg_data:
		var current_lv = Global.upgrades[key]
		var max_lv = upg_data[key]["max"]
		var cost = current_lv + 1 # Giá = Cấp hiện tại + 1

		upg_ui_elements[key]["info"].text = "%s (Lv %d/%d)\n> %s" % [upg_data[key]["name"], current_lv, max_lv, upg_data[key]["desc"]]

		var btn: Button = upg_ui_elements[key]["btn"]
		if current_lv >= max_lv:
			btn.text = "MAX"
			btn.disabled = true
			btn.modulate = Color(0.5, 0.5, 0.5)
		elif Global.purple_gems < cost:
			btn.text = "%d Gems" % cost
			btn.disabled = true
			btn.modulate = Color(0.5, 0.5, 0.5)
		else:
			btn.text = "%d Gems" % cost
			btn.disabled = false
			btn.modulate = Color.WHITE

func _update_tree_ui() -> void:
	for id in tree_ui_elements:
		var node: Dictionary = SkillTree.NODES[id]
		var req: String = String(node["req"])
		var line: String = "%s\n> %s" % [node["name"], node["desc"]]
		if req != "":
			line += " (needs %s)" % SkillTree.NODES[req]["name"]
		tree_ui_elements[id]["info"].text = line
		var btn: Button = tree_ui_elements[id]["btn"]
		if SkillTree.owned(Global.upgrades, id):
			btn.text = "OWNED"
			btn.disabled = true
			btn.modulate = Color(0.5, 0.5, 0.5)
		elif not SkillTree.can_unlock(Global.upgrades, id):
			btn.text = "LOCKED"
			btn.disabled = true
			btn.modulate = Color(0.5, 0.5, 0.5)
		else:
			btn.text = "%d Gems" % SkillTree.cost(id)
			btn.disabled = Global.purple_gems < SkillTree.cost(id)
			btn.modulate = Color(0.5, 0.5, 0.5) if btn.disabled else Color.WHITE

func _buy_tree_node(id: String) -> void:
	var wallet := {"gems": Global.purple_gems}
	if SkillTree.buy(Global.upgrades, wallet, id):
		Global.purple_gems = int(wallet["gems"])
		Global.save_game()
		_update_upgrade_ui()

func _buy_upgrade(key: String) -> void:
	var cost = Global.upgrades[key] + 1
	if Global.purple_gems >= cost and Global.upgrades[key] < upg_data[key]["max"]:
		Global.purple_gems -= cost
		Global.upgrades[key] += 1
		Global.save_game()
		_update_upgrade_ui()


# ==========================================
# 4. XÂY DỰNG TỪ ĐIỂN TRA CỨU (INDEX)
# ==========================================
const GuideContent = preload("res://scripts/guide_content.gd")
var _guide_text: RichTextLabel
var _guide_scroll: ScrollContainer
var _guide_tab_btns: Dictionary = {}
var _guide_tab: String = "basics"

func _build_index_menu() -> void:
	index_node = MarginContainer.new()
	index_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	index_node.add_theme_constant_override("margin_left", 90)
	index_node.add_theme_constant_override("margin_right", 90)
	index_node.add_theme_constant_override("margin_top", 40)
	index_node.add_theme_constant_override("margin_bottom", 40)
	ui_layer.add_child(index_node)

	var panel = Panel.new()
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	p_style.corner_radius_top_left = 15; p_style.corner_radius_top_right = 15
	p_style.corner_radius_bottom_left = 15; p_style.corner_radius_bottom_right = 15
	p_style.border_width_left = 4; p_style.border_width_right = 4
	p_style.border_width_top = 4; p_style.border_width_bottom = 4
	p_style.border_color = Color(0.3, 0.3, 0.4)
	panel.add_theme_stylebox_override("panel", p_style)
	index_node.add_child(panel)

	var inner = MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 24)
	inner.add_theme_constant_override("margin_right", 24)
	inner.add_theme_constant_override("margin_top", 16)
	inner.add_theme_constant_override("margin_bottom", 16)
	index_node.add_child(inner)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	inner.add_child(vbox)

	var title = Label.new()
	title.text = "SURVIVAL GUIDE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(title, 22)
	title.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	vbox.add_child(title)

	# Hàng tab (tự xuống dòng nếu hẹp)
	var tabs = HFlowContainer.new()
	tabs.alignment = FlowContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("h_separation", 8)
	tabs.add_theme_constant_override("v_separation", 8)
	vbox.add_child(tabs)
	_guide_tab_btns.clear()
	for tab_id in GuideContent.TAB_ORDER:
		var btn := _create_btn(String(GuideContent.TAB_TITLES[tab_id]), _select_guide_tab.bind(tab_id), Vector2(104, 38), Color(0.2, 0.25, 0.35), 10)
		tabs.add_child(btn)
		_guide_tab_btns[tab_id] = btn

	_guide_scroll = ScrollContainer.new()
	_guide_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_guide_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_guide_scroll)

	_guide_text = RichTextLabel.new()
	_guide_text.bbcode_enabled = true
	_guide_text.fit_content = true
	_guide_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_guide_text.add_theme_font_override("normal_font", Global.pixel_font())
	_guide_text.add_theme_font_override("bold_font", Global.pixel_font())
	_guide_text.add_theme_font_size_override("normal_font_size", 13)
	_guide_text.add_theme_font_size_override("bold_font_size", 13)
	_guide_text.add_theme_constant_override("line_separation", 4)
	_guide_scroll.add_child(_guide_text)

	var center_btn = CenterContainer.new()
	vbox.add_child(center_btn)
	center_btn.add_child(_create_btn("BACK", show_main_menu, Vector2(260, 50), Color(0.5, 0.5, 0.5)))

	_select_guide_tab("basics")
	index_node.hide()

func _select_guide_tab(tab_id: String) -> void:
	_guide_tab = tab_id
	_guide_text.text = GuideContent.tab_text(tab_id)
	_guide_scroll.scroll_vertical = 0
	for id in _guide_tab_btns:
		var on: bool = id == tab_id
		var c: Color = Color(0.25, 0.55, 0.85) if on else Color(0.2, 0.25, 0.35)
		var btn: Button = _guide_tab_btns[id]
		for st in ["normal", "hover", "pressed"]:
			var sb: StyleBoxFlat = (btn.get_theme_stylebox(st) as StyleBoxFlat).duplicate()
			sb.bg_color = c.lightened(0.25) if st == "hover" else (c.darkened(0.2) if st == "pressed" else c)
			btn.add_theme_stylebox_override(st, sb)

# ==========================================
# CÔNG CỤ & LOGIC CHUYỂN TRANG
# ==========================================
func _create_btn(text_val: String, action: Callable, custom_min_size: Vector2 = Vector2(400, 65), custom_color: Color = Color(0.2, 0.25, 0.35), font_size: int = 16) -> Button:
	var btn = Button.new()
	btn.text = text_val
	btn.custom_minimum_size = custom_min_size
	_apply_font(btn, font_size)

	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = custom_color
	style_normal.corner_radius_top_left = 12; style_normal.corner_radius_top_right = 12
	style_normal.corner_radius_bottom_left = 12; style_normal.corner_radius_bottom_right = 12
	style_normal.border_width_bottom = 6
	style_normal.border_color = custom_color.darkened(0.5)

	var style_hover = style_normal.duplicate()
	style_hover.bg_color = custom_color.lightened(0.3)

	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = custom_color.darkened(0.2)
	style_pressed.border_width_bottom = 2
	style_pressed.border_width_top = 4

	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	btn.pressed.connect(action)
	return btn

func show_main_menu() -> void:
	profile_node.hide()
	index_node.hide()
	class_node.hide()
	upgrade_node.hide()
	main_node.show()

func show_index() -> void:
	main_node.hide()
	index_node.show()

func show_class_menu() -> void:
	main_node.hide()
	class_node.free() # dựng lại để tên/kỹ năng theo bậc tiến hoá luôn mới
	_build_class_menu()
	class_node.show()

func show_profile() -> void:
	main_node.hide()
	_refresh_profile()
	profile_node.show()

func show_upgrade_menu() -> void:
	main_node.hide()
	_update_upgrade_ui()
	upgrade_node.show()

func _start_new_game(c_id: String) -> void:
	Global.saved_run.clear()
	Global.save_game()
	Global.current_class = c_id
	# (Tiền khởi điểm của Starting Capital được cấp trong main.gd sau reset_run().)
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _continue_game() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _quit_game() -> void:
	get_tree().quit()

func _open_settings() -> void:
	var menu = SETTINGS_MENU_SCENE.instantiate()
	ui_layer.add_child(menu)
	menu.closed.connect(func(): menu.queue_free())
