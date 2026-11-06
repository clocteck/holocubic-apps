"""Host-only tests: no firmware build or device access."""
from pathlib import Path
import unittest
from lupa.lua54 import LuaRuntime

SOURCE = (Path(__file__).resolve().parent / "../package/main.lua").read_text(encoding="utf-8")
RESTORE = SOURCE.split("local function restore_saved_brightness()", 1)[1].split("local UI_TEXT", 1)[0]
RESTORE = "local function restore_saved_brightness()" + RESTORE


class BrightnessRestoreTests(unittest.TestCase):
    def run_restore(self, value=42, failures=0, sleeping=False):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().INITIAL = value
        lua.globals().FAILURES = failures
        lua.globals().SLEEPING = sleeping
        lua.execute("""
            SETTINGS = {brightness=INITIAL}
            DISPLAY_SCHEDULE_SERVICE = {scheduled_sleeping=SLEEPING}
            calls, logs, applied = 0, 0, nil
            print = function() logs=logs+1 end
            http = {post=function(url, options, body)
                calls=calls+1
                assert(options.timeout==500 and options.max_redirects==0 and body=='')
                if calls<=FAILURES then return 503 end
                applied=tonumber(url:match('/display/api/settings%?brightness=(%d+)$'))
                assert(applied)
                return 200
            end}
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
            self.assertEqual(state.calls, 1)

    def test_missing_or_invalid_value_does_not_change_display(self):
        for value in [None, "invalid", float("nan")]:
            self.assertEqual(self.run_restore(value).calls, 0)

    def test_bounded_retries(self):
        state = self.run_restore(failures=2)
        self.assertEqual(state.calls, 3)
        self.assertEqual(state.applied, 42)
        state = self.run_restore(failures=10)
        self.assertEqual(state.calls, 3)
        self.assertIsNone(state.applied)
        self.assertEqual(state.logs, 1)

    def test_existing_scheduled_sleep_is_not_woken(self):
        self.assertEqual(self.run_restore(sleeping=True).calls, 0)


if __name__ == "__main__":
    unittest.main()
