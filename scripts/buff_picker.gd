extends CanvasLayer
## Buff Picker: hiện 3 lựa chọn buff ngẫu nhiên sau khi dọn phòng thường/boss (Pick 1 of 3
## kiểu Soul Knight). Tạm dừng game khi đang chọn, tiếp tục ngay sau khi người chơi bấm chọn.

var _title: Label
var _bg: ColorRect
var _cards: Array = [] # Array[Dictionary]: panel/style/tier_label/name_label/desc_label/stack_label/btn

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
	title.text = "CHỌN 1 BUFF"
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
		_cards.append(_make_card(hbox))


func _make_card(parent: Control) -> Dictionary:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(260, 240)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.16, 0.95)
	style.border_width_left = 4; style.border_width_right = 4
	style.border_width_top = 4; style.border_width_bottom = 4
	style.corner_radius_top_left = 10; style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10; style.corner_radius_bottom_right = 10
	p.add_theme_stylebox_override("panel", style)
	parent.add_child(p)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	p.add_child(margin)

	var vbox := VBoxContainer.new()
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

	var stack_label := Label.new()
	stack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack_label.add_theme_font_size_override("font_size", 12)
	stack_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(stack_label)

	var btn := Button.new()
	btn.text = "Chọn"
	btn.custom_minimum_size = Vector2(0, 44)
	vbox.add_child(btn)

	return {
		"panel": p, "style": style, "tier_label": tier_label, "name_label": name_label,
		"desc_label": desc_label, "stack_label": stack_label, "btn": btn,
	}


func _on_buff_choice_requested(choices: Array) -> void:
	if _title:
		_title.text = "CHỌN 1 BUFF (%d/%d)" % [Global.BUFF_PICKS_PER_BOSS - Global.buff_picks_left + 1, Global.BUFF_PICKS_PER_BOSS]
	for i in _cards.size():
		var c: Dictionary = _cards[i]
		var btn: Button = c["btn"]
		for conn in btn.pressed.get_connections():
			btn.pressed.disconnect(conn["callable"])
		if i >= choices.size():
			c["panel"].hide()
			continue
		c["panel"].show()
		var id: String = choices[i]
		var info: Dictionary = Global.buff_pool[id]
		var tier: String = info["tier"]
		var color: Color = Global.BUFF_TIER_COLOR.get(tier, Color.WHITE)

		var style: StyleBoxFlat = c["style"]
		style.border_color = color

		c["tier_label"].text = tier.to_upper()
		c["tier_label"].add_theme_color_override("font_color", color)
		c["name_label"].text = info["name"]
		c["name_label"].add_theme_color_override("font_color", color)
		c["desc_label"].text = info["desc"]
		var cur_stack: int = Global.buff_stack(id)
		c["stack_label"].text = ("Đã có: %d" % cur_stack) if cur_stack > 0 else ""

		btn.pressed.connect(_on_card_chosen.bind(id))

	_bg.show()
	get_tree().paused = true


func _on_card_chosen(id: String) -> void:
	Global.apply_buff(id)
	_bg.hide()
	get_tree().paused = false
	Global.consume_buff_pick() # còn lượt thứ 2 thì hiện tiếp
