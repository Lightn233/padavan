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

# 快照只追踪曾经发布的动态地址；静态记录优先，当前前缀恢复即取消淘汰。
function packed(key, a, i, out) {
    split(substr(key, 2), a, ":"); out=""
    for(i=1;i<=8;i++) out=out sprintf("%04x",hex16(a[i]))
    return out
}
function unpacked(s, i, out) {
    if(length(s)!=32 || s~/[^0-9a-f]/) return ""
    out=""; for(i=1;i<=32;i+=4) out=out ":" substr(s,i,4)
    return ipv6(substr(out,2))
}
function eligible(s) {return s~/^(2|3|fc|fd)/}
mode=="tracked" {
    if (NF!=2 || ($1!="live" && $1!="expired" && $1!="protected")) next
    key=unpacked($2); if(key!="" && eligible($2)) tracked[key]=1
    next
}
mode=="static" || mode=="current" {
    sub(/[ \t]*#.*/, ""); key=ipv6(tolower($1))
    if(key=="" || NF<2 || !eligible(packed(key))) next
    if(mode=="static") protected[key]=1
    else tracked[key]=1
    next
}
mode=="lan6" {
    if($0!~/scope global/ || $0~/(^|[ \t])(tentative|dadfailed)([ \t]|$)/ ||
       $0~/valid_lft[ \t]+0(sec)?([ \t]|$)/) next
    for(i=1;i<NF;i++) if($i=="inet6") {
        n=split(tolower($(i+1)),cidr,"/"); key=ipv6(cidr[1])
        if(n!=2 || key=="" || cidr[2]!~/^[0-9]+$/ || cidr[2]<1 || cidr[2]>128) next
        if(!eligible(packed(key))) next
        p=key "/" cidr[2]; lan6_key[p]=key; lan6_bits[p]=cidr[2]+0
        break
    }
    next
}
END {
    for(key in tracked) {
        if(++count>512) exit 2
        state=(key in protected)?"protected":(current_lan6(key)?"live":"expired")
        print state, packed(key)
    }
}
