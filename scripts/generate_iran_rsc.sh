#!/usr/bin/env sh
set -eu

# ورودی‌ها
COUNTRIES_FILE="${1:-countries.txt}"
OUT_DIR="${2:-generated}"

mkdir -p "$OUT_DIR"

base_url="https://stat.ripe.net/data/country-resource-list/data.json"
last="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

filterv4='.data.resources.ipv4[]'
filterv6='.data.resources.ipv6[]'

# نرمال‌سازی اسم لیست:
# - IPv4: IP-<CC>  مثلا IP-IR
# - IPv6: <CC>v6   مثلا IRv6
v4_list_name() { echo "IP-$1"; }
v6_list_name() { echo "${1}v6"; }

write_country_rsc() {
  cc="$1"
  url="${base_url}?resource=${cc}&v4_format=prefix"

  # خروجی
  out_file="${OUT_DIR}/${cc}.rsc"

  # دریافت دیتا
  output="$(curl -s --http2-prior-knowledge -H 'Connection: close' "$url")"

  v4_list="$(echo "$output" | jq -r "$filterv4" 2>/dev/null || true)"
  v6_list="$(echo "$output" | jq -r "$filterv6" 2>/dev/null || true)"

  # اگر هیچ دیتایی نبود، فایل را نساز (یا قبلی را دست نزن)
  if [ -z "${v4_list}${v6_list}" ]; then
    echo "Skip ${cc}: empty"
    return 0
  fi

  v4name="$(v4_list_name "$cc")"
  v6name="$(v6_list_name "$cc")"

  {
    echo "# Last update: $last"
    echo "# Country: $cc"
    echo "# Source: $url"
    echo ""

    # IPv6
    echo "/ipv6 firewall address-list remove [/ipv6 firewall address-list find list=${v6name}]"
    echo "/ipv6 firewall address-list"
    for p in $v6_list; do
      echo ":do { add address=$p list=${v6name} } on-error={}"
    done
    echo ""

    # IPv4
    echo "/ip firewall address-list remove [/ip firewall address-list find list=${v4name}]"
    echo "/ip firewall address-list"
    for p in $v4_list; do
      echo ":do { add address=$p list=${v4name} } on-error={}"
    done
  } > "$out_file"

  echo "Wrote $out_file"
}

# اجرای اصلی: هر خط یک کد کشور (با امکان کامنت و خط خالی)
if [ ! -f "$COUNTRIES_FILE" ]; then
  echo "Countries file not found: $COUNTRIES_FILE" >&2
  exit 1
fi

while IFS= read -r line || [ -n "$line" ]; do
  cc="$(echo "$line" | tr -d '\r' | awk '{print $1}')"

  # خالی/کامنت
  [ -z "$cc" ] && continue
  echo "$cc" | grep -qE '^[#;]' && continue

  # uppercase
  cc="$(echo "$cc" | tr '[:lower:]' '[:upper:]')"

  # فقط 2 حرف
  echo "$cc" | grep -qE '^[A-Z]{2}$' || { echo "Skip invalid code: $cc"; continue; }

  write_country_rsc "$cc"
done < "$COUNTRIES_FILE"
