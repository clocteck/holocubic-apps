-- Credentials are sensitive plaintext on a removable SD card, not a secure vault.
local M={}
function M.new(fs,json)
  local root='/sd/data/netease'
  local S={}
  local function read(path)
    local ok,raw=pcall(fs.getcontents,path)
    if not ok or type(raw)~='string' or #raw>65536 then return nil end
    local good,value=pcall(json.decode,raw)
    return good and type(value)=='table' and value or nil
  end
  function S.load(name)
    assert(name=='session' or name=='settings')
    return read(root..'/'..name..'.json') or read(root..'/'..name..'.bak')
  end
  function S.save(name,value)
    assert(name=='session' or name=='settings')
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
    local ok,result=pcall(function()
      for _,name in ipairs({'session.json.tmp','session.bak','session.json'})do
        local path=root..'/'..name
        if fs.exists(path)then fs.remove(path)end
        if fs.exists(path)then return false end
      end
      return true
    end)
    if not ok or not result then return nil,'登录会话清理失败，请重试退出'end
    return true
  end
  return S
end
return M
