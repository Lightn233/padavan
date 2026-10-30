#!/usr/bin/env bash
# 在机型模板之后应用公共覆盖；同一个配置项以最后一次出现为准。
set -euo pipefail

product="${1:?请指定机型，例如 RM2100}"
root="$(pwd)"
config="$root/trunk/.config"
common_override="$root/hello/common.override"

if [ ! -f "$config" ]; then
  echo "错误：未找到 $config，请先复制机型模板。" >&2
  exit 1
fi

# 在原文件所在目录生成结果，校验成功后再原子替换，失败不改变原配置。
tmp="$(mktemp "$root/trunk/.config.XXXXXX")"
trap 'rm -f -- "$tmp"' EXIT
inputs=("$config")
if [ -f "$common_override" ]; then
  inputs+=("$common_override")
fi
# 个人选择最后应用，并只作用于同名机型。
local_override="$root/hello/local/$product.override"
if [ -f "$local_override" ]; then
  inputs+=("$local_override")
fi

awk '
  function config_key(line, key) {
    key = line
    if (key ~ /^CONFIG_[A-Za-z0-9_]+=/) {
      sub(/=.*/, "", key)
      return key
    }
    if (key ~ /^#[ \t]+CONFIG_[A-Za-z0-9_]+ is not set[ \t]*$/) {
      sub(/^#[ \t]+/, "", key)
      sub(/ is not set[ \t]*$/, "", key)
      return key
    }
    return ""
  }
  {
    sub(/\r$/, "")
    lines[NR] = $0
    keys[NR] = config_key($0)
    if (keys[NR] != "") last[keys[NR]] = NR
    else last_comment[$0] = NR
  }
  END {
    for (i = 1; i <= NR; i++)
      if ((keys[i] == "" && last_comment[lines[i]] == i) ||
          (keys[i] != "" && last[keys[i]] == i)) print lines[i]
  }
' "${inputs[@]}" > "$tmp"

# 无效的硬件参数在替换配置、下载工具链之前报错。
python3 "$root/scripts/build_config.py" --validate-config "$product" "$tmp"

# 内容未变时保留时间戳，避免触发无意义的增量重编译。
if ! cmp -s -- "$config" "$tmp"; then
  chmod --reference="$config" "$tmp"
  mv -f -- "$tmp" "$config"
fi
echo "$product：覆盖配置已应用，重复配置项已归一化。"
