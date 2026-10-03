extends Node2D
## Điều phối: tạo tầng, đặt Player, chuyển tầng, Tạm dừng, Save/Load, Game Over & Thưởng Ngọc Tím.

@onready var dungeon: Node2D = $Dungeon
@onready var player: CharacterBody2D = $Player
const NPC_SCENE = preload("res://scenes/npc.tscn")
var current_npc: Node2D = null

var _changing: bool = false
var pause_layer: CanvasLayer
var pause_ui: VBoxContainer
var is_game_over: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS 
	
	# 1. KIỂM TRA VÀ PHỤC HỒI SAVE GAME (OPTION A)
	var is_loading_save = not Global.saved_run.is_empty()
	
	if is_loading_save:
		Global.current_class = Global.saved_run.get("class", Global.current_class)
		var stats = Global.saved_run.get("stats", {})
		Global.run_stats = stats.duplicate()
		Global.floor_num = stats.get("floors", 1)
	else:
		if Global.has_method("reset_run"): Global.reset_run()
		if Global.has_method("reset_run_stats"): Global.reset_run_stats()
		
	Global.portal_entered.connect(_on_portal_entered)
	Global.player_died.connect(_on_player_died)
	
	# 2. XÂY DỰNG HẦM NGỤC & ĐẶT PLAYER
	player.global_position = Vector2(-9999, -9999)
	
	dungeon.generate(Global.floor_num)
	await get_tree().process_frame # Chờ hầm ngục kiến thiết xong
	player.global_position = dungeon.room_center(dungeon.start_cell)
	
	# Nạp lại máu và súng nếu đây là lần Load Game
	if is_loading_save:
		_restore_player_state()
		
	Global.message.emit("Tầng %d" % Global.floor_num, Color.WHITE)
	_spawn_npc_if_needed()

	# 3. KHỞI TẠO UI TẠM DỪNG
	pause_layer = CanvasLayer.new()
	pause_layer.layer = 100
	add_child(pause_layer)
	
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	pause_layer.add_child(bg)
	
	var center = CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	pause_layer.add_child(center)
	
	pause_ui = VBoxContainer.new()
	pause_ui.add_theme_constant_override("separation", 20)
	center.add_child(pause_ui)
	
	pause_layer.hide()


func _restore_player_state() -> void:
	if is_instance_valid(player):
		var w_id = Global.saved_run.get("weapon_id", "pistol")
		var w_rarity = Global.saved_run.get("weapon_rarity", "common")
		if player.has_method("set_weapon_with_rarity"):
			player.set_weapon_with_rarity(w_id, w_rarity)
		player.hp = Global.saved_run.get("hp", player.max_hp)
		
		# KHÔI PHỤC TRẠNG THÁI HỒI SINH
		player.has_revived = Global.saved_run.get("has_revived", false)
		
	# Xóa bản lưu (Permadeath)
	Global.saved_run.clear()
	Global.save_game()


# ==========================================
# CÁC HÀM XỬ LÝ CHUYỂN TẦNG GỐC 
# ==========================================
func _on_portal_entered() -> void:
	if _changing: return
	_changing = true
	_next_floor.call_deferred()

func _next_floor() -> void:
	# === BỔ SUNG LOGIC THƯỞNG NGỌC TÍM (ĐIỀU KIỆN 3) ===
	if Global.floor_num > 0 and Global.floor_num % 5 == 0:
		var gems_earned = int(Global.floor_num / 5)
		Global.purple_gems += gems_earned
		Global.save_game() 
		Global.message.emit("Tuyệt vời! Vượt mốc Tầng %d: +%d Ngọc Tím!" % [Global.floor_num, gems_earned], Color(0.8, 0.3, 0.9))
	# ====================================================

	Global.floor_num += 1
	if Global.get("run_stats") != null:
		Global.run_stats["floors"] = Global.floor_num
		
	# BẢO VỆ TUYỆT ĐỐI: Ném Player ra ngoài vũ trụ để tránh chạm nhầm phòng đang xây
	player.global_position = Vector2(-9999, -9999)
	
	dungeon.generate(Global.floor_num)
	await get_tree().process_frame
	
	# Xây xong xuôi mới đặt vào phòng Start
	player.global_position = dungeon.room_center(dungeon.start_cell)
	_spawn_npc_if_needed()
	
	player.knockback = Vector2.ZERO
	player.heal(int(float(player.max_hp) * 0.3))
	Global.message.emit("Tầng %d" % Global.floor_num, Color.WHITE)
	_changing = false


# ==========================================
# CƠ CHẾ TẠM DỪNG (ESC) VÀ GAME OVER
# ==========================================
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not is_game_over:
		get_tree().paused = !get_tree().paused
		if get_tree().paused:
			_build_pause_menu()
			pause_layer.show()
		else:
			pause_layer.hide()

func _build_pause_menu() -> void:
	for c in pause_ui.get_children(): c.queue_free()
	
	var title = Label.new()
	title.text = "TẠM DỪNG"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	pause_ui.add_child(title)
	
	_add_btn("Tiếp Tục", func():
		get_tree().paused = false
		pause_layer.hide()
	)
	_add_btn("Lưu Tiến Độ & Về Menu", _save_and_quit)

func _add_btn(text: String, action: Callable) -> void:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(300, 50)
	btn.pressed.connect(action)
	pause_ui.add_child(btn)

func _save_and_quit() -> void:
	if is_instance_valid(player) and player.alive:
		Global.saved_run = {
			"class": Global.current_class,
			"hp": player.hp,
			"weapon_id": player.weapon_id,
			"weapon_rarity": player.weapon_rarity,
			"has_revived": player.has_revived, # LƯU TRẠNG THÁI HỒI SINH
			"stats": Global.run_stats.duplicate() if Global.get("run_stats") else {}
		}
		Global.save_game()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_player_died() -> void:
	is_game_over = true
	Global.saved_run.clear() # Xóa file save vì đã chết
	Global.save_game()
	
	get_tree().paused = true
	_build_game_over_menu()
	pause_layer.show()

func _build_game_over_menu() -> void:
	for c in pause_ui.get_children(): c.queue_free()
	
	var title = Label.new()
	title.text = "GAME OVER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	pause_ui.add_child(title)
	
	var f = Global.run_stats.get("floors", Global.floor_num) if Global.get("run_stats") else Global.floor_num
	var k = Global.run_stats.get("kills", 0) if Global.get("run_stats") else 0
	var c_coin = Global.run_stats.get("coins", 0) if Global.get("run_stats") else 0
	
	var info = Label.new()
	info.text = "Tầng vượt qua: %d\nTiêu diệt: %d quái\nThu thập: %d Xu" % [f, k, c_coin]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_ui.add_child(info)
	
	_add_btn("Về Menu Chính", func():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	)
		
func _spawn_npc_if_needed() -> void:
	if is_instance_valid(current_npc):
		current_npc.queue_free()
		
	if Global.floor_num % 2 == 0:
		current_npc = NPC_SCENE.instantiate()
		add_child(current_npc)
		current_npc.global_position = dungeon.room_center(dungeon.start_cell) + Vector2(0, -100)
