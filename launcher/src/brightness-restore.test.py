"""Host-only tests: no firmware build or device access."""
from pathlib import Path
import unittest
from lupa.lua54 import LuaRuntime

SOURCE = (Path(__file__).resolve().parent / "../package/main.lua").read_text(encoding="utf-8")
RESTORE = SOURCE.split("local function restore_saved_brightness()", 1)[1].split("local UI_TEXT", 1)[0]
RESTORE = "local function restore_saved_brightness()" + RESTORE


class BrightnessRestoreTests(unittest.TestCase):
    def run_restore(self, value=42, failures=0, sleeping=False, direct="ok", http_mode="ok"):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().INITIAL = value
        lua.globals().FAILURES = failures
        lua.globals().SLEEPING = sleeping
        lua.globals().DIRECT = direct
        lua.globals().HTTP_MODE = http_mode
        lua.execute("""
            SETTINGS = {brightness=INITIAL}
            DISPLAY_SCHEDULE_SERVICE = {scheduled_sleeping=SLEEPING}
            calls, logs, applied, direct_calls, physical = 0, 0, nil, 0, nil
            print = function(message) logs=logs+1;last_log=message end
            if DIRECT~='missing' then
                sys = {setbrightness=function(value)
                    assert(calls==0, 'direct restore must precede HTTP')
                    direct_calls=direct_calls+1
                    if DIRECT=='throw' then error('display unavailable') end
                    if DIRECT=='reject' then return nil, 'display unavailable' end
                    physical=value
                    return true
                end}
            end
            http = {post=function(url, options, body)
                calls=calls+1
                assert(options.timeout==500 and options.max_redirects==0 and body=='')
                if HTTP_MODE=='offline' then return -1, 'wifi not connected' end
                if HTTP_MODE=='throw' then error('HTTP unavailable') end
                if calls<=FAILURES then return 503 end
                applied=tonumber(url:match('/display/api/settings%?brightness=(%d+)$'))
                assert(applied)
                return 200
            end}
            if HTTP_MODE=='missing' then http=nil end
        """)
        lua.execute(RESTORE + "\nrestore_saved_brightness()")
        return lua.globals()

    def test_syntax_and_startup_order(self):
        LuaRuntime().execute("assert(load(...))", SOURCE)
        call = SOURCE.index("\nrestore_saved_brightness()\n")
        self.assertLess(call, SOURCE.index("\nschedule_autostart()\n"))
        self.assertLess(call, SOURCE.index("\nstart_display_schedule_service()"))

    def test_saved_value_and_clamping(self):
        for value, expected in [(42, 42), (0, 1), (150, 100), (35.8, 35)]:
            state = self.run_restore(value)
            self.assertEqual(state.applied, expected)
            self.assertEqual(state.physical, expected)
            self.assertEqual(state.direct_calls, 1)
            self.assertEqual(state.calls, 1)

    def test_missing_or_invalid_value_does_not_change_display(self):
        for value in [None, "invalid", float("nan")]:
            state = self.run_restore(value)
            self.assertEqual(state.calls, 0)
            self.assertEqual(state.direct_calls, 0)

    def test_bounded_retries(self):
        state = self.run_restore(failures=2)
        self.assertEqual(state.calls, 3)
        self.assertEqual(state.applied, 42)
        state = self.run_restore(failures=10)
        self.assertEqual(state.calls, 3)
        self.assertIsNone(state.applied)
        self.assertEqual(state.physical, 42)
        self.assertEqual(state.logs, 1)
        self.assertIn('brightness restored', state.last_log)

    def test_existing_scheduled_sleep_is_not_woken(self):
        state = self.run_restore(sleeping=True)
        self.assertEqual(state.calls, 0)
        self.assertEqual(state.direct_calls, 0)

    def test_old_firmware_restores_without_wifi_or_http(self):
        for mode in ['offline', 'missing', 'throw']:
            state = self.run_restore(http_mode=mode)
            self.assertEqual(state.physical, 42)
            self.assertEqual(state.direct_calls, 1)
            self.assertIsNone(state.applied)
            self.assertEqual(state.calls, 0 if mode == 'missing' else 3)

    def test_http_fallback_when_direct_api_is_missing_or_fails(self):
        for mode in ['missing', 'reject', 'throw']:
            state = self.run_restore(direct=mode)
            self.assertEqual(state.applied, 42)
            self.assertIsNone(state.physical)
            self.assertEqual(state.logs, 0)

    def test_failure_is_reported_when_neither_api_can_restore(self):
        for mode in ['offline', 'missing']:
            state = self.run_restore(direct='reject', http_mode=mode)
            self.assertIsNone(state.physical)
            self.assertIsNone(state.applied)
            self.assertEqual(state.logs, 1)
            self.assertIn('could not restore saved brightness', state.last_log)


if __name__ == "__main__":
    unittest.main()
