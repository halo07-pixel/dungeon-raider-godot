extends RefCounted
## Cốt truyện: toàn bộ chữ nằm ở đây (static, không autoload). Ký ức của một boss = cờ `boss_<id>` đã đặt, nên không thêm dữ liệu save.
## Mạch chung: người chơi là Gatekeeper đã thất bại; mỗi khu là một lần thất bại (Gate = lời thề, Catacomb = bỏ mặc, Vault = ngọn lửa,
## Archive = xoá dấu vết, Grove = lãng quên mọc lên trên những gì bị xoá). Lord là đỉnh của câu chuyện được kể; Many-Faced là cái tên
## Colossus đã xoá khỏi sổ cái, nên là kết thúc thật.
const STATE = preload("res://hk/state.gd")

## Thứ tự = thứ tự hiện ở tab Memories. intro: câu boss nói khi vào trận; memory: ký ức nhận được khi hạ.
const MEMORIES: Array = [
	{"id": "warden", "title": "The Oath", "intro": "None pass.", "memory": "I swore to hold the gate until the last of them was safe."},
	{"id": "hexer", "title": "The Open Door", "intro": "You remember me, don't you?", "memory": "Someone unbarred the gate from within. I still hear the latch."},
	{"id": "wraith", "title": "The First Loss", "intro": "You were not here.", "memory": "She asked me to stay. I stood my post instead."},
	{"id": "brute", "title": "The Left Behind", "intro": "We counted on you.", "memory": "I sealed the lower ranks in. They trusted me to open it again."},
	{"id": "lord", "title": "The Fire", "intro": "I am the last gatekeeper standing. Go back.", "memory": "I burned the vaults to bury what slept there. The city burned with it."},
	{"id": "colossus", "title": "The Ledger", "intro": "Every page, in your hand.", "memory": "I wrote it all down, then wrote my own name out of it."},
]
const BENCH: Array = [   # theo số ký ức đã có (0..6)
	"The stone is cold. Something is missing.",
	"A gate. An oath. You were someone who stayed.",
	"Two doors, one open. Whose hand?",
	"Someone asked you to stay. The echo is faint.",
	"You left them behind. Rest anyway.",
	"Fire, and then silence. You remember the smell.",
	"Every page is read. One name is still blank.",
]
const DEATH: Dictionary = {
	"gate": "The gate remembers who did not hold it.",
	"catacomb": "Those you left behind make room for you.",
	"vault": "Ash settles where you fell. You lit this fire.",
	"archive": "A page turns. Your name is still missing.",
	"grove": "The roots keep what falls. Forgetting grows well here.",
}
## Boss bí mật (không phải ký ức): câu vào trận / câu khi hạ.
const SECRET: Dictionary = {
	"many_faced": {   # intro_grove: câu vào trận khi đã hạ boss Grove
		"title": "The Last Face",
		"intro": "I am the name the ledger lost. I wear every face you buried.",
		"intro_grove": "I am the name the ledger lost. I wear every face you buried, even the one the rot kept.",
		"memory": "Then close the gate, Gatekeeper. This time, stay.",
	},
	"grove": {"title": "The Planting", "intro": "Rest. The rot is patient.", "memory": "Something was planted here to forget. It grew anyway."},   # bonus của Toxic Grove: không tính vào 6 ký ức
}
## Ghi chú trong hốc bí mật (hiện khi mở rương hốc): một dòng theo khu.
const SECRET_NOTE: Dictionary = {
	"gate": "Scratched in the stone: 'I stayed.'",
	"catacomb": "A tally of names, every one crossed out.",
	"vault": "Ash, and a key that opens nothing.",
	"archive": "A page torn out. Only the margin remains.",
	"grove": "Something bloomed here before the rot.",
}
const INTRO_GATEKEEPER: String = "You remember it all. Then hold the gate."   # câu vào trận của Lord khi đã có 5 ký ức kia
const ENDING_NORMAL: Array = ["The Dungeon Lord has fallen", "The vaults fall silent. A name is still missing. Thank you for playing."]
const ENDING_TRUE: Array = ["The gate is closed", "The lost name is written back. Every face you buried is at rest.", "Thank you for playing."]
const ENDING_TRUE_GROVE: String = "The lost name is written back. Every face is at rest, even what grew from the forgetting."   # thay dòng 2 khi đã hạ boss Grove
const ENDING_FULL: Array = ["The Gatekeeper remembers", "You held the gate, and you burned it. Both were you.", "A name is still missing from the ledger. Beyond the throne, a door has opened."]

static func memory(id: String) -> Dictionary:
	for m in MEMORIES:
		if m["id"] == id:
			return m
	return {}

## Chữ của boss (ký ức hoặc boss bí mật); key = "intro" | "memory".
static func line(id: String, key: String) -> String:
	var d: Dictionary = memory(id)
	if d.is_empty():
		d = SECRET.get(id, {})
	if id == "many_faced" and key == "intro" and STATE.flag("boss_grove"):
		return String(d["intro_grove"])
	return String(d.get(key, ""))

static func has_memory(id: String) -> bool:
	return STATE.flag("boss_" + id)

static func count() -> int:
	var n: int = 0
	for m in MEMORIES:
		if has_memory(String(m["id"])):
			n += 1
	return n

static func is_complete() -> bool:
	return count() == MEMORIES.size()

static func bench_line() -> String:
	return String(BENCH[count()])

static func secret_note(area: String) -> String:
	return String(SECRET_NOTE.get(area, SECRET_NOTE["gate"]))

static func death_line(area: String) -> String:
	return String(DEATH.get(area, DEATH["gate"]))

const SEALED: String = "Only one who remembers everything may read the last name."   # banner cửa sov_1 khi chưa đủ ký ức

## "true" | "full" | "normal"
static func ending_kind() -> String:
	if STATE.flag("boss_many_faced"):
		return "true"
	return "full" if is_complete() else "normal"

static func ending_lines() -> Array:
	match ending_kind():
		"true":
			if STATE.flag("boss_grove"):
				var t: Array = ENDING_TRUE.duplicate()
				t[1] = ENDING_TRUE_GROVE
				return t
			return ENDING_TRUE
		"full":
			return ENDING_FULL
	return ENDING_NORMAL
