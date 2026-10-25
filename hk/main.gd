extends Node2D
## Điểm vào của bản Hollow Knight-style: chuyển thẳng sang world (màn hình tiêu đề sẽ thêm sau).
func _ready() -> void:
	var w := Node2D.new()
	w.set_script(preload("res://hk/world.gd"))
	add_child(w)
