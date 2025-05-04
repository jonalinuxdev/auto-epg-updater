#!/bin/bash
set -e

INPUT_JSON="epg/urls/link.json"
DEST_DIR="epg/xml"
OUTPUT_JSON="epg/stable-epg-sources.json"
RAW_BASE_URL="https://raw.githubusercontent.com/jonalinuxdev/auto-epg-updater/refs/heads/main/epg/xml"

timestamp=$(date '+%Y-%m-%d %H:%M')
log_file="epg-log.txt"
TEMP_README="README.tmp"

echo "REPO_DIR: $(pwd)"
echo "INPUT_JSON: $INPUT_JSON"
echo "DEST_DIR: $DEST_DIR"
echo "OUTPUT_JSON: $OUTPUT_JSON"
echo "RAW_BASE_URL: $RAW_BASE_URL"

mkdir -p "$DEST_DIR"

{
echo "🕒 Inizio download EPG: $timestamp"
echo

declare -A country_links

if [[ ! -f "$INPUT_JSON" ]]; then
  echo "Errore: File input JSON non trovato: $INPUT_JSON"
  exit 1
fi

mapfile -t countries < <(jq -r 'keys[]' "$INPUT_JSON")

if [ ${#countries[@]} -eq 0 ]; then
    echo "Nessun paese trovato nel JSON. Uscita."
    echo '{}' > "$OUTPUT_JSON"
    exit 0
fi

for country in "${countries[@]}"; do
  mapfile -t urls < <(jq -r --arg c "$country" '.[$c][]' "$INPUT_JSON")
  for url in "${urls[@]}"; do
    filename=$(basename "$url")
    base="${filename%.xml.gz}"
    base="${base%.xml}"
    output_file="guide-${base}.xml"
    temp_file="temp_${base}.xml.gz"

    echo "Scarico: $url"
    if curl -fsSL --connect-timeout 10 --retry 5 --retry-delay 5 "$url" -o "$temp_file"; then
      mime_type=$(file --mime-type --brief "$temp_file")
      echo "Detected MIME type: $mime_type"

      if [[ "$mime_type" == "application/gzip" ]]; then
        echo "📦 Scompatto GZ: $temp_file"
        if gunzip -c "$temp_file" > "$DEST_DIR/$output_file"; then
            echo "✅ Scompattato e salvato: $DEST_DIR/$output_file"
            country_links["$country"]+="$RAW_BASE_URL/$output_file "
        else
            echo "⚠️ Errore nella scompattazione di $temp_file"
            rm -f "$temp_file"
        fi
      elif [[ "$mime_type" == "application/xml" || "$mime_type" == "text/xml" || "$mime_type" == "text/plain" ]]; then
        echo "📄 Copio XML: $temp_file"
        mv "$temp_file" "$DEST_DIR/$output_file"
        echo "✅ Copiato e salvato: $DEST_DIR/$output_file"
        country_links["$country"]+="$RAW_BASE_URL/$output_file "
      else
        echo "⚠️ MIME non gestito: $mime_type"
        rm -f "$temp_file"
      fi
      rm -f "$temp_file"
    else
      echo "⚠️ Errore nel download: $url"
    fi
  done
done

echo "🛠 Creo JSON: $OUTPUT_JSON"
echo '{' > "$OUTPUT_JSON"
first_country=1
for country in "${!country_links[@]}"; do
  [[ $first_country -eq 0 ]] && echo ',' >> "$OUTPUT_JSON"
  first_country=0
  echo -n "  \"$country\": [" >> "$OUTPUT_JSON"
  IFS=' ' read -r -a urls <<< "${country_links[$country]}"
  first_url=1
  for url in "${urls[@]}"; do
    [[ $first_url -eq 0 ]] && echo -n ', ' >> "$OUTPUT_JSON"
    first_url=0
    echo -n "\"${url}\"" >> "$OUTPUT_JSON"
  done
  echo "]" >> "$OUTPUT_JSON"
done
echo '}' >> "$OUTPUT_JSON"

echo
echo "✅ Completato: $OUTPUT_JSON"
} | tee "$log_file"

# Salva log in file
log_file="epg.log"
exec > >(tee "$log_file") 2>&1

# (qui va il corpo dello script, poi alla fine:)

TEMP_README="README.tmp"

# Inserisce log e timestamp in cima al README
{
  echo "## 📝 Ultima esecuzione"
  echo
  echo "- Data: $timestamp"
  echo "- Totale paesi: ${#countries[@]}"
  echo
  awk '
    BEGIN {skip=0}
    /^## 📝 Ultima esecuzione/ {skip=1; next}
    skip && /^## / {skip=0}
    skip == 0 {print}
  ' README.md
} > "$TEMP_README"

mv "$TEMP_README" README.md

# Appende log dettagliato
{
  echo
  echo "## 🧾 Log dettagliato ultima esecuzione"
  echo
  echo '```bash'
  cat "$log_file"
  echo '```'
} >> README.md

# Git auto-commit & push
cd "$(dirname "$0")"
if git diff --quiet && git diff --cached --quiet; then
  echo "🟢 Nessuna modifica da pushare su Git."
else
  echo "📤 Push su GitHub..."
  git add .
  git commit -m "📡 EPG update: $timestamp"
  git push origin main
fi

