local cjson = require 'cjson'
local function fail(message)
    io.stderr:write('Trojan 配置错误：' .. message .. '\n')
    os.exit(1)
end
local section, mode = arg[1] or '', arg[2] or ''
if not section:match('^%d+$') or #section > 10 then fail('节点编号无效') end
local input = io.popen('dbus get ssconf_basic_json_' .. section)
if not input then fail('无法读取节点') end
local raw = input:read('*all'); input:close()
local ok, server = pcall(cjson.decode, raw)
if not ok or type(server) ~= 'table' then fail('节点不是 JSON 对象') end
local function text(value, fallback)
    if value == nil or value == cjson.null then return fallback end
    if type(value) ~= 'string' and type(value) ~= 'number' then fail('字段类型无效') end
    return tostring(value)
end
local function port(value)
    local n = tonumber(value)
    if not n or n ~= math.floor(n) or n < 1 or n > 65535 then fail('端口无效') end
    return n
end
local address = text(server.server, '')
local password = text(server.password, '')
local sni = text(server.tls_host, '')
if address == '' or address:find('[%z\1-\32]') then fail('服务器地址无效') end
if password == '' then fail('密码不能为空') end
if sni:find('[%z\1-\32]') then fail('TLS 主机名无效') end
local remote_port = port(server.server_port)
-- 旧入口把这两个字段分别用作证书校验和主机名校验，不能静默改变含义。
local verify = text(server.insecure, '') == '0'
local verify_hostname = text(server.tls, '') == '1'
if mode == 'select' then
    local requested = arg[3] or 'auto'
    if requested ~= 'auto' and requested ~= 'legacy' and requested ~= 'xray' then fail('核心选择无效') end
    if requested == 'legacy' then print('legacy')
    elseif verify and verify_hostname then print('xray')
    elseif requested == 'auto' then print('legacy')
    else fail('此节点的旧证书选项不能无损转换到 Xray，请保留兼容核心或修正证书设置') end
    return
end
local local_port = port(arg[3])
if mode == 'nat' or mode == 'client' then
    print(cjson.encode({
        log_level=2, run_type=mode, local_addr='0.0.0.0', local_port=local_port,
        remote_addr=address, remote_port=remote_port, udp_timeout=60, password={password},
        ssl={verify=verify, verify_hostname=verify_hostname, cert='', sni=sni,
             alpn={'h2','http/1.1'}, reuse_session=true, session_ticket=false},
        tcp={no_delay=true, keep_alive=true, reuse_port=true,
             fast_open=text(server.fast_open, '0') == '1', fast_open_qlen=20}
    }))
    return
end
if not verify or not verify_hostname then fail('此节点需要旧核心兼容路径') end
local inbound
if mode == 'xray-socks' then
    inbound={listen='0.0.0.0', port=local_port, protocol='socks', settings={auth='noauth',udp=true}}
elseif mode == 'xray-tcp' or mode == 'xray-udp' then
    local proto = mode == 'xray-tcp' and 'tcp' or 'udp'
    inbound={listen='0.0.0.0', port=local_port, protocol='dokodemo-door',
        settings={network=proto,followRedirect=true},
        streamSettings=proto == 'udp' and {sockopt={tproxy='tproxy'}} or nil}
else fail('运行方式无效') end
print(cjson.encode({
    log={loglevel='warning'}, inbounds={inbound},
    outbounds={{tag='proxy',protocol='trojan',
        settings={servers={{address=address,port=remote_port,password=password}}},
        streamSettings={network='tcp',security='tls',
            tlsSettings={useSystemCA=true,serverName=sni ~= '' and sni or address,alpn={'h2','http/1.1'}},
            sockopt={tcpFastOpen=text(server.fast_open, '0') == '1'}}}}
}))
