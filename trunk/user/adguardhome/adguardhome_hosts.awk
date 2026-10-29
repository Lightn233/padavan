# 生成 LAN 名称映射；短名称在前，完整域名保留为别名。此文件不操作服务。
function hostname(s, labels, n, i) {
    if (s == "" || length(s) > 253 || s ~ /[^A-Za-z0-9_.-]/) return 0
    n = split(s, labels, ".")
    for (i = 1; i <= n; i++)
        if (!length(labels[i]) || length(labels[i]) > 63 || labels[i] ~ /^-/ || labels[i] ~ /-$/) return 0
    return 1
}
function ipv4(s, a, n, i) {
    n = split(s, a, ".")
    if (n != 4) return 0
    for (i = 1; i <= 4; i++) if (a[i] !~ /^[0-9]+$/ || a[i] + 0 > 255) return 0
    return 1
}
function ipv6(s, h, a, b, n, l, r, i, key, part) {
    if (s !~ /:/ || s ~ /[^0-9a-f:]/) return ""
    n = split(s, h, "::")
    l = h[1] == "" ? 0 : split(h[1], a, ":")
    r = n == 2 && h[2] != "" ? split(h[2], b, ":") : 0
    if (n > 2 || (n == 1 && l != 8) || (n == 2 && l + r >= 8)) return ""
    key = ""
    for (i = 1; i <= l; i++) {
        if (a[i] == "" || length(a[i]) > 4) return ""
        part = a[i]; sub(/^0+/, "", part); key = key ":" (part == "" ? "0" : part)
    }
    for (i = 1; i <= 8 - l - r; i++) key = key ":0"
    for (i = 1; i <= r; i++) {
        if (b[i] == "" || length(b[i]) > 4) return ""
        part = b[i]; sub(/^0+/, "", part); key = key ":" (part == "" ? "0" : part)
    }
    return key
}
function hex16(s, i, value) {
    value = 0
    for (i = 1; i <= length(s); i++) value = value * 16 + index("0123456789abcdef", substr(s, i, 1)) - 1
    return value
}
function current_lan6(key, address, prefix, p, i, j, remaining, bits, unit, matches) {
    # 直接运行渲染器的旧数据集可以不启用；正式入口始终要求当前 LAN 前缀。
    if (!enforce_lan6) return 1
    split(substr(key, 2), address, ":")
    for (p in lan6_bits) {
        split(substr(lan6_key[p], 2), prefix, ":")
        remaining = lan6_bits[p]; matches = 1
        for (i = 1; i <= 8 && remaining > 0; i++) {
            bits = remaining > 16 ? 16 : remaining
            unit = 1
            for (j = bits; j < 16; j++) unit *= 2
            if (int(hex16(address[i]) / unit) != int(hex16(prefix[i]) / unit)) { matches = 0; break }
            remaining -= bits
        }
        if (matches) return 1
    }
    return 0
}
function canonical(name) { return index(name, ".") || domain == "" ? name : name "." domain }
function inside_lan(ip, a, b, m, i, unit) {
    if (!ipv4(lan_address) || !ipv4(lan_mask) || ip == lan_address) return 0
    split(ip, a, "."); split(lan_address, b, "."); split(lan_mask, m, ".")
    for (i = 1; i <= 4; i++) {
        if (m[i] !~ /^(0|128|192|224|240|248|252|254|255)$/) return 0
        unit = 256 - m[i]
        if (int(a[i] / unit) != int(b[i] / unit)) return 0
    }
    return 1
}
function valid_mac(mac, octets, i) {
    if (split(mac, octets, ":") != 6) return 0
    for (i = 1; i <= 6; i++) if (octets[i] !~ /^[0-9a-f][0-9a-f]$/) return 0
    return mac != "00:00:00:00:00:00" && mac != "ff:ff:ff:ff:ff:ff"
}
function client_name(name) {
    return hostname(name) && name != "unknown" && name != "localhost" && name != "localhost.localdomain"
}
function claim(mac, name, full) {
    full = tolower(canonical(name))
    if ((full in owner) && owner[full] != mac) collision[full] = 1
    owner[full] = mac
}
function short_name(name, suffix) {
    suffix = "." domain
    if (domain != "" && length(name) > length(suffix) &&
        tolower(substr(name, length(name) - length(suffix) + 1)) == suffix)
        return substr(name, 1, length(name) - length(suffix))
    return name
}
function reserve(family, name, full, short) {
    name = tolower(name); full = canonical(name)
    fixed[family SUBSEP name] = fixed[family SUBSEP full] = 1
    if (length(full) > length(domain) + 1 && substr(full, length(full) - length(domain)) == "." domain) {
        short = substr(full, 1, length(full) - length(domain) - 1)
        if (!index(short, ".")) fixed[family SUBSEP short] = 1
    }
}
function names_for(family, name, full, short, result) {
    full = canonical(name); short = short_name(name); result = ""
    if (!fixed[family SUBSEP tolower(short)]) result = short
    if (short != full && !fixed[family SUBSEP tolower(full)])
        result = sprintf("%s%s%s", result, (result == "" ? "" : " "), full)
    return result
}
function emit(family, ip, name, names, line) {
    names = names_for(family, name)
    if (names == "") return
    line = ip " " names
    if (!system_seen[line]++) print line >> system_out
    if (family == 6 && !hosts_seen[line]++) print line >> hosts_out
}
BEGIN {
    domain = tolower(domain)
    if ((domain != "" && !hostname(domain)) || (clock_mode != "no-rtc" && clock_mode != "epoch")) exit 2
}
mode == "base" || mode == "extra" {
    sub(/[ \t]*#.*/, "")
    ip = tolower($1); family = ipv4(ip) ? 4 : (ipv6(ip) != "" ? 6 : 0)
    if (!family) next
    for (i = 2; i <= NF; i++) if (hostname($i)) {
        name = tolower($i)
        # 同名同类型的系统静态记录优先于额外静态文件；允许另一地址族补齐。
        if (mode == "extra" && !fixed[family SUBSEP name]) {
            line = sprintf("%s %s%s", ip, $i, (tolower($i) == tolower(canonical($i)) ? "" : " " canonical($i)))
            if (!extra_seen[line]++) extra[++extra_count] = line
        }
        reserve(family, name)
    }
    next
}
mode == "lan6" {
    # 输入来自 ip -6 -o addr；ULA 也可用，探测中、冲突和已失效地址不可作为依据。
    if ($0 !~ /scope global/ || $0 ~ /(^|[ \t])(tentative|dadfailed)([ \t]|$)/) next
    if ($0 ~ /valid_lft[ \t]+0(sec)?([ \t]|$)/) next
    for (i = 1; i < NF; i++) if ($i == "inet6") {
        n = split(tolower($(i + 1)), cidr, "/"); key = ipv6(cidr[1])
        if (n != 2 || key == "" || cidr[2] !~ /^[0-9]+$/ || cidr[2] < 1 || cidr[2] > 128) next
        if (key ~ /^:fe[89ab]/ || key ~ /^:ff/ || key == ":0:0:0:0:0:0:0:0" || key == ":0:0:0:0:0:0:0:1") next
        p = key "/" cidr[2]; lan6_key[p] = key; lan6_bits[p] = cidr[2] + 0
        break
    }
    next
}
mode == "leases" {
    if (NF < 4 || $1 !~ /^[0-9]+$/ || !ipv4($3)) next
    if (clock_mode == "epoch" && $1 != 0 && $1 + 0 <= now) next
    # no-RTC 的首列为时长，由 dnsmasq 删除到期租约，绝不与 Unix 时间比较。
    mac = tolower($2); name = tolower($4)
    if (!valid_mac(mac)) next
    # 有效租约的身份始终优先，包括客户端没有提供名称的情况。
    lease_seen[mac] = 1
    if (($3 in ip_owner) && ip_owner[$3] != mac) bad_ip[$3] = 1
    ip_owner[$3] = mac
    if (!client_name(name)) next
    full = canonical(name)
    claim(mac, name)
    if ((mac in mac_name) && canonical(mac_name[mac]) != full) bad_mac[mac] = 1
    owner[full] = ip_owner[$3] = mac; mac_name[mac] = name
    count++; lease_mac[count] = mac; lease_ip[count] = $3; lease_name[count] = $4
    next
}
mode == "cache" {
    # 仅保存 MAC 与名称；时间未同步、过期或未来记录均不用于恢复。
    if (NF != 3 || $1 !~ /^[0-9]+$/ || now < 1704067200 ||
        $1 + 0 > now || now - $1 > 604800 || $1 < 1704067200) next
    mac = tolower($2); name = tolower($3)
    if (!valid_mac(mac) || !client_name(name)) next
    if (mac in remembered) { cache_bad[mac] = 1; next }
    if (++cache_count > 256) next
    remembered[mac] = $3; remembered_at[mac] = $1
    next
}
mode == "neigh4" {
    ip = $1
    if (!ipv4(ip) || !inside_lan(ip) || ip ~ /^(0|127|169\.254|22[4-9]|23[0-9])\./) next
    if ($0 ~ /(^|[ \t])(FAILED|INCOMPLETE)([ \t]|$)/) next
    for (i = 2; i < NF; i++) if ($i == "lladdr") {
        mac = tolower($(i + 1))
        if (!valid_mac(mac)) next
        if ((ip in neighbor4_mac) && neighbor4_mac[ip] != mac) neighbor4_conflict[ip] = 1
        neighbor4_mac[ip] = mac; present[mac] = 1
        break
    }
    next
}
mode == "neigh" {
    ip = tolower($1); key = ipv6(ip)
    if (key == "" || key ~ /^:fe[89ab]/ || key ~ /^:ff/ || key == ":0:0:0:0:0:0:0:0" || key == ":0:0:0:0:0:0:0:1") next
    if ($0 ~ /(^|[ \t])(FAILED|INCOMPLETE)([ \t]|$)/) next
    if (!current_lan6(key)) next
    for (i = 2; i < NF; i++) if ($i == "lladdr") {
        mac = tolower($(i + 1))
        if (!valid_mac(mac)) next
        if ((key in neighbor_mac) && neighbor_mac[key] != mac) neighbor_conflict[key] = 1
        neighbor_ip[key] = ip; neighbor_mac[key] = mac; present[mac] = 1
        break
    }
}
END {
    # 同名不同 MAC 一律按冲突处理，绝不据名称合并设备。
    for (mac in remembered)
        if (!lease_seen[mac] && present[mac] && !cache_bad[mac]) claim(mac, remembered[mac])
    for (i = 1; i <= extra_count; i++) if (!system_seen[extra[i]]++) print extra[i] >> system_out
    for (i = 1; i <= count; i++) {
        mac = lease_mac[i]; name = lease_name[i]
        if (!collision[tolower(canonical(name))] && !bad_mac[mac] && !bad_ip[lease_ip[i]]) {
            accepted[mac] = name
            emit(4, lease_ip[i], name)
        }
    }
    for (mac in remembered) {
        if (!lease_seen[mac] && present[mac] && !cache_bad[mac] &&
            !collision[tolower(canonical(remembered[mac]))]) accepted[mac] = remembered[mac]
    }
    for (ip in neighbor4_mac) {
        mac = neighbor4_mac[ip]
        if (!lease_seen[mac] && (mac in accepted) && !neighbor4_conflict[ip] &&
            !(ip in ip_owner)) emit(4, ip, accepted[mac])
    }
    for (key in neighbor_ip) {
        mac = neighbor_mac[key]
        if ((mac in accepted) && !neighbor_conflict[key]) emit(6, neighbor_ip[key], accepted[mac])
    }
    if (cache_out != "" && now >= 1704067200) {
        for (mac in remembered)
            if (!lease_seen[mac] && !cache_bad[mac])
                print remembered_at[mac], mac, remembered[mac] >> cache_out
        for (mac in accepted)
            if (lease_seen[mac] && !bad_mac[mac])
                printf "%.0f %s %s\n", int(now / 86400) * 86400, mac, accepted[mac] >> cache_out
    }
}
