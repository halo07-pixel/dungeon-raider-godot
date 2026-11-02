extends StaticBody2D
## Mảnh tường nứt: người chơi chém một nhát là vỡ. Chỉ báo lên bằng signal `broken`; room quyết định phần còn lại (cờ, mở cả cụm).
signal broken
var hp: int = 1   # _on_nail_hit của người chơi đọc hp của mục tiêu (hạ gục = đòn nặng); tường nứt không có máu

func take_hit(_dmg: int, _from: Vector2) -> bool:
	broken.emit()
	return true
