"""Host Lua behavior tests and native-source contracts; no firmware build."""
import struct
import unittest
from pathlib import Path
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / "package/main.lua").read_text(encoding="utf-8")
NATIVE = (ROOT / "src/main/jpg_module.c").read_text(encoding="utf-8")


def section(start, end):
    return SOURCE[SOURCE.index(start):SOURCE.index(end, SOURCE.index(start))]


def chunk(payload, kind=b"00dc"):
    return kind + struct.pack("<I", len(payload)) + payload + b"\0" * (len(payload) % 2)


class PlaybackTests(unittest.TestCase):
    def reader(self, data, limit=None):
        lua = LuaRuntime(unpack_returned_tuples=True, encoding="latin-1")
        lua.globals().DATA = data.decode("latin-1")
        lua.globals().LIMIT = len(data) if limit is None else limit
        lua.execute("""
          requests={}; bytes_read=0
          APP={skip_payload_bytes_saved=0,scan_stack={{pos=0,limit=LIMIT}}}
          APP.fd={pos=0,
            seek=function(self,mode,pos) self.pos=pos; return pos end,
            read=function(self,n)
              requests[#requests+1]=n
              local s=DATA:sub(self.pos+1,self.pos+n)
              self.pos=self.pos+#s; bytes_read=bytes_read+#s; return s
            end}
        """)
        helpers = section("local function u32le", "local function file_size")
        reader = section("local function is_video_chunk", "local function style_panel")
        fn = lua.execute(helpers + reader + " return read_next_jpeg")
        return lua, fn

    def test_syntax(self):
        LuaRuntime().compile(SOURCE)

    def test_skip_reads_only_header_and_soi(self):
        payload = b"\xff\xd8" + b"x" * 10001
        next_frame = b"\xff\xd8next\xff\xd9"
        lua, read = self.reader(chunk(payload) + chunk(next_frame))
        self.assertTrue(read(True))
        self.assertEqual(lua.globals().bytes_read, 10)
        self.assertEqual(lua.globals().APP.skip_payload_bytes_saved, len(payload)-2)
        self.assertEqual(read(False).encode("latin-1"), next_frame)

    def test_nested_list_and_non_video_chunks(self):
        inner = chunk(b"audio", b"01wb") + chunk(b"\xff\xd8frame")
        lua, read = self.reader(chunk(b"rec " + inner, b"LIST"))
        self.assertTrue(read(True))
        self.assertEqual(read(True), (None, "eof"))

    def test_prefixed_jpeg_keeps_legacy_fallback(self):
        payload = b"prefix" + b"\xff\xd8image"
        lua, read = self.reader(chunk(payload))
        self.assertTrue(read(True))
        self.assertEqual(lua.globals().APP.skip_payload_bytes_saved, 0)
        self.assertEqual(lua.globals().bytes_read, 8 + 2 + len(payload))

    def test_invalid_chunk_skipped_like_normal_reader(self):
        lua, read = self.reader(chunk(b"not jpeg") + chunk(b"\xff\xd8valid"))
        self.assertTrue(read(True))
        self.assertEqual(read(True), (None, "eof"))

    def test_bounds_and_truncated_header_rejected(self):
        _, read = self.reader(b"00dc" + struct.pack("<I", 100) + b"xx")
        self.assertEqual(read(True), (None, "AVI chunk is damaged"))
        _, read = self.reader(b"00dc", limit=8)
        self.assertEqual(read(True), (None, "AVI read failed"))

    def test_pause_and_resume_log_source(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute("""
          APP={paused=false,timeline_frame=12}; FRAME_INTERVAL_MS=50
          logs={}; function print(s) logs[#logs+1]=s end
          function now_ms() return 1234 end
          function pause_audio(v) audio_paused=v end
          function show_message() end; function hide_message() end
          APP.files={'demo.avi'}; APP.index=1
        """)
        setter = section("local function set_pause_state", "local function sleep_ms")
        toggle = section("local function toggle_pause", "local function register_keys")
        run = lua.execute(setter + toggle + " return toggle_pause")
        run("key.UP", "START")
        self.assertTrue(lua.globals().APP.paused)
        self.assertTrue(lua.globals().audio_paused)
        self.assertIn("paused=true source=key.UP event=START", lua.globals().logs[1])
        self.assertEqual(lua.globals().APP.pause_changed_ms, 1234)
        run("key.UP", "START")
        self.assertFalse(lua.globals().APP.paused)
        self.assertFalse(lua.globals().audio_paused)
        self.assertEqual(lua.globals().APP.started_ms, 1234 - 600)
        self.assertIn("paused=false source=key.UP event=START", lua.globals().logs[2])

    def test_all_pause_transitions_are_logged(self):
        self.assertEqual(SOURCE.count("APP.paused ="), 2)  # init + central setter

    def test_stack_sizes_and_compatibility_contract(self):
        self.assertIn("stack_bytes = 4608", SOURCE)
        self.assertIn("producer_stack_bytes = 5536", SOURCE)
        self.assertIn("#define JPG_DECODE_TASK_STACK_BYTES 7376u", NATIVE)
        self.assertEqual(NATIVE.count("push_frame_stats(L, inst, brief);"), 3)
        helper = NATIVE[NATIVE.index("static void push_frame_stats"):NATIVE.index("static void jpg_async_decode_task")]
        self.assertIn("if (!brief)", helper)
        self.assertIn("push_stats(L, inst)", helper)  # legacy callers unchanged
        self.assertNotIn("host->heap", helper)
        self.assertNotIn('collectgarbage("collect")', SOURCE)


if __name__ == "__main__":
    unittest.main()
