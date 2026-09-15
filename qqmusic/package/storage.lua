-- Credentials are sensitive plaintext on a removable SD card, not a secure vault.
local M={}
function M.new(fs,json)
  local root='/sd/data/qqmusic'
  local S={}
  local function allowed(name)
    if name=='session'or name=='settings'or name=='recent'then return true end
    local offset=type(name)=='string'and name:match('^catalog_top2[67]_(%d+)$')
    return offset and tonumber(offset)<1000 and tonumber(offset)%20==0
  end
  local function read(path)
    local ok,raw=pcall(fs.getcontents,path)
    if not ok or type(raw)~='string' or #raw>65536 then return nil end
    local good,value=pcall(json.decode,raw)
    return good and type(value)=='table' and value or nil
  end
  function S.load(name)
    assert(allowed(name))
    return read(root..'/'..name..'.json') or read(root..'/'..name..'.bak')
  end
  function S.save(name,value)
    assert(allowed(name))
    for _,p in ipairs({'/sd/data',root})do if not fs.exists(p)then fs.mkdir(p)end end
    local target=root..'/'..name..'.json'
    local tmp,backup=target..'.tmp',root..'/'..name..'.bak'
    local raw=json.encode(value)
    if #raw>65536 then return nil,'数据过大' end
    if not fs.putcontents(tmp,raw) or not read(tmp) then return nil,'SD 写入失败' end
    if fs.exists(target) then
      if fs.exists(backup) then
        fs.remove(backup) -- NodeMCU file.remove returns no values on success.
        if fs.exists(backup) then return nil,'SD 备份清理失败' end
      end
      if not fs.rename(target,backup) then return nil,'SD 备份失败' end
    end
    if not fs.rename(tmp,target) then
      if fs.exists(backup) then fs.rename(backup,target) end
      return nil,'SD 提交失败'
    end
    return true
  end
  function S.clear_session()
    -- Only after the user chooses Logout. Never touch settings or history.
    for _,name in ipairs({'session.json.tmp','session.bak','session.json'})do
      local path=root..'/'..name
      if fs.exists(path)then fs.remove(path);if fs.exists(path)then return nil,'无法清除本地登录凭据'end end
    end;return true
  end
  return S
end
return M
