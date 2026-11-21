#!/bin/sh
# Gera o site estático da documentação.
#
# Uso: docs/site/build.sh [diretório de saída]   (padrão: site/ na raiz)
#
# Precisa de pandoc e plantuml. O diretório gerado é só HTML, CSS e SVG e
# pode ser servido por qualquer servidor web.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
docs=$(dirname "$here")
out=${1:-$(dirname "$docs")/site}

rm -rf "$out"
mkdir -p "$out/diagramas"

cp "$here/style.css" "$out/"

# Diagramas em SVG, mais as fontes PlantUML.
cp "$docs"/diagramas/*.puml "$out/diagramas/"
plantuml -failfast2 -tsvg -o "$out/diagramas" "$docs"/diagramas/*.puml

cd "$docs"
find . -name '*.md' -not -path './site/*' | sort | while read -r md; do
    md=${md#./}
    html="$out/${md%.md}.html"
    mkdir -p "$(dirname "$html")"

    # Caminho relativo até a raiz do site, para o menu e o CSS.
    depth=$(printf '%s' "$md" | tr -cd '/' | wc -c)
    root=$(printf '../%.0s' $(seq 1 "$depth") 2>/dev/null || true)
    [ "$depth" -eq 0 ] && root=""

    title=$(sed -n 's/^# //p' "$md" | head -n 1)

    pandoc "$md" \
        --from gfm \
        --to html5 \
        --standalone \
        --template "$here/template.html" \
        --lua-filter "$here/links.lua" \
        --metadata pagetitle="$title" \
        --variable root="$root" \
        --output "$html"
    echo "$md -> ${html#"$out"/}"
done

echo "Site gerado em $out"
