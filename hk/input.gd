extends RefCounted
## Phím của bản Hollow Knight-style. Đăng ký bằng code để không đụng InputMap của game cũ.
const KEYS: Dictionary = {
	"hk_left": [KEY_A, KEY_LEFT],
	"hk_right": [KEY_D, KEY_RIGHT],
	"hk_up": [KEY_W, KEY_UP],
	"hk_down": [KEY_S, KEY_DOWN],
	"hk_jump": [KEY_Z, KEY_SPACE],
	"hk_attack": [KEY_X, KEY_J],
	"hk_dash": [KEY_C, KEY_K],
}

static func ensure() -> void:
	for action in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			for k in KEYS[action]:
				var ev := InputEventKey.new()
				ev.physical_keycode = k
				InputMap.action_add_event(action, ev)
