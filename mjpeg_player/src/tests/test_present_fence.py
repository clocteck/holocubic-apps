"""Run with Python + lupa; feed package/main.lua on stdin."""
import sys
from lupa import LuaRuntime

source = sys.stdin.read()
lua = LuaRuntime()
lua.compile(source)
body = source[source.index("local function present_ready()"):
              source.index("local function skip_one_frame()")]
lua.globals().test_image = object()  # Lupa exposes this as Lua userdata.
setup = """
USE_NATIVE_WORKER_TASKS=true; SCREEN_W=320; SCREEN_H=240
calls={}; APP={ui={image=7,root=42},jpg={},errors=0,presented=0}
function now_us() return 10 end
function set_pause_state(paused, source, event)
  APP.paused=paused; APP.pause_source=source; APP.pause_event=event
end
function stop_audio() calls.stopped=true end
function show_message() end
function retain_image() end
function lv_img_set_src() table.insert(calls, 'set') end
function lv_obj_get_width() error('must not query deferred width') end
function lv_obj_get_parent() table.insert(calls, 'fence'); return 42 end
APP.jpg.read_ready_image=function(brief)
  assert(brief == true)
  return test_image,320,240,{image_pool_pending_slot=1}
end
APP.jpg.cancel_image=function() calls.cancel=true end
APP.jpg.commit_image=function(slot, elapsed, brief)
  assert(brief == true)
  table.insert(calls, 'commit'); return true,{}
end
"""
run = lua.execute(body + " return present_ready")
lua.execute(setup)
run()
lua.execute("assert(table.concat(calls, ',') == 'set,fence,commit'); assert(APP.presented==1)")
for query in ("return nil", "return 99", "error('query failed')"):
    lua.execute(setup + " function lv_obj_get_parent() " + query + " end")
    run()
    lua.execute("""
      assert(APP.paused and APP.errors==1 and APP.presented==0)
      assert(not calls.cancel and calls.stopped)
      for _, call in ipairs(calls) do assert(call ~= 'commit') end
    """)
print("PASS: syntax, FIFO fence order, layout-independent query, failure slot protection")
