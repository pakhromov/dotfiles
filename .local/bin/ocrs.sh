tmp_img="$(mktemp --suffix=.png)"
trap 'rm -f "$tmp_img"' EXIT

dulcepan -f png -o "$tmp_img"
ocrs "$tmp_img" | wl-copy
