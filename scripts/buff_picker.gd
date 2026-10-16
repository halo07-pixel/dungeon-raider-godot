extends CanvasLayer
## Buff Picker: hiện 3 lựa chọn buff ngẫu nhiên sau khi dọn phòng thường/boss (Pick 1 of 3
## kiểu Soul Knight). Tạm dừng game khi đang chọn, tiếp tục ngay sau khi người chơi bấm chọn.

var _title: Label
var _bg: ColorRect
var _cards: Array = [] # Array[Dictionary]: panel/style/tier_label/name_label/desc_label/synergy_label/stack_label/id
var _choosing: bool = false # chống bấm đúp: mỗi lượt chỉ nhận 1 lần chọn
const CARD_BG: Color = Color(0.12, 0.12, 0.16, 0.95)
const CARD_BG_HOVER: Color = Color(0.2, 0.2, 0.26, 0.98)
const CARD_BORDER: int = 4
const CARD_BORDER_HOVER: int = 7

func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	Global.buff_choice_requested.connect(_on_buff_choice_requested)
	_build_ui()


func _build_ui() -> void:
	_bg = ColorRect.new()
	_bg.color = Color(0.0, 0.0, 0.0, 0.75)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	_bg.hide()

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	var title := Label.new()
	title.text = "CHOOSE A BUFF"
	_title = title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	vbox.add_child(title)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 24)
	vbox.add_child(hbox)

	for i in 3:
		_cards.append(_make_card(hbox, i))


func _make_card(parent: Control, index: int) -> Dictionary:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.custom_minimum_size = Vector2(260, 240)
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_BG
	_set_border(style, CARD_BORDER)
	style.corner_radius_top_left = 10; style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10; style.corner_radius_bottom_right = 10
	p.add_theme_stylebox_override("panel", style)
	parent.add_child(p)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	p.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var tier_label := Label.new()
	tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tier_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(tier_label)

	var name_label := Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.add_theme_font_size_override("font_size", 19)
	vbox.add_child(name_label)

	var desc_label := Label.new()
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.custom_minimum_size = Vector2(230, 0)
	desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(desc_label)

	var synergy_label := Label.new()
	synergy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	synergy_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	synergy_label.add_theme_font_size_override("font_size", 16)
	synergy_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.2))
	synergy_label.visible = false
	vbox.add_child(synergy_label)

	var stack_label := Label.new()
	stack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack_label.add_theme_font_size_override("font_size", 12)
	stack_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(stack_label)

	# Cả thẻ là vùng bấm: bấm chuột trái vào bất kỳ đâu trên thẻ để chọn; hover sáng viền + nền.
	p.gui_input.connect(_on_card_input.bind(index))
	p.mouse_entered.connect(_on_card_hover.bind(index, true))
	p.mouse_exited.connect(_on_card_hover.bind(index, false))

	return {
		"panel": p, "style": style, "tier_label": tier_label, "name_label": name_label,
		"desc_label": desc_label, "synergy_label": synergy_label, "stack_label": stack_label, "id": "",
	}


func _set_border(style: StyleBoxFlat, w: int) -> void:
	style.border_width_left = w; style.border_width_right = w
	style.border_width_top = w; style.border_width_bottom = w


func _on_card_hover(index: int, hovering: bool) -> void:
	var style: StyleBoxFlat = _cards[index]["style"]
	style.bg_color = CARD_BG_HOVER if hovering else CARD_BG
	_set_border(style, CARD_BORDER_HOVER if hovering else CARD_BORDER)


func _on_card_input(event: InputEvent, index: int) -> void:
	if _choosing or not _bg.visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var id: String = _cards[index]["id"]
		if id != "":
			_on_card_chosen(id)


func _input(event: InputEvent) -> void:
	if _choosing or not _bg.visible:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var idx: int = -1
	match event.keycode:
		KEY_1, KEY_KP_1: idx = 0
		KEY_2, KEY_KP_2: idx = 1
		KEY_3, KEY_KP_3: idx = 2
	if idx < 0 or idx >= _cards.size() or not _cards[idx]["panel"].visible:
		return
	var id: String = _cards[idx]["id"]
	if id != "":
		get_viewport().set_input_as_handled()
		_on_card_chosen(id)


func _on_buff_choice_requested(choices: Array) -> void:
	if _title:
		_title.text = "CHOOSE A BUFF"
		if Global.BUFF_PICKS_PER_BOSS > 1:
			_title.text += " (%d/%d)" % [Global.BUFF_PICKS_PER_BOSS - Global.buff_picks_left + 1, Global.BUFF_PICKS_PER_BOSS]
	for i in _cards.size():
		var c: Dictionary = _cards[i]
		if i >= choices.size():
			c["panel"].hide()
			continue
		c["panel"].show()
		_on_card_hover(i, false)
		var id: String = choices[i]
		c["id"] = id
		var info: Dictionary = Global.buff_pool[id]
		var tier: String = info["tier"]
		var color: Color = Global.BUFF_TIER_COLOR.get(tier, Color.WHITE)

		var style: StyleBoxFlat = c["style"]
		style.border_color = color

		c["tier_label"].text = "[%d]  %s" % [i + 1, tier.to_upper()]
		c["tier_label"].add_theme_color_override("font_color", color)
		c["name_label"].text = info["name"]
		c["name_label"].add_theme_color_override("font_color", color)
		c["desc_label"].text = info["desc"]
		var partners: Array = Global.synergy_owned_partner_names(id)
		var syn: Label = c["synergy_label"]
		syn.visible = not partners.is_empty()
		syn.text = "★" if not partners.is_empty() else ""
		var cur_stack: int = Global.buff_stack(id)
		c["stack_label"].text = ("x%d" % cur_stack) if cur_stack > 0 else ""

	_choosing = false
	_bg.show()
	get_tree().paused = true


func _on_card_chosen(id: String) -> void:
	if _choosing:
		return
	_choosing = true
	Global.apply_buff(id)
	_bg.hide()
	get_tree().paused = false
	Global.consume_buff_pick() # còn lượt thứ 2 thì hiện tiếp
