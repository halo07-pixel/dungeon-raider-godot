extends RefCounted
## Sprite dùng lại từ game cũ (bộ DungeonTilesetII của 0x72, CC0 — xem assets/dungeon/CREDITS.md). Chỉ phục vụ vẽ,
## logic/va chạm không phụ thuộc vào đây. Thiếu file thì không vẽ gì (test headless chưa import vẫn chạy).
const BODIES = preload("res://hk/bodies.gd")
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
		r.size.x = -sz.x   # Godot: size.x < 0 = lật ngang, vẫn phủ [position.x, position.x + |size.x|] (không dời vị trí)
	ci.draw_texture_rect(t, r, false, mod)

## Vẽ hoạt ảnh/ảnh `base` sao cho phần NHÌN THẤY (không tính viền trong suốt) nằm giữa `foot.x` và đáy nhìn thấy chạm `foot.y`.
## Kích thước hộp va chạm lấy từ cùng bảng `bodies.gd` nên hình và hộp luôn khớp.
static func draw_body(ci: CanvasItem, base: String, foot: Vector2, scale: float, flip: bool = false, mod: Color = Color.WHITE, fps: float = 8.0) -> void:
	var r: Rect2 = BODIES.rect(base, scale)
	var cx: float = r.get_center().x
	draw(ci, anim(base, fps), foot + Vector2(cx if flip else -cx, -r.end.y), scale, flip, mod)

## Hộp nhìn thấy (toạ độ thế giới) của `base` phóng `scale`, đứng tại chân `foot` — cùng quy ước với draw_body.
static func visible_at(base: String, scale: float, foot: Vector2) -> Rect2:
	var sz: Vector2 = BODIES.rect(base, scale).size
	return Rect2(foot.x - sz.x * 0.5, foot.y - sz.y, sz.x, sz.y)
