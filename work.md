## Kontext
Dieses Plugin erzeugt PNGs aus PDF-Anhängen in Redmine-Kommentaren und speichert sie als normale Redmine-Attachments im gleichen Filesystem-Storage wie alle Uploads.

Wichtig:
- Redmine speichert Attachments auf Platte unter einem internen Dateinamen (diskfile). Der sichtbare Attachment-Name (filename) ist etwas anderes.
- Die Plugin-PNGs erkennt man zuverlässig am Attachment-Dateinamen-Muster:
  - Cover: `*_a<PDF_ATTACHMENT_ID>_cover.png`
  - Seiten: `*_a<PDF_ATTACHMENT_ID>_p###.png`

## Pfad, wo Redmine Dateien ablegt
Im Redmine-Container (meist `/usr/src/redmine`):

```bash
cd /usr/src/redmine
bundle exec rails runner 'puts Attachment.storage_path'
```

Typisch ist z.B. `/usr/src/redmine/files/` mit Unterordnern `YYYY/MM`.

## Plugin-PNGs auflisten (kurz)
Nur echte Storage-Pfade (perfekt zum Download):

```bash
cd /usr/src/redmine
bundle exec rails runner '
Attachment.where("filename LIKE ?", "%.png").find_each do |png|
  m = png.filename.to_s.match(/_a(\d+)_(cover|p\d{3})\.png\z/i)
  next unless m

  pdf = Attachment.find_by(id: m[1].to_i)
  next unless pdf && pdf.filename.to_s.downcase.end_with?(".pdf")

  puts png.diskfile
end
'
```

Optional: Pfad + sichtbarer PNG-Name:

```bash
cd /usr/src/redmine
bundle exec rails runner '
Attachment.where("filename LIKE ?", "%.png").find_each do |png|
  m = png.filename.to_s.match(/_a(\d+)_(cover|p\d{3})\.png\z/i)
  next unless m

  pdf = Attachment.find_by(id: m[1].to_i)
  next unless pdf && pdf.filename.to_s.downcase.end_with?(".pdf")

  puts "#{png.diskfile}\t#{png.filename}"
end
'
```

## Datei mit Testinhalt erzeugen
Schreibt `test` nach `/usr/src/redmine/tmp/pdf/compresslist.json` und zeigt danach den Inhalt:

```bash
mkdir -p /usr/src/redmine/tmp/pdf && echo -n "test" > /usr/src/redmine/tmp/pdf/compresslist.json && cat /usr/src/redmine/tmp/pdf/compresslist.json
```

## PNGs aus compresslist.json komprimieren (Batch, mit Backup + interaktivem Cleanup)
Erwartung:
- `compresslist.json` enthält entweder JSON (`["/path/a.png", ...]` oder `{"files":[...]}`) oder einfach eine Liste von Pfaden (eine pro Zeile).
- Originale werden als `.orig` behalten.
- Komprimierte Datei bekommt wieder exakt den Originalnamen.
- Fortschritt zeigt `3/5209 basename.png` plus Größen vorher/nachher.
- Am Ende Auswahl: Backups löschen oder Originale wiederherstellen.

```bash
LIST="/usr/src/redmine/tmp/pdf/compresslist.json"
PNGQUANT="${PNGQUANT:-pngquant}"

set -euo pipefail

files="$(
  ruby -rjson -e '
    s = File.read(ARGV[0])
    begin
      j = JSON.parse(s)
      j = j["files"] if j.is_a?(Hash) && j.key?("files")
      Array(j).each { |x| puts x.to_s }
    rescue
      s.each_line { |l| l = l.strip; next if l.empty?; puts l }
    end
  ' "$LIST" | sed "s/\r$//" | sed "/^\s*$/d"
)"

total="$(printf "%s\n" "$files" | wc -l | tr -d " ")"
i=0

human() { awk -v b="$1" 'BEGIN{split("B KB MB GB TB",u," ");i=1;while(b>=1024&&i<5){b/=1024;i++}printf "%.1f %s",b,u[i]}' ; }

declare -a ORIGS=()
declare -a BAKS=()

printf "%s\n" "$files" | while IFS= read -r f; do
  i=$((i+1))
  base="$(basename "$f")"

  if [ ! -f "$f" ]; then
    echo "[$i/$total] $base MISSING"
    continue
  fi

  orig_bytes="$(wc -c < "$f" | tr -d " ")"

  bak="${f}.orig"
  if [ -e "$bak" ]; then
    bak="${f}.orig.$(date +%s)"
  fi

  mv -f "$f" "$bak"

  set +e
  "$PNGQUANT" --force --skip-if-larger --strip --speed 1 --quality 60-80 --output "$f" "$bak" >/dev/null 2>&1
  st=$?
  set -e

  if [ ! -f "$f" ]; then
    cp -p "$bak" "$f"
  fi

  comp_bytes="$(wc -c < "$f" | tr -d " ")"

  echo "[$i/$total] $base  orig=$(human "$orig_bytes")  comp=$(human "$comp_bytes")"

  ORIGS+=("$f")
  BAKS+=("$bak")
done

echo
read -r -p "Aktion: [d] Originale löschen (Backups *.orig*) / [r] Originale wiederherstellen? (d/r/Enter=keine): " action
case "$action" in
  d|D)
    for bak in "${BAKS[@]}"; do rm -f -- "$bak"; done
    echo "OK: Originale gelöscht (komprimierte Dateien bleiben aktiv)."
    ;;
  r|R)
    for idx in "${!ORIGS[@]}"; do
      orig="${ORIGS[$idx]}"
      bak="${BAKS[$idx]}"
      [ -f "$bak" ] || continue
      rm -f -- "$orig"
      mv -f -- "$bak" "$orig"
    done
    echo "OK: Originale wiederhergestellt (komprimierte ersetzt)."
    ;;
  *)
    echo "OK: Keine Änderung (komprimierte aktiv, Backups bleiben liegen)."
    ;;
esac
```

## Warum Redmine danach manchmal noch “große” Größen anzeigt
Redmine zeigt die Größe oft aus `attachments.filesize` (DB) an. Wenn du die Datei auf Platte ersetzt, kann diese DB-Zahl unverändert bleiben, obwohl der Download schon kleiner ist.

Prüfen (zeigt nur Abweichungen DB vs Platte für Plugin-PNGs):

```bash
cd /usr/src/redmine
bundle exec rails runner '
def human(n)
  units = %w[B KB MB GB TB]
  n = n.to_i
  i = 0
  f = n.to_f
  while f >= 1024 && i < units.length - 1
    f /= 1024.0
    i += 1
  end
  format("%.2f %s", f, units[i])
end

Attachment.where("filename LIKE ?", "%.png").find_each do |a|
  next unless a.filename.to_s.match?(/_a\d+_(cover|p\d{3})\.png\z/i)
  path = a.diskfile.to_s
  next unless File.file?(path)
  disk = File.size(path).to_i
  db = a.filesize.to_i
  next if disk == db
  puts "#{a.id}\t#{a.filename}\tdb=#{human(db)}\tdisk=#{human(disk)}\t#{path}"
end
'
```

DB-Filesize updaten (nur Plugin-PNGs):

```bash
cd /usr/src/redmine
bundle exec rails runner '
updated = 0

Attachment.where("filename LIKE ?", "%.png").find_each do |a|
  next unless a.filename.to_s.match?(/_a\d+_(cover|p\d{3})\.png\z/i)
  path = a.diskfile.to_s
  next unless File.file?(path)
  disk = File.size(path).to_i
  next if disk == a.filesize.to_i
  a.update_columns(filesize: disk)
  updated += 1
end

puts "updated=#{updated}"
'
```

## 404 beim Download (Attachment existiert, Datei fehlt/ist unlesbar)
Ein 404 auf `GET /attachments/<id>` kommt typischerweise, wenn Redmine den Attachment-Datensatz findet, aber die Datei auf Platte nicht existiert oder nicht lesbar ist.

Attachment prüfen (Beispiel: 32503):

```bash
cd /usr/src/redmine
bundle exec rails runner '
Rails.logger = Logger.new(nil) rescue nil
a = Attachment.find(32503)
p = a.diskfile.to_s
puts "id=#{a.id} filename=#{a.filename}"
puts "diskfile=#{p}"
puts "exists=#{File.exist?(p)} readable=#{File.readable?(p)}"
puts "filesize_db=#{a.filesize}"
puts "filesize_disk=#{File.file?(p) ? File.size(p) : "n/a"}"
'
```

Hinweis zu `ls`/Command-Substitution:
Wenn `bundle exec rails runner ...` Logzeilen ausgibt, landen sie bei `$(...)` in der Variable und können `ls` kaputt machen (z.B. “File name too long”). Deshalb oben `Rails.logger = Logger.new(nil)`.

## Fix, wenn komprimierte Datei durch Rechte/Owner unlesbar geworden ist
Rechte/Owner von `.orig` auf die komprimierte Datei übertragen:

```bash
find /usr/src/redmine/files -type f -name "*.png.orig*" -print0 | while IFS= read -r -d "" bak; do
  cur="${bak%.orig*}"
  [ -f "$cur" ] || continue
  chown --reference="$bak" "$cur" 2>/dev/null || true
  chmod --reference="$bak" "$cur" 2>/dev/null || true
done
```

## Fix, wenn die aktuelle Datei fehlt (exists=false): aus .orig wiederherstellen
Nur fehlende Dateien restore’n:

```bash
find /usr/src/redmine/files -type f -name "*.png.orig*" -print0 | while IFS= read -r -d "" bak; do
  cur="${bak%.orig*}"
  [ -f "$cur" ] && continue
  mv -f "$bak" "$cur"
  echo "RESTORED $cur"
done
```

