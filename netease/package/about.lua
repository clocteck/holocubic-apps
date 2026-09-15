-- Shared copy for the LVGL about page. Never display Cookie values.
local M={
  title='使用说明',
  badge='非官方客户端',
  github='https://github.com/clocteck',
  github_label='github.com/clocteck',
  shortcuts={
    {'左右','换歌 / 选择'}, {'上下','切换页面'},
    {'Home','确认 / 暂停'}, {'长按 Home','退出应用'},
    {'A / B','确认 / 返回'}, {'Start','播放 / 暂停'},
  },
  usage={
    '左右：切歌 / 选择  上下：切换页面',
    'Home：确认 / 暂停  长按 Home：退出',
    '手柄 A：确认  B：返回  Start：暂停',
  },
  privacy={
    '直连网易云，无第三方中转',
    '登录凭据保存在 SD 卡',
  },
}
function M.account(nickname,logged_in)
  if not logged_in then return '账户 · 未登录','请扫码登录' end
  if type(nickname)~='string' or nickname=='' then nickname='网易云用户' end
  return '账户 · '..nickname,'已登录'
end
return M
