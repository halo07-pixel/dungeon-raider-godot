# Test headless

    bash tools/tests/run_all.sh        # chạy tất cả
    godot --headless --path . -s tools/tests/<ten>.gd   # chạy một test

- Mọi test dùng `user://test_save.dat`, không ghi đè save thật.
- `take_damage_signature_test.gd`: mọi kiểu gọi `take_damage` trên player/enemy/boss (lỗi `source` từng làm đạn hết gây sát thương).
- `save_safety_test.gd`: lưu/nạp an toàn, tự lưu ván. `heat_test`, `tree_test`, `killer_test`, `adapt_test`, `telemetry_*`: Heat, cây kỹ năng, người gây chết, quái thích nghi, telemetry.
- Hằng số cân bằng (HP boss…) nên đọc từ dữ liệu game trong test, không gõ cứng (council_test từng vỡ oan khi cân bằng đổi).
