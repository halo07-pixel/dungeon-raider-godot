#!/usr/bin/env bash
# Chạy mọi test headless trong tools/tests/. Dùng: bash tools/tests/run_all.sh  (từ thư mục gốc dự án)
# Mỗi test tự dùng file save riêng (user://test_save.dat), không đụng save thật. Trả mã lỗi khác 0 nếu có test hỏng.
cd "$(dirname "$0")/../.." || exit 1
fail=0
for f in tools/tests/*.gd; do
  out=$(timeout 180 godot --headless --path . -s "$f" 2>&1)
  rc=$?
  if [ $rc -ne 0 ] || echo "$out" | grep -aq "SCRIPT ERROR"; then
    echo "FAIL  $f (rc=$rc)"; echo "$out" | grep -a "FAIL\|SCRIPT ERROR" | head -3; fail=1
  else
    echo "ok    $f"
  fi
done
exit $fail
