extends CanvasLayer
## Menu Cài đặt: âm lượng Master/SFX, Fullscreen, đổi phím di chuyển/né. Được tạo linh
## hoạt (instantiate) từ cả Main Menu lẫn menu Tạm dừng trong game — không phải node cố
## định sẵn trong scene nào, nơi gọi tự add_child() rồi nghe signal "closed" để tự huỷ.

signal closed

const ACTION_LABELS: Dictionary = {
	"move_up": "Move Up",
	"move_down": "Move Down",
	"move_left": "Move Left",
	"move_right": "Move Right",
	"dodge": "Dodge",
}

var _awaiting_action: String = ""
var _keybind_buttons: Dictionary = {} # action -> Button


func _ready() -> void:
	layer = 150
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(center)

	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(480, 580)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.97)
	style.border_width_left = 4; style.border_width_right = 4
	style.border_width_top = 4; style.border_width_bottom = 4
	style.border_color = Color(0.4, 0.5, 0.7)
	style.corner_radius_top_left = 14; style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14; style.corner_radius_bottom_right = 14
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	vbox.add_child(_build_slider_row("Master Volume", float(Global.settings.get("master_volume", 1.0)), Global.set_master_volume))
	vbox.add_child(_build_slider_row("SFX Volume", float(Global.settings.get("sfx_volume", 1.0)), Global.set_sfx_volume))
	vbox.add_child(_build_slider_row("Music Volume", float(Global.settings.get("music_volume", 1.0)), MusicManager.set_music_volume))

	var fs_row := HBoxContainer.new()
	var fs_label := Label.new()
	fs_label.text = "Fullscreen"
	fs_label.custom_minimum_size = Vector2(180, 0)
	fs_row.add_child(fs_label)
	var fs_check := CheckButton.new()
	fs_check.button_pressed = bool(Global.settings.get("fullscreen", false))
	fs_check.toggled.connect(func(on: bool): Global.set_fullscreen(on))
	fs_row.add_child(fs_check)
	vbox.add_child(fs_row)

	vbox.add_child(HSeparator.new())

	var keys_title := Label.new()
	keys_title.text = "Controls"
	keys_title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(keys_title)

	for action in Global.REBINDABLE_ACTIONS:
		vbox.add_child(_build_keybind_row(action))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var back_btn := Button.new()
	back_btn.text = "BACK"
	back_btn.custom_minimum_size = Vector2(0, 50)
	back_btn.pressed.connect(func(): closed.emit())
	vbox.add_child(back_btn)


func _build_slider_row(label_text: String, initial: float, setter: Callable) -> Control:
	var row := VBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = initial * 100.0
	slider.value_changed.connect(func(v: float): setter.call(v / 100.0))
	row.add_child(slider)
	return row


func _build_keybind_row(action: String) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = ACTION_LABELS.get(action, action)
	label.custom_minimum_size = Vector2(220, 0)
	row.add_child(label)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(140, 36)
	btn.text = Global.key_name_for_action(action)
	btn.pressed.connect(_on_rebind_pressed.bind(action, btn))
	row.add_child(btn)
	_keybind_buttons[action] = btn
	return row


func _on_rebind_pressed(action: String, btn: Button) -> void:
	_awaiting_action = action
	btn.text = "Press a key..."


func _input(event: InputEvent) -> void:
	if _awaiting_action == "":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		Global.rebind_action(_awaiting_action, event.physical_keycode)
		var btn: Button = _keybind_buttons.get(_awaiting_action)
		if is_instance_valid(btn):
			btn.text = Global.key_name_for_action(_awaiting_action)
		_awaiting_action = ""
		get_viewport().set_input_as_handled()
