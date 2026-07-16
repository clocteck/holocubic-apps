return {
  tool = {
    name = "test.ping",
    description = "测试 MCP 插件自动扫描是否生效，调用后返回 pong。",
    inputSchema = {
      type = "object",
      properties = {
        message = {
          type = "string",
          description = "可选测试文本，会原样返回。",
        },
      },
      additionalProperties = false,
    },
  },
  call = function(arguments, ctx)
    arguments = type(arguments) == "table" and arguments or {}
    return ctx.text_result({
      ok = true,
      pong = true,
      message = tostring(arguments.message or ""),
      source = "test.lua",
    })
  end,
}
