local M = {}
M.models = {
  nihaoxiaozhi = { model = "wn9s_nihaoxiaozhi", text = "你好小智" },
  hi_esp = { model = "wn9s_hiesp", text = "Hi ESP" },
}
function M.apply(cfg)
  local Store = dofile(cfg.APP_DIR .. "/store.lua")
  local doc = Store.ensure()
  local id = type(doc.wake) == "table" and doc.wake.id or "nihaoxiaozhi"
  local model = M.models[id] or M.models.nihaoxiaozhi
  cfg.WAKE_ID, cfg.WAKE_WORD, cfg.WAKE_MODEL = id, model.text, model.model
  cfg.WAKE_ROOT = cfg.APP_DIR .. "/wake"
  cfg.WAKE_MODEL_DIR = cfg.WAKE_ROOT .. "/" .. model.model
  cfg.WAKE_INDEX, cfg.WAKE_DATA = cfg.WAKE_MODEL_DIR .. "/wn9_index", cfg.WAKE_MODEL_DIR .. "/wn9_data"
  cfg.LANGUAGE = doc.language or "auto"
  -- One-time cleanup of obsolete audio options; preserve identity and credentials.
  local a=doc.audio
  if a and (a.duplex~=nil or a.aec_delay_ms~=nil or a.aec_nlp_level~=nil) then
    local ok,err=Store.update(function(saved)
      saved.audio.duplex=nil;saved.audio.aec_delay_ms=nil;saved.audio.aec_nlp_level=nil
    end)
    if not ok then error(err) end
  end
  return cfg
end
return M
