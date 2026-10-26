extends RefCounted
## Sprite dùng lại từ game cũ (bộ DungeonTilesetII của 0x72, CC0 — xem assets/dungeon/CREDITS.md). Chỉ phục vụ vẽ,
## logic/va chạm không phụ thuộc vào đây. Thiếu file thì không vẽ gì (test headless chưa import vẫn chạy).
const DIR: String = "res://assets/dungeon/"
static var _cache: Dictionary = {}
static var _count: Dictionary = {}

static func tex(name: String) -> Texture2D:
	if not _cache.has(name):
		var p: String = DIR + name + ".png"
		_cache[name] = load(p) if ResourceLoader.exists(p) else null
	return _cache[name]

static func frame_count(base: String) -> int:
	if not _count.has(base):
		var n: int = 0
		while tex("%s_f%d" % [base, n]) != null:
			n += 1
		_count[base] = n
	return _count[base]

## Khung hiện tại của hoạt ảnh `base` (base_f0, base_f1, ...) theo đồng hồ; không có khung thì thử ảnh tĩnh.
static func anim(base: String, fps: float = 8.0) -> Texture2D:
	var n: int = frame_count(base)
	if n == 0:
		return tex(base)
	return tex("%s_f%d" % [base, int(Time.get_ticks_msec() / 1000.0 * fps) % n])

## Vẽ `t` với đáy-giữa tại `foot`, phóng `scale` lần (nearest), lật ngang nếu `flip`.
static func draw(ci: CanvasItem, t: Texture2D, foot: Vector2, scale: float, flip: bool = false, mod: Color = Color.WHITE) -> void:
	if t == null:
		return
	var sz: Vector2 = t.get_size() * scale
	var r := Rect2(foot + Vector2(-sz.x * 0.5, -sz.y), sz)
	if flip:
		r = Rect2(r.position + Vector2(sz.x, 0.0), Vector2(-sz.x, sz.y))
	ci.draw_texture_rect(t, r, false, mod)
