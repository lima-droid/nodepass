#!/usr/bin/env bash
# 只修改「安装 / 下载 / 镜像」链接：把上游组织 NodePassProject 指向本仓库 lima-droid。
# 其它内容（源码、配置、文档措辞）保持与上游逐字节一致，方便每次同步。
#
# 用法: bash .github/scripts/point-links-to-fork.sh
set -euo pipefail

UPSTREAM_ORG="${UPSTREAM_ORG:-NodePassProject}"
FORK_ORG="${FORK_ORG:-lima-droid}"

# 本仓库在上游 URL 中出现过的名字（加新别名时在这里补）
NAMES=("nodepass")

MAP=$(mktemp)
trap 'rm -f "$MAP"' EXIT

add() { printf '%s\t%s\n' "$1" "$2" >> "$MAP"; }

for name in "${NAMES[@]}"; do
  lname=$(echo "$name" | tr '[:upper:]' '[:lower:]')
  for base in "https://github.com" "https://raw.githubusercontent.com" "https://api.github.com/repos"; do
    add "${base}/${UPSTREAM_ORG}/${name}"  "${base}/${FORK_ORG}/${name}"
    add "${base}/${UPSTREAM_ORG}/${lname}" "${base}/${FORK_ORG}/${lname}"
  done
  # Docker 镜像（ghcr 名称大小写两种写法都出现过）
  add "ghcr.io/${UPSTREAM_ORG}/${name}"       "ghcr.io/${FORK_ORG}/${lname}"
  add "ghcr.io/${UPSTREAM_ORG,,}/${lname}"    "ghcr.io/${FORK_ORG}/${lname}"
  # 脚本里的仓库变量，例如 GITHUB_REPO="NodePassProject/nodepass"
  add "\"${UPSTREAM_ORG}/${name}\"" "\"${FORK_ORG}/${name}\""
  add "'${UPSTREAM_ORG}/${name}'"   "'${FORK_ORG}/${name}'"
done

# 只扫文本文件，跳过 .github（本仓库自己的自动化）、二进制、锁文件等
mapfile -t FILES < <(
  git ls-files -z \
    | tr '\0' '\n' \
    | grep -Ev '^(\.github/|CONTRIBUTING\.md$|LICENSE$|go\.sum$)' \
    | grep -Ev '(^|/)(node_modules|dist|vendor)/' \
    | grep -Ev '\.(png|jpe?g|gif|ico|svg|webp|woff2?|ttf|eot|otf|zip|gz|tgz|tar|exe|bin|db|sqlite|pdf|mp4|sum|lock)$' \
    || true
)

if [ ${#FILES[@]} -eq 0 ]; then
  echo "没有需要处理的文件"
  exit 0
fi

MAP="$MAP" perl -pi -e '
  BEGIN {
    open my $fh, "<", $ENV{MAP} or die "open map: $!";
    while (my $line = <$fh>) {
      chomp $line;
      my ($k, $v) = split /\t/, $line, 2;
      next unless defined $v && length $k;
      $R{$k} = $v;
    }
    # 长的先匹配，避免短串抢走长串
    @KEYS = sort { length($b) <=> length($a) } keys %R;
  }
  for my $k (@KEYS) { s/\Q$k\E/$R{$k}/g }
' "${FILES[@]}"

# 上游 .goreleaser.yml 把 nodepass 配成 prerelease: true，
# 会让发布的版本全部显示为「预发行版」，这里统一改成正式发布。
if [ -f .goreleaser.yml ]; then
  sed -i -E 's/^([[:space:]]*)prerelease:[[:space:]]*true[[:space:]]*$/\1prerelease: false/' .goreleaser.yml
fi

echo "链接重写完成，改动文件："
git diff --stat || true
