local M={}
function M.valid(mode)return mode=='ordered'or mode=='shuffle'or mode=='repeat_one'end
function M.step(mode,index,count,delta,automatic,random)
  if count<1 then return nil end
  if automatic and mode=='repeat_one'then return index end
  if mode=='shuffle'then
    if count==1 then return 1 end
    local next_index=(random or math.random)(count-1)
    return next_index>=index and next_index+1 or next_index
  end
  if automatic and index>=count then return nil end -- Ordered playback stops at the end.
  return (index-1+delta)%count+1
end
return M
