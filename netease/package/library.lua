-- Normalize account libraries without exposing identifiers in diagnostics.
local M={titles={'收藏','最近播放','每日推荐'}}
local function key(id)
  if type(id)=='string'and id:match('^%d+$')and id:find('[1-9]')then return id end
  if type(id)=='number'and id>0 and id%1==0 and id<=2147483647 then return tostring(id)end
end
function M.likes(doc)
  if type(doc)~='table'or type(doc.ids)~='table'then return nil,'收藏响应格式不兼容'end
  local ids,seen={},{}
  for _,id in ipairs(doc.ids)do
    local k=key(id)
    if k and not seen[k]then ids[#ids+1]=id;seen[k]=true end
  end
  return ids,{}
end
function M.recent(doc)
  local data=type(doc)=='table'and doc.data
  if type(data)~='table'or type(data.list)~='table'then return nil,'最近播放响应格式不兼容'end
  local ids,songs,seen={},{},{}
  for _,entry in ipairs(data.list)do
    local song=type(entry)=='table'and entry.data
    local k=type(song)=='table'and key(song.id)
    if k and not seen[k]then
      ids[#ids+1]=song.id;songs[#songs+1]=song;seen[k]=true
    end
  end
  return ids,songs
end
function M.daily(doc)
  local songs=type(doc)=='table'and ((type(doc.data)=='table'and doc.data.dailySongs)or doc.recommend)
  if type(songs)~='table'then return nil,'每日推荐响应格式不兼容'end
  local list={};for _,song in ipairs(songs)do list[#list+1]={data=song}end
  return M.recent({data={list=list}})
end
return M
