-- Public account fields only; never copy cookies/tokens into UI state.
local M={}
function M.parse(doc)
  if type(doc)~='table'then return nil end
  local p=type(doc.profile)=='table'and doc.profile or {}
  local a=type(doc.account)=='table'and doc.account or {}
  local uid=p.userId or a.id
  if not uid or not tostring(uid):match('^%d+$')or not tostring(uid):find('[1-9]')then return nil end
  local vip=tonumber(p.vipType or a.vipType)
  local status=vip and vip>=0 and vip%1==0 and (vip>0 and 'member'or 'non_member')or 'unknown'
  return {id=tostring(uid),nickname=type(p.nickname)=='string'and p.nickname~=''and p.nickname or '网易云用户',
    membership=status,membership_label=status=='member'and '网易云会员'or status=='non_member'and '非会员'or '会员状态未知'}
end
return M
