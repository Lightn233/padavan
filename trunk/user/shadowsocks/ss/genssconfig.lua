local cjson = require 'cjson'
local function fail(message)
    io.stderr:write('Shadowsocks 配置错误：' .. message .. '\n')
    os.exit(1)
end
local section = arg[1] or ''
if not section:match('^%d+$') or #section > 10 then fail('节点编号无效') end
local input = io.popen('dbus get ssconf_basic_json_' .. section)
if not input then fail('无法读取节点') end
local raw = input:read('*all'); input:close()
local ok, server = pcall(cjson.decode, raw)
if not ok or type(server) ~= 'table' then fail('节点不是 JSON 对象') end
local function port(value)
    local n=tonumber(value)
    if not n or n ~= math.floor(n) or n < 1 or n > 65535 then fail('端口无效') end
    return n
end
if type(server.server) ~= 'string' or server.server == '' or server.server:find('[%z\1-\32]') then fail('服务器地址无效') end
if type(server.password) ~= 'string' or server.password == '' then fail('密码不能为空') end
if type(server.encrypt_method_ss) ~= 'string' or server.encrypt_method_ss == '' then fail('加密方式不能为空') end
local plugin, options = server.plugin, server.plugin_opts
if plugin == cjson.null or plugin == '' or plugin == 'none' then plugin=nil end
if plugin ~= nil and type(plugin) ~= 'string' then fail('插件名称无效') end
if options == cjson.null then options=nil end
if options ~= nil and type(options) ~= 'string' then fail('插件参数无效') end
-- simple-obfs 是旧界面的名称，继续映射到同协议的 obfs-local，不能替换为不同协议。
if plugin == 'simple-obfs' or plugin == 'obfs-local' then
    plugin='obfs-local'
    if (options or ''):find('[%z\r\n]') then fail('混淆参数不能包含换行') end
    local mode=(';' .. (options or '') .. ';'):match(';obfs=([^;]*);')
    if mode ~= 'http' and mode ~= 'tls' then fail('混淆模式只能是 http 或 tls') end
    -- 其余参数原样交给同协议插件，保留 fast-open、IPv6 优先和自定义 HTTP 方法等旧选项。
end
print(cjson.encode({server=server.server,server_port=port(server.server_port),
    local_address='0.0.0.0',local_port=port(arg[2]),password=server.password,
    timeout=60,method=server.encrypt_method_ss,plugin=plugin,plugin_opts=plugin and options or nil,
    reuse_port=true,fast_open=false}))
