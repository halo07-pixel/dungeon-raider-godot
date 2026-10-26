extends RefCounted
## Đọc các phòng từ hk/rooms/*.txt. Mỗi file: phần đầu là khai báo "khoá: giá trị", dòng '---', rồi lưới ký tự.
##   area: gate|catacomb|vault     name: Tên hiển thị     map: x,y (toạ độ trên bản đồ, đơn vị ô bản đồ)
##   hint: cột hàng chữ   door N: phòng_đích cửa_đích   altar: id=... needs=...   charm: id=...   boss: id=...   gate_flag: cờ
## Ký tự lưới: # tường  = bục một chiều  ^ gai  1-9 cửa  @ điểm xuất phát  B bench  M thương nhân  $ rương geo
##   A bàn thờ kỹ năng  C bùa  X boss  G cổng mở khi có cờ  c f s h = quái bò/bay/bắn/húc
const DIR: String = "res://hk/rooms"
const MAP_CELL_TILES: float = 8.0   # 1 ô bản đồ = 8x8 ô lưới

static func parse_room(text: String) -> Dictionary:
	var out: Dictionary = {"area": "gate", "name": "", "map": Vector2(0, 0), "doors": {}, "grid": [], "hints": []}
	var in_grid: bool = false
	for raw in text.split("\n"):
		var line: String = raw.trim_suffix("\r")
		if in_grid:
			if line.strip_edges() == "" and out["grid"].is_empty():
				continue
			out["grid"].append(line)
			continue
		if line.strip_edges() == "---":
			in_grid = true
			continue
		if line.strip_edges() == "" or line.begins_with("#"):
			continue
		var idx: int = line.find(":")
		if idx < 0:
			continue
		var key: String = line.substr(0, idx).strip_edges()
		var val: String = line.substr(idx + 1).strip_edges()
		if key.begins_with("door "):
			var p: PackedStringArray = val.split(" ", false)
			if p.size() == 2:
				out["doors"][key.substr(5).strip_edges()] = {"to": p[0], "door": p[1]}
		elif key == "hint":   # hint: cột hàng nội dung — chữ gợi ý vẽ trong phòng
			var hp: PackedStringArray = val.split(" ", false, 2)
			if hp.size() == 3:
				out["hints"].append({"col": int(hp[0]), "row": int(hp[1]), "text": hp[2]})
		elif key == "map":
			var xy: PackedStringArray = val.split(",")
			out["map"] = Vector2(float(xy[0]), float(xy[1]))
		elif key in ["altar", "charm", "boss"]:
			var d: Dictionary = {}
			for kv in val.split(" ", false):
				var pr: PackedStringArray = kv.split("=")
				d[pr[0]] = pr[1] if pr.size() > 1 else ""
			out[key] = d
		else:
			out[key] = val
	while not out["grid"].is_empty() and String(out["grid"][-1]).strip_edges() == "":
		out["grid"].pop_back()
	return out

static func load_all() -> Dictionary:
	var rooms: Dictionary = {}
	var d := DirAccess.open(DIR)
	if d == null:
		return rooms
	for f in d.get_files():
		if f.ends_with(".txt"):
			rooms[f.get_basename()] = parse_room(FileAccess.get_file_as_string(DIR + "/" + f))
	return rooms

static func map_size(room: Dictionary) -> Vector2:
	var cols: int = 0
	for l in room["grid"]:
		cols = maxi(cols, String(l).length())
	return Vector2(float(cols) / MAP_CELL_TILES, float(room["grid"].size()) / MAP_CELL_TILES)
