local M={}
-- getlocal() already applies the device's TZ/DST rules. Never add an hour again.
function M.clock(clock)
  if not clock or type(clock.getlocal)~='function'then return '--:--',nil end
  local ok,t=pcall(clock.getlocal)
  if not ok or type(t)~='table'or type(t.year)~='number'or t.year<2024 or
     type(t.hour)~='number'or type(t.min)~='number'or
     t.hour<0 or t.hour>23 or t.min<0 or t.min>59 then return '--:--',nil end
  return string.format('%02d:%02d',t.hour,t.min),t.dst==1
end
-- Metrics from bundled font headers: ui13 ascent=13, ui16 ascent=22.
-- Fixed baselines, not equal top coordinates, keep mixed font sizes aligned.
function M.lyric_row(row)
  local baseline=56+(row-1)*30
  return baseline-(row==3 and 22 or 13),31,baseline
end
function M.rate(stats)
  local rate=stats and (stats.output_rate or stats.source_rate)or 0
  return type(rate)=='number'and rate>0 and string.format('%gk',rate/1000)or '--k'
end
function M.lyrics(lines,position,status)
  local current=0
  for i,line in ipairs(type(lines)=='table'and lines or {})do
    if line.at>position then break end
    current=i
  end
  local result={}
  for row=1,5 do
    local index=current+row-3
    result[row]=(lines and lines[index]and lines[index].text)or ''
  end
  if not lines or #lines==0 then result[3]=status=='loading'and '加载中'or '暂无歌词' end
  return result,current
end
function M.cover(S,A)
  if S.page=='player'then
    return M.song_cover(A.song)
  elseif S.page=='songs'or S.page=='playlists'then
    return (S.items[S.cursor]or {}).cover or A.list_cover
  elseif S.page=='library'then return (A.tab_covers or {})[S.tab]end
end
function M.song_cover(song)
  if type(song)~='table'then return nil end
  local album=type(song.al)=='table'and song.al or type(song.album)=='table'and song.album or {}
  local url=album.picUrl or album.coverImgUrl or song.picUrl or song.coverImgUrl
  return type(url)=='string'and url~=''and url or nil
end
return M
