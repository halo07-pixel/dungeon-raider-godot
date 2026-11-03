extends SceneTree
## Test bot đo độ khó (tools/_hkbot.gd): chạy bot thật bằng tiến trình con cho một quái cũ, một quái mới theo khu và một boss bay; mỗi lần phải in dòng RESULT và thoát sạch.
## Không kiểm số liệu độ khó (bot chỉ để so sánh), chỉ kiểm bot không treo/không lỗi script và `all` liệt kê đủ loại.
var fails: int = 0

func ck(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)

func run_bot(kind: String, extra: Array = []) -> String:
	var out: Array = []
	var rc: int = OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "tools/_hkbot.gd", "--", kind, "1"] + extra, out, true)
	return ("rc=%d\n" % rc) + String(out[0] if out.size() > 0 else "")

func _init() -> void:
	await process_frame
	var bot: Script = load("res://tools/_hkbot.gd")
	ck(bot != null, "bot biên dịch được")
	for k in ["crawler", "bubbler", "wraith"]:
		var o: String = run_bot(k)
		ck(o.contains("RESULT %s:" % k), "bot '%s' in RESULT" % k)
		ck(not o.contains("SCRIPT ERROR"), "bot '%s' không lỗi script" % k)
	var o2: String = run_bot("colossus", ["parry"])   # chế độ đỡ: chạy được, không lỗi script
	ck(o2.contains("RESULT colossus:"), "bot parry in RESULT")
	ck(not o2.contains("SCRIPT ERROR"), "bot parry không lỗi script")
	var src: String = FileAccess.get_file_as_string("res://tools/_hkbot.gd")
	for k in ["sentry", "reviver", "cinder", "bubbler", "colossus", "many_faced"]:
		ck(src.contains('"%s"' % k), "danh sách `all` có '%s'" % k)
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
