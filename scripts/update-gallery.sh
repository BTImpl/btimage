#!/usr/bin/env bash
set -euo pipefail

MANIFEST="data/gallery.json"
IMAGES_DIR="images"

mkdir -p "$IMAGES_DIR" "$(dirname "$MANIFEST")"

if [ ! -f "$MANIFEST" ]; then
  echo "[]" > "$MANIFEST"
fi

# Legutóbbi posztok lekérése (alapértelmezetten kb. 25, ez bőven elég
# 30 percenkénti futásnál egy fotós fióknak).
RESPONSE=$(curl -s "https://graph.facebook.com/v26.0/${IG_USER_ID}/media?fields=id,caption,media_type,media_url,permalink,timestamp&access_token=${IG_ACCESS_TOKEN}")

# Egyelőre csak a sima képeket dolgozzuk fel.
# Videó és karusszel (több képes poszt) kezelése később bővíthető,
# lásd a README "Ismert korlátok" részét.
echo "$RESPONSE" | jq -c '.data[]? | select(.media_type == "IMAGE")' | while read -r item; do
  ID=$(echo "$item" | jq -r '.id')

  ALREADY_KNOWN=$(jq --arg id "$ID" '[.[] | select(.id == $id)] | length' "$MANIFEST")
  if [ "$ALREADY_KNOWN" -gt 0 ]; then
    continue
  fi

  MEDIA_URL=$(echo "$item" | jq -r '.media_url')
  CAPTION=$(echo "$item" | jq -r '.caption // ""')
  PERMALINK=$(echo "$item" | jq -r '.permalink')
  TIMESTAMP=$(echo "$item" | jq -r '.timestamp')

  # Fontos: a media_url egy ideiglenes, aláírt link, ami hamarosan lejár —
  # ezért LETÖLTJÜK a képet, és a repóban tároljuk tartósan, nem a
  # media_url-t mentjük el a manifestbe.
  IMAGE_PATH="${IMAGES_DIR}/${ID}.jpg"
  curl -s -o "$IMAGE_PATH" "$MEDIA_URL"

  jq --arg id "$ID" \
     --arg caption "$CAPTION" \
     --arg permalink "$PERMALINK" \
     --arg timestamp "$TIMESTAMP" \
     --arg image "$IMAGE_PATH" \
     '. += [{id: $id, caption: $caption, permalink: $permalink, timestamp: $timestamp, image: $image}]' \
     "$MANIFEST" > "${MANIFEST}.tmp" && mv "${MANIFEST}.tmp" "$MANIFEST"

  echo "Új poszt hozzáadva: $ID"
done

# index.html újragenerálása a manifest teljes tartalmából, legújabb elöl.
{
  echo "<!DOCTYPE html>"
  echo "<html lang=\"hu\"><head><meta charset=\"utf-8\">"
  echo "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
  echo "<title>BT Image galéria</title>"
  echo "<style>"
  echo "body{font-family:sans-serif;max-width:800px;margin:2rem auto;padding:0 1rem;background:#111;color:#eee}"
  echo ".post{margin-bottom:2.5rem}"
  echo "img{max-width:100%;border-radius:8px;display:block;margin-bottom:0.75rem}"
  echo "a{color:#8ab4f8}"
  echo "</style></head><body>"
  echo "<h1>BT Image galéria</h1>"
  jq -r 'sort_by(.timestamp) | reverse | .[] |
    "<div class=\"post\"><img src=\"\(.image)\" alt=\"\"><p>\(.caption)</p><a href=\"\(.permalink)\">Megnézem Instagramon</a></div>"' \
    "$MANIFEST"
  echo "</body></html>"
} > index.html

echo "Galéria oldal újragenerálva."
