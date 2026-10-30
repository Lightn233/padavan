#!/bin/sh
# 校验精简 BusyBox 下的配置比较；只使用新建的临时目录。
set -eu
[ "$#" = 1 ] || { echo '用法：sh test_digest_compare.sh /源码路径/trunk/user/legacy-compat/legacy-service.sh' >&2; exit 2; }
. "$1"
compat_test_dir=$(mktemp -d) || exit 1
trap 'rm -rf -- "$compat_test_dir"' EXIT HUP INT TERM
mkdir "$compat_test_dir/bin"
printf '#!/bin/sh\nexit 127\n' > "$compat_test_dir/bin/cmp"
chmod 755 "$compat_test_dir/bin/cmp"
PATH="$compat_test_dir/bin:$PATH"
export PATH
printf 'name=测试\nvalue=unchanged\n' > "$compat_test_dir/a"
cp "$compat_test_dir/a" "$compat_test_dir/b"
compat_same_file "$compat_test_dir/a" "$compat_test_dir/b"
echo 'PASS equal'
printf 'name=测试\nvalue=different\n' > "$compat_test_dir/b"
if compat_same_file "$compat_test_dir/a" "$compat_test_dir/b"; then exit 1; fi
echo 'PASS different'
: > "$compat_test_dir/a"
: > "$compat_test_dir/b"
compat_same_file "$compat_test_dir/a" "$compat_test_dir/b"
echo 'PASS empty'
if compat_same_file "$compat_test_dir/a" "$compat_test_dir/missing" 2>/dev/null; then exit 1; fi
echo 'PASS one-missing'
if compat_same_file "$compat_test_dir/missing" "$compat_test_dir/also-missing" 2>/dev/null; then exit 1; fi
echo 'PASS both-missing'
if compat_same_file "$compat_test_dir" "$compat_test_dir" 2>/dev/null; then exit 1; fi
echo 'PASS directory-read-error'
