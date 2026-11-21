-- Filtro do pandoc para o site da documentação.
--
-- Links para outros .md viram links para o .html correspondente, mantendo a
-- âncora. Links e imagens de diagramas (.puml ou .png em diagramas/) passam a
-- apontar para o .svg gerado pelo build.

local function rewrite(target)
  if target:match("^%a[%w+.-]*:") then
    return target -- URL absoluta
  end
  local path, anchor = target:match("^([^#]*)(#?.*)$")
  if path:match("%.md$") then
    return path:gsub("%.md$", ".html") .. anchor
  end
  if path:match("diagramas/[^/]+%.puml$") or path:match("diagramas/[^/]+%.png$") then
    return path:gsub("%.%w+$", ".svg") .. anchor
  end
  return target
end

function Link(el)
  el.target = rewrite(el.target)
  return el
end

-- Imagens viram links para si mesmas, para abrir diagramas largos em
-- tamanho real.
function Image(el)
  el.src = rewrite(el.src)
  return pandoc.Link(el, el.src)
end
