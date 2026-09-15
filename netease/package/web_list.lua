-- The browser's library survives device page changes and playback revisions.
local M={}
function M.new()
  local B={revision=0,tab=1,title='',items={},ready=false,loading=false,error=false}
  function B.begin(tab,title)
    B.revision=B.revision+1;B.tab=tab;B.title=title or ''
    B.items={};B.ready=false;B.loading=true;B.error=false
  end
  function B.finish(items)B.items=items;B.ready=true;B.loading=false;B.error=false end
  function B.fail()B.ready=false;B.loading=false;B.error=true end
  function B.clear()B.begin(1,'收藏');B.loading=false end
  function B.select(doc)
    if doc.list_revision~=B.revision then return nil,'列表已变化，请重新选择'end
    if not B.ready then return nil,'请先选择音乐库'end
    if type(doc.index)~='number'or doc.index%1~=0 or not B.items[doc.index]then return nil,'无效项目'end
    return B.items[doc.index]
  end
  function B.snapshot(song_id)
    local rows={}
    for i,item in ipairs(B.items)do
      if i>22 then break end
      rows[#rows+1]={index=i,name=item.name or '',page=item.page_offset~=nil or item.playlist_offset~=nil,
        current=item.id~=nil and tostring(item.id)==tostring(song_id)}
    end
    return {title=B.title,tab=B.tab,items=rows,ready=B.ready,loading=B.loading,error=B.error,revision=B.revision}
  end
  return B
end
return M
