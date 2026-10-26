#!/usr/bin/env bash
# Chạy mọi test headless trong tools/tests/ rồi validator phòng. Dùng: bash tools/tests/run_all.sh  (từ thư mục gốc dự án)
# Cần lệnh `godot` (4.7) trong PATH. Mỗi test tự dùng file save riêng (user://hk_*_save.json), không đụng save thật.
cd "$(dirname "$0")/../.." || exit 1
fail=0
godot --headless --path . --import >/dev/null 2>&1
for f in tools/tests/*.gd; do
  out=$(timeout 180 godot --headless --path . -s "$f" 2>&1)
  rc=$?
  if [ $rc -ne 0 ] || echo "$out" | grep -aq "SCRIPT ERROR"; then
    echo "FAIL  $f (rc=$rc)"; echo "$out" | grep -a "FAIL\|SCRIPT ERROR" | head -3; fail=1
  else
    echo "ok    $f"
  fi
done
if python3 tools/hk/validate_rooms.py --quick >/dev/null 2>&1; then echo "ok    tools/hk/validate_rooms.py"; else echo "FAIL  tools/hk/validate_rooms.py"; fail=1; fi
exit $fail
