local cjson = require "cjson"

local function fail(message)
    io.stderr:write("Xray 配置错误：" .. message .. "\n")
    os.exit(1)
end

local section = arg[1] or ""
if not section:match("^%d+$") or #section > 10 then
    fail("节点编号无效")
end
local proto = arg[2] or "tcp"
if proto ~= "tcp" and proto ~= "udp" then fail("入站类型无效") end
local function port(value, allow_zero)
    local n = tonumber(value)
    if not n or n ~= math.floor(n) or n > 65535 or n < (allow_zero and 0 or 1) then
        fail("端口必须为有效整数")
    end
    return n
end
local local_port = port(arg[3] or "0", true)
local socks_port = port(arg[4] or "0", true)
local input = io.popen("dbus get ssconf_basic_json_" .. section)
if not input then fail("无法读取节点") end
local raw = input:read("*all")
input:close()
local ok, server = pcall(cjson.decode, raw)
if not ok or type(server) ~= "table" then fail("节点不是有效 JSON 对象") end
local function text(value, fallback)
    if value == nil or value == cjson.null then return fallback end
    if type(value) ~= "string" and type(value) ~= "number" then fail("字段类型无效") end
    return tostring(value)
end
local function enabled(value)
    return value == true or value == 1 or value == "1" or value == "true" or value == "on"
end
local function list(value, fallback)
    if value == nil or value == cjson.null or value == "" then return fallback end
    if type(value) == "string" then return {value} end
    if type(value) ~= "table" or #value == 0 then fail("列表字段无效") end
    for _, item in ipairs(value) do if type(item) ~= "string" then fail("列表必须为字符串") end end
    return value
end
local address = text(server.server, "")
if address == "" or address:find("[%z\1-\32]") then fail("服务器地址无效") end
local id = text(server.vmess_id, "")
if id == "" then fail("缺少用户 ID") end
local transport = text(server.transport, "tcp")
local tls = text(server.tls, "0")
local flow = text(server.flow, "0")
-- 已移除的协议不能静默改成另一种；须与服务端一起迁移。
if tls == "2" or flow == "1" or flow == "2" then
    fail("旧 XTLS/direct/splice 已不受支持，请与服务端一起迁移到 TLS + Vision")
end
if transport == "h2" or transport == "quic" then
    fail("旧 HTTP/2 或 QUIC 传输已移除，请先迁移服务端，原节点配置已保留")
end
if not ({tcp=true, ws=true, grpc=true, kcp=true})[transport] then fail("不支持的传输方式") end
if tls ~= "0" and tls ~= "1" then fail("不支持的传输安全类型") end
if flow ~= "0" and flow ~= "" and flow ~= "3" and flow ~= "xtls-rprx-vision" then fail("不支持的流控") end
local vision = flow == "3" or flow == "xtls-rprx-vision"
if vision and (tls ~= "1" or transport ~= "tcp") then fail("Vision 需要 TCP 与 TLS") end
if vision and enabled(server.mux) then fail("Vision 不能同时启用旧 Mux") end
local stream = {network=transport, security=tls == "1" and "tls" or "none"}
if tls == "1" then
    if enabled(server.insecure) then
        fail("新版核心已移除跳过证书验证，请先为服务端配置有效证书，原节点已保留")
    end
    -- 延用路由器的受信 CA；始终验证服务端证书和主机名。
    stream.tlsSettings = {useSystemCA=true, serverName=text(server.tls_host, "")}
end
if transport == "tcp" then
    local guise = text(server.tcp_guise, "none")
    if guise ~= "none" and guise ~= "http" then fail("TCP 伪装类型无效") end
    stream.tcpSettings = {header={type=guise}}
    if guise == "http" then
        stream.tcpSettings.header.request = {path=list(server.http_path, {"/"}), headers={Host=list(server.http_host, {address})}}
    end
elseif transport == "ws" then
    stream.wsSettings = {path=text(server.ws_path, "/"), host=text(server.ws_host, "")}
elseif transport == "grpc" then
    stream.grpcSettings = {serviceName=text(server.grpc_path, "")}
elseif transport == "kcp" then
    stream.kcpSettings = {
        mtu=tonumber(server.mtu), tti=tonumber(server.tti),
        uplinkCapacity=tonumber(server.uplink_capacity), downlinkCapacity=tonumber(server.downlink_capacity),
        congestion=enabled(server.congestion), readBufferSize=tonumber(server.read_buffer_size),
        writeBufferSize=tonumber(server.write_buffer_size), header={type=text(server.kcp_guise, "none")}
    }
end
local inbounds = {}
if local_port ~= 0 then
    inbounds[#inbounds+1] = {
        listen="0.0.0.0", port=local_port, protocol="dokodemo-door", tag="redirect-" .. proto,
        settings={network=proto, followRedirect=true},
        streamSettings=proto == "udp" and {sockopt={tproxy="tproxy"}} or nil,
        sniffing={enabled=true, destOverride={"http", "tls"}}
    }
end
if proto == "tcp" and socks_port ~= 0 then
    inbounds[#inbounds+1] = {listen="0.0.0.0", port=socks_port, protocol="socks", tag="socks", settings={auth="noauth", udp=true}}
end
if #inbounds == 0 then fail("至少需要一个监听端口") end
local user = {id=id, encryption=text(server.security, "none")}
if user.encryption == "" then user.encryption = "none" end
if vision then user.flow = "xtls-rprx-vision" end
-- 使用数组形式；保留 JSON 自身的转义，不再通过 sed 删除反斜线。
local config = {
    log={loglevel="warning"}, inbounds=inbounds,
    outbounds={
        {protocol="vless", tag="proxy", settings={vnext={{address=address, port=port(server.server_port, false), users={user}}}},
         streamSettings=stream, mux={enabled=enabled(server.mux), concurrency=tonumber(server.concurrency) or 8}},
        {protocol="freedom", tag="direct"}
    }
}
print(cjson.encode(config))
