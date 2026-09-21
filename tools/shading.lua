-- Typ2docx shading. The Typst reader captures block and box fills as
-- background-color attributes; map them onto the stock's shading styles
-- so Word shades the regions exactly like its own fill-color selection,
-- which covers display math. Shading adds no spacing of its own; shaded
-- regions keep the body rhythm. Headings and table cells, where the
-- writer pins its own paragraph style, get the character style instead.
-- A region ending in a table hoists the table out to the shaded table
-- style: left in the div, the block shading cannot reach it (tables take
-- no paragraph style) and the div would leave the following paragraph in
-- BodyText with no margin below the table. Highlight regions keep
-- pandoc's native mark handling (the highlight pen). Style names must
-- match the custom-style values exactly, or the writer injects a
-- shadowing placeholder definition.

local PARASTYLE = "ShadingBlock"
local CHARSTYLE = "ShadingInline"
local TABLESTYLE = "ShadedTable"

local function pin(b)
  b.content = pandoc.List(
    { pandoc.Span(b.content, pandoc.Attr("", {}, { ["custom-style"] = CHARSTYLE })) }
  )
  return b
end

local PIN = { Header = pin, Para = pin, Plain = pin }

local function shade(el)
  el.attributes["custom-style"] = PARASTYLE
  el.content = el.content:map(function(b)
    if b.t == "Header" then return pin(b) end
    if b.t == "Table" then return pandoc.walk_block(b, PIN) end
    return b
  end)
  return el
end

function Div(el)
  if el.attributes["background-color"] == nil then return nil end
  el.attributes["background-color"] = nil
  local last = el.content[#el.content]
  if last ~= nil and last.t == "Table" then
    el.content[#el.content] = nil
    last.attributes["custom-style"] = TABLESTYLE
    if #el.content == 0 then return last end
    return pandoc.List({ shade(el), last })
  end
  return shade(el)
end

function Span(el)
  if el.attributes["background-color"] == nil then return nil end
  el.attributes["background-color"] = nil
  el.attributes["custom-style"] = CHARSTYLE
  return el
end
