local M={modes={sequence=true,random=true,single=true}}
function M.next_index(index,count,mode,automatic,random)
  if count<1 then return 1 end
  if automatic and mode=='single'then return index end
  if mode=='random'and count>1 then return (index-1+(random or math.random)(1,count-1))%count+1 end
  return index%count+1
end
function M.lyrics(raw)
  local lines={};if type(raw)~='string'then return lines end
  for line in raw:gmatch('[^\r\n]+')do
    local text=line:gsub('%[[^%]]*%]',''):gsub('&nbsp;',' '):gsub('&#32;',' ')
    local meaningful=text:gsub('%s',''):gsub('　',''):gsub('\194\160','')
    if meaningful~=''then
      for m,s in line:gmatch('%[(%d+):([%d%.]+)%]')do local seconds=tonumber(s)
        if seconds then lines[#lines+1]={at=tonumber(m)*60+seconds,text=text}end
      end
    end
  end
  table.sort(lines,function(a,b)return a.at<b.at end);return lines
end
return M
