-- 仅输出候选 JSON；调用者验证后自行替换，绝不覆盖输入文件。
local cjson = require "cjson"
local function fail(s) io.stderr:write("需手动迁移："..s.."；原文件未修改\n"); os.exit(1) end
local f=io.open(arg[1] or "", "rb"); if not f then fail("无法读取输入") end
local raw=f:read("*a");f:close()
if #raw>4*1024*1024 then fail("配置超过 4 MiB") end
local ok,c=pcall(cjson.decode,raw);if not ok or type(c)~="table" then fail("不是有效 JSON 对象") end
local function arr(v) if v==nil then return {} end; if type(v)~="table" then fail("列表类型错误") end;return v end
local function populated(t) if #t>0 then return t end;return nil end
local function move(t,a,b) if t[a]~=nil then if t[b]~=nil then fail(a.." 与 "..b.." 冲突") end;t[b]=t[a];t[a]=nil end end
local function scan(t)
 if type(t)~="table" then return end
 for k,v in pairs(t) do
  if k=="geoip" or k=="geosite" then fail("GeoIP/Geosite 需要显式提供对应规则集") end
  scan(v)
 end
end
scan(c)
local dns=c.dns
if dns then
 if dns.independent_cache==true then fail("independent_cache 已移除，请确认缓存隔离要求") end
 dns.independent_cache=nil
 for _,s in ipairs(arr(dns.servers)) do
  if not s.type then
   local a=s.address;if type(a)~="string" then fail("DNS 地址缺失") end
   if s.strategy or s.client_subnet then fail("每服务器 strategy/client_subnet 需要按规则确认作用范围") end
   if s.address_strategy and not s.address_resolver then fail("address_strategy 缺少 address_resolver") end
   if s.address_resolver then
    s.domain_resolver={server=s.address_resolver,strategy=s.address_strategy}
    s.address_resolver=nil;s.address_strategy=nil
   end
   if a=="local" then s.type="local"
   elseif a=="fakeip" then
    local fake=dns.fakeip;if not fake or not fake.enabled then fail("fakeip 地址池未启用") end
    s.type="fakeip";s.inet4_range=fake.inet4_range;s.inet6_range=fake.inet6_range
   elseif a:match("^rcode://") then fail("rcode 服务器需要转换成有明确匹配条件的 predefined 规则")
   elseif a:match("^dhcp://") then s.type="dhcp";local i=a:sub(8);if i~="auto" then s.interface=i end
   else
    local scheme,rest=a:match("^(%w+)://(.+)$");scheme=scheme or "udp";rest=rest or a
    if not ({udp=true,tcp=true,tls=true,https=true,quic=true,h3=true})[scheme] then fail("未知 DNS 传输 "..scheme) end
    local authority,path=rest:match("^([^/]+)(/.*)$");authority=authority or rest
    if authority:find("[@%s]") then fail("DNS URL 含有用户信息或空白") end
    local host,port=authority:match("^%[([^%]]+)%]:(%d+)$")
    if not host then host=authority:match("^%[([^%]]+)%]$") end
    if not host then
     local _,colons=authority:gsub(":",":")
     if colons==1 then host,port=authority:match("^([^:]+):(%d+)$") end
     host=host or authority
    end
    s.type=scheme;s.server=host
    if port then port=tonumber(port);if port<1 or port>65535 then fail("DNS 端口无效") end;s.server_port=port end
    if path and scheme~="https" and scheme~="h3" then fail("此 DNS 传输不接受 URL 路径") end
    if path and path~="/dns-query" then s.path=path end
   end
   -- 旧远端 DNS 默认经默认出站；新版默认直连，迁移时保留原来的路径。
   if s.type~="local" and s.type~="fakeip" and s.type~="dhcp" and not s.detour then
    local chosen=nil;local all=arr(c.outbounds);local final=c.route and c.route.final
    if final then for _,o in ipairs(all) do if o.tag==final then chosen=o end end
    else chosen=all[1] end
    if chosen then
     if chosen.type=="direct" then
      for key,_ in pairs(chosen) do if key~="type" and key~="tag" and key~="domain_strategy" and key~="domain_resolver" then fail("默认直连出站带自定义拨号参数，需核对 DNS 路由") end end
     elseif chosen.tag and chosen.type~="block" and chosen.type~="dns" then s.detour=chosen.tag
     else fail("旧 DNS 默认出站无法确定，请明确指定 detour") end
    end
   end
   s.address=nil
  end
 end
 if dns.fakeip then
  if dns.fakeip.enabled then
   local found=false;for _,s in ipairs(arr(dns.servers)) do if s.type=="fakeip" then found=true end end
   if not found then fail("启用的 FakeIP 没有对应服务器") end
  end
  dns.fakeip=nil
 end
 for _,r in ipairs(arr(dns.rules)) do if r.outbound~=nil then fail("DNS outbound 匹配需要指定 domain_resolver，不能猜测") end end
end
local route=c.route or {};local rules=arr(route.rules);local prepend={};local special={};local outgoing={}
if dns and not route.default_domain_resolver and #arr(c.outbounds)>0 then
 if not dns.final or #arr(dns.rules)>0 then fail("出站域名解析需要明确的默认 DNS；复杂 DNS 规则请手动核对") end
 route.default_domain_resolver=dns.final
end
for _,o in ipairs(arr(c.outbounds)) do
 if o.type=="block" or o.type=="dns" then
  if not o.tag then fail("特殊出站缺少 tag") end
  special[o.tag]=o.type=="block" and "reject" or "hijack-dns"
 elseif o.type=="wireguard" then fail("WireGuard 必须确认 endpoint 的地址、对端和 allowed_ips")
 else
  if o.override_address or o.override_port then fail("出站目标覆盖需要按路由引用关系迁移") end
  if o.domain_strategy then
   local resolver=route.default_domain_resolver or (dns and dns.final)
   if not resolver then fail("domain_strategy 缺少明确的 DNS 解析器") end
   if type(resolver)~="string" then fail("复杂默认解析器请手动迁移") end
   if o.domain_resolver then fail("domain_strategy 与 domain_resolver 同时存在") end
   o.domain_resolver={server=resolver,strategy=o.domain_strategy};o.domain_strategy=nil
  end
  outgoing[#outgoing+1]=o
 end
end
for _,o in ipairs(outgoing) do
 for _,tag in ipairs(arr(o.outbounds)) do if special[tag] then fail("选择器引用了已移除的特殊出站") end end
end
local function convert_rules(rs)
 for _,r in ipairs(rs) do
  if r.outbound and special[r.outbound] then
   if r.action and r.action~="route" then fail("特殊出站与现有 action 冲突") end
   r.action=special[r.outbound];r.outbound=nil
  end
  if r.rules then convert_rules(r.rules) end
 end
end
convert_rules(rules)
if route.final and special[route.final] then rules[#rules+1]={action=special[route.final]};route.final=nil end
local tags={};for _,i in ipairs(arr(c.inbounds)) do if i.tag then if tags[i.tag] then fail("入站 tag 重复") end;tags[i.tag]=true end end
for n,i in ipairs(arr(c.inbounds)) do
 if i.sniff or i.domain_strategy then
  if i.sniff_override_destination==false or i.sniff_override_destination==true then fail("sniff_override_destination 需要确认目的地址覆盖语义") end
  if i.sniffing then fail("未知 sniffing 字段") end
  if not i.tag then local tag="migrated-in-"..n;if tags[tag] then fail("生成的入站 tag 冲突") end;i.tag=tag;tags[tag]=true end
  if i.domain_strategy then prepend[#prepend+1]={inbound={i.tag},action="resolve",strategy=i.domain_strategy} end
  if i.sniff then prepend[#prepend+1]={inbound={i.tag},action="sniff",timeout=i.sniff_timeout} end
 end
 i.sniff=nil;i.sniff_timeout=nil;i.domain_strategy=nil;i.sniff_override_destination=nil
 if i.type=="tun" then
  for _,pair in ipairs({{"inet4_address","inet6_address","address"},{"inet4_route_address","inet6_route_address","route_address"},{"inet4_route_exclude_address","inet6_route_exclude_address","route_exclude_address"}}) do
   if i[pair[1]] or i[pair[2]] then
    if i[pair[3]] then fail("新旧 TUN 地址字段同时存在") end
    local a={};for _,key in ipairs({pair[1],pair[2]}) do
     local values=i[key];if type(values)=="string" then values={values} end
     for _,v in ipairs(arr(values)) do a[#a+1]=v end;i[key]=nil
    end
    i[pair[3]]=populated(a)
   end
  end
 end
end
for _,r in ipairs(rules) do prepend[#prepend+1]=r end
route.rules=populated(prepend)
if next(route) then c.route=route end
c.outbounds=populated(outgoing)
if c.experimental then
 local api=c.experimental.clash_api
 if api and (api.cache_file or api.cache_id or api.store_selected or api.store_fakeip) then
  if c.experimental.cache_file then fail("新旧缓存设置同时存在") end
  c.experimental.cache_file={enabled=true,path=api.cache_file,cache_id=api.cache_id,store_fakeip=api.store_fakeip}
  api.cache_file=nil;api.cache_id=nil;api.store_selected=nil;api.store_fakeip=nil
 end
 if c.experimental.cache_file and c.experimental.cache_file.store_rdrc then fail("store_rdrc 已移除，请确认缓存要求") end
end
io.write(cjson.encode(c),"\n")
