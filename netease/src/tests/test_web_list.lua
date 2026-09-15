local List=dofile(ROOT..'/package/web_list.lua')
local b=List.new()
assert(not b.select({index=1,list_revision=0}))
b.begin(3,'每日推荐')
local rows={{id=1,name='first',queue_index=1},{id='98765432109',name='second',queue_index=2},
  {name='下一页',page_offset=20}}
b.finish(rows)
local revision=b.revision
local state={page='songs',view_generation=1}
assert(b.select({index=1,list_revision=revision})==rows[1])
-- Playback and physical page navigation do not invalidate the browser list.
for _,page in ipairs({'player','about','library','player'})do
  state.page=page;state.view_generation=state.view_generation+1
  local snapshot=b.snapshot('98765432109')
  assert(snapshot.revision==revision and snapshot.ready and snapshot.tab==3)
  assert(#snapshot.items==3 and snapshot.items[2].current and not snapshot.items[1].current)
  assert(b.select({index=2,list_revision=revision})==rows[2])
  assert(b.select({index=3,list_revision=revision}).page_offset==20)
end
-- Only new libraries/pages invalidate stale browser buttons.
b.begin(3,'每日推荐');assert(b.loading and not b.ready)
assert(not b.select({index=1,list_revision=revision}))
assert(not b.select({index=1,list_revision=b.revision}))
b.finish({{id=9,name='page two',queue_index=21}})
assert(b.select({index=1,list_revision=b.revision}).queue_index==21)
for _,index in ipairs({0,-1,1.5,2,'1'})do assert(not b.select({index=index,list_revision=b.revision}))end
b.begin(1,'收藏');b.fail()
assert(b.error and not b.loading and not b.ready and #b.snapshot().items==0)
b.begin(2,'最近播放');b.finish({})
assert(b.ready and not b.error and #b.snapshot().items==0)
