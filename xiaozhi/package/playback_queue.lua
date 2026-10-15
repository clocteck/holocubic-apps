-- Bounded, nonblocking Opus jitter buffer. Native DMA backpressure is normal.
local M = {}
function M.new(write, max_frames, max_bytes)
  local q, head, tail, bytes = {}, 1, 1, 0
  local self = {}
  function self:clear() q, head, tail, bytes = {}, 1, 1, 0 end
  function self:count() return tail-head end
  function self:drain()
    for _=1,12 do
      if head==tail then self:clear(); return true end
      local ok, err = write(q[head])
      if not ok then
        if err=="would_block" then return true end
        return false, err
      end
      bytes=bytes-#q[head];q[head]=nil;head=head+1
    end
    return true
  end
  function self:push(packet)
    if type(packet)~="string" or #packet==0 then return false,"invalid Opus packet" end
    if tail-head>=max_frames or bytes+#packet>max_bytes then
      return false,"playback jitter buffer limit exceeded"
    end
    q[tail]=packet;tail=tail+1;bytes=bytes+#packet
    return self:drain()
  end
  return self
end
return M
