"""Lua mock tests for foreground audio avoidance; no device or firmware writes."""
from pathlib import Path
import unittest
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = (ROOT / "xiaozhi-service/package/runtime.lua").read_text(encoding="utf-8")


class AudioArbitrationTests(unittest.TestCase):
    def harness(self, foreground="mjpeg_player", suspended=False, service=True):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute("""
          cfg={SERVICE_MODE=true}; State={FATAL_ERROR='fatal_error'}
          self={state={state='idle'},audio={last_error='audio: read failed'},
            protocol={close_audio_channel=function() closed=true end},
            ui={show_notification=function() notifications=notifications+1 end}}
          notifications=0; alerts=0; logs={}; foreground='launcher'
          function print(s) logs[#logs+1]=s end
          function alert() alerts=alerts+1 end
          function T(s) return s end
          function set_state(s) self.state.state=s end
          function foreground_app_id() return foreground end
          function read_wake_service_config() return {deny_apps={mp3_player=true}} end
          function suspend_audio_for_app(id) suspended_for=id;self.audio_suspended_by_app=true end
        """)
        lua.globals().foreground = foreground
        lua.globals().cfg.SERVICE_MODE = service
        lua.globals().self.audio_suspended_by_app = suspended
        deny_start = RUNTIME.index("  local function app_denies_service(")
        deny_end = RUNTIME.index("  local function start_wake_service_for_app(", deny_start)
        bind_start = RUNTIME.index("  local function bind_audio()")
        bind_end = RUNTIME.index("  start_activation = function()", bind_start)
        lua.execute(RUNTIME[deny_start:deny_end] + RUNTIME[bind_start:bind_end] + " bind_audio()")
        return lua

    def test_video_preemption_before_lifecycle_event(self):
        lua = self.harness()
        lua.globals().self.audio.on_error("audio: capture read failed")
        self.assertEqual(lua.globals().suspended_for, "mjpeg_player")
        self.assertEqual(lua.globals().self.state.state, "idle")
        self.assertEqual(lua.globals().self.audio.last_error, "")
        self.assertEqual(lua.globals().self.audio.last_failure, "audio: capture read failed")
        self.assertEqual(lua.globals().alerts + lua.globals().notifications, 0)
        self.assertIn("serial only", lua.globals().logs[1])

    def test_late_error_during_suspension_is_recoverable(self):
        lua = self.harness(foreground="launcher", suspended=True)
        lua.globals().self.audio_suspended_app_id = "mjpeg_player"
        lua.globals().self.audio.on_error("audio: worker stopped")
        self.assertEqual(lua.globals().suspended_for, "mjpeg_player")
        self.assertEqual(lua.globals().self.audio.last_error, "")

    def test_real_failure_remains_stopped_without_popup(self):
        lua = self.harness(foreground="launcher")
        lua.globals().self.audio.on_error("audio: codec allocation failed")
        self.assertEqual(lua.globals().self.state.state, "fatal_error")
        self.assertTrue(lua.globals().closed)
        self.assertTrue(lua.globals().self.audio_error_serial_only)
        self.assertEqual(lua.globals().alerts + lua.globals().notifications, 0)

    def test_fatal_state_does_not_open_floating_ui(self):
        lua = LuaRuntime()
        lua.execute("""
          State={FATAL_ERROR='fatal_error',IDLE='idle'}
          self={audio_error_serial_only=true,ui={on_state=function(_,s) shown=s end}}
          new_state=State.FATAL_ERROR
        """)
        start = RUNTIME.index("    if new_state == State.FATAL_ERROR and self.audio_error_serial_only then")
        end = RUNTIME.index("    if new_state == State.LISTENING then", start)
        lua.execute(RUNTIME[start:end])
        self.assertEqual(lua.globals().shown, "idle")
        lua.globals().self.audio_error_serial_only = False
        lua.execute(RUNTIME[start:end])
        self.assertEqual(lua.globals().shown, "fatal_error")

    def test_foreground_runtime_does_not_misclassify_failure(self):
        lua = self.harness(service=False)
        lua.globals().self.audio.on_error("audio: failed")
        self.assertEqual(lua.globals().self.state.state, "fatal_error")
        self.assertIsNone(lua.globals().suspended_for)

    def test_other_notifications_unchanged(self):
        lua = self.harness()
        lua.globals().self.audio.on_error("unrelated error")
        self.assertEqual(lua.globals().notifications, 1)

    def test_syntax_and_defaults(self):
        lua = LuaRuntime()
        for path in ("runtime.lua", "config.lua", "mcp/device.lua"):
            source = (ROOT / "xiaozhi-service/package" / path).read_text(encoding="utf-8")
            lua.compile(source)
            self.assertIn("mjpeg_player = true", source)


if __name__ == "__main__":
    unittest.main()
