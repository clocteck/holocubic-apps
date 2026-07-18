local M = {}

function M.new()
  local self = {}

  function self:setup() end
  function self:stop() end
  function self:set_view_mode() end
  function self:set_metrics() end
  function self:update_status_bar() end
  function self:set_status() end
  function self:show_notification() end
  function self:set_emotion() end
  function self:set_chat_message() end
  function self:clear_chat_messages() end
  function self:on_state() end
  function self:alert() end
  function self:diagnostics()
    return { mode = "headless" }
  end

  return self
end

return M
