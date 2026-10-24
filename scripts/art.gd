extends RefCounted
## Nạp khung hoạt ảnh pixel-art từ assets/dungeon/<tiền tố>_f0.png, _f1.png... (sinh bởi tools/gen_art_pass.py), có nhớ đệm.
## Thiếu file thì trả mảng rỗng: nơi gọi tự quay về cách vẽ cũ, game không vỡ.

static var _cache: Dictionary = {}

static func frames(prefix: String, count: int) -> Array:
	if _cache.has(prefix):
		return _cache[prefix]
	var out: Array = []
	for i in count:
		var path: String = "res://assets/dungeon/%s_f%d.png" % [prefix, i]
		if ResourceLoader.exists(path):
			out.append(load(path))
	_cache[prefix] = out
	return out

## Khung hiện tại theo thời gian t (giây) và tốc độ fps; null nếu không có khung nào.
static func frame(prefix: String, count: int, t: float, fps: float) -> Texture2D:
	var fr: Array = frames(prefix, count)
	if fr.is_empty():
		return null
	return fr[int(t * fps) % fr.size()]
