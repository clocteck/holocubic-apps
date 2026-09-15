local M={}
function M.validate(base,patch)
  if type(patch)~='table'then return nil,'无效设置'end
  local c={};for k,v in pairs(base)do c[k]=v end
  if patch.play_mode~=nil then
    if patch.play_mode~='sequence'and patch.play_mode~='random'and patch.play_mode~='single'then return nil,'无效播放模式'end
    c.play_mode=patch.play_mode
  end
  local bounds={volume={0,100},hpf_hz={0,300},vbass_mix={0,0.25},vbass_drive={1,4},
    vbass_low_hpf={20,299},vbass_low_lpf={21,300},vbass_out_hpf={50,1199},vbass_out_lpf={51,1200}}
  for k,range in pairs(bounds)do
    if patch[k]~=nil then
      local n=patch[k]
      if type(n)~='number'or n~=n or n<range[1]or n>range[2]then return nil,'参数超出范围: '..k end
      c[k]=n
    end
  end
  for _,k in ipairs({'volume','hpf_hz','vbass_low_hpf','vbass_low_lpf','vbass_out_hpf','vbass_out_lpf'})do c[k]=math.floor(c[k])end
  if patch.vbass~=nil then if type(patch.vbass)~='boolean'then return nil,'低音开关无效'end;c.vbass=patch.vbass end
  if patch.eq_db~=nil then
    if type(patch.eq_db)~='table'or #patch.eq_db~=5 then return nil,'需要五段 EQ'end
    c.eq_db={}
    for i=1,5 do local n=patch.eq_db[i]
      if type(n)~='number'or n~=n or n< -6 or n>6 then return nil,'EQ 范围为 -6 到 +6 dB'end
      c.eq_db[i]=math.floor(n*10+0.5)/10
    end
  end
  if c.vbass_low_hpf>=c.vbass_low_lpf or c.vbass_out_hpf>=c.vbass_out_lpf then return nil,'高通频率必须小于低通频率'end
  return c
end
function M.apply(audio,c)
  local g=c.eq_db
  local ok,e=audio.effects(math.floor(g[1]*10+0.5),math.floor(g[2]*10+0.5),math.floor(g[3]*10+0.5),
    math.floor(g[4]*10+0.5),math.floor(g[5]*10+0.5),c.hpf_hz,c.vbass,
    math.floor(c.vbass_mix*1000+0.5),math.floor(c.vbass_drive*1000+0.5),
    c.vbass_low_hpf,c.vbass_low_lpf,c.vbass_out_hpf,c.vbass_out_lpf)
  if ok then audio.volume(c.volume)end
  return ok,e
end
return M
