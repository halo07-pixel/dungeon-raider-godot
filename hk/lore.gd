extends RefCounted
## Cốt truyện: toàn bộ chữ nằm ở đây (static, không autoload). Ký ức của một boss = cờ `boss_<id>` đã đặt, nên không thêm dữ liệu save.
const STATE = preload("res://hk/state.gd")

## Thứ tự = thứ tự hiện ở tab Memories. intro: câu boss nói khi vào trận; memory: ký ức nhận được khi hạ.
const MEMORIES: Array = [
	{"id": "warden", "title": "The Oath", "intro": "None pass.", "memory": "I swore to hold the gate until the last of them was safe."},
	{"id": "hexer", "title": "The Open Door", "intro": "You remember me, don't you?", "memory": "Someone unbarred the gate from within. I still hear the latch."},
	{"id": "wraith", "title": "The First Loss", "intro": "You were not here.", "memory": "She asked me to stay. I stood my post instead."},
	{"id": "brute", "title": "The Left Behind", "intro": "We counted on you.", "memory": "I sealed the lower ranks in. They trusted me to open it again."},
	{"id": "lord", "title": "The Fire", "intro": "I am the last gatekeeper. Go back.", "memory": "I burned the vaults to bury what slept there. The city burned with it."},
	{"id": "colossus", "title": "The Ledger", "intro": "Every page, in your hand.", "memory": "I wrote it all down, then wrote my own name out of it."},
]
const BENCH: Array = [   # theo số ký ức đã có (0..6)
	"The stone is cold. Something is missing.",
	"A gate. An oath. You were someone who stayed.",
	"Two doors, one open. Whose hand?",
	"Someone asked you to stay. The echo is faint.",
	"You left them behind. Rest anyway.",
	"Fire, and then silence. You remember the smell.",
	"The ledger is whole. Nothing is left to remember.",
]
const DEATH: Dictionary = {
	"gate": "The gate remembers who did not hold it.",
	"catacomb": "The dead make room for you.",
	"vault": "Ash settles where you fell.",
	"archive": "A page turns. Your name is still missing.",
}
const ENDING_NORMAL: Array = ["The Dungeon Lord has fallen", "The vaults fall silent. Thank you for playing."]
const ENDING_FULL: Array = ["The Gatekeeper remembers", "You held the gate, and you burned it. Both were you."]

static func memory(id: String) -> Dictionary:
	for m in MEMORIES:
		if m["id"] == id:
			return m
	return {}

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

static func death_line(area: String) -> String:
	return String(DEATH.get(area, DEATH["gate"]))

static func ending_lines() -> Array:
	return ENDING_FULL if is_complete() else ENDING_NORMAL
