-- Typ2docx content adjustments, paired with 04-shading.patch. The Typst
-- reader captures highlight regions as mark divs/spans and block/box
-- fills as background-color attributes; fills are normalized to marks,
-- so every marked region renders through pandoc's native handling with
-- the default text highlight color (the highlighter pen: one mechanism,
-- one color, the tool Word users reach for). Pandoc's pen never reaches
-- OMML runs (the math converter bypasses the run-property environment),
-- so math-bearing paragraphs in a marked region take the pen-yellow
-- ShadingBlock band, and a region ending in a table hoists the table out
-- to the pen-yellow ShadedTable style; block math inside #highlight
-- crashes the reader outright, which is why fills remain the source-side
-- convention for math regions. The reader also emits whitespace-only
-- paragraphs for comment lines and bracket newlines, and anchor-only
-- paragraphs for labels; Typst source never carries an intentional
-- empty paragraph, so they are dropped, and a region trims them before
-- its trailing-table check: left in place they would render as blank
-- lines and defeat the hoist that restores the margin below the table.
-- A figure wrapping only a table flattens to the table (caption
-- position and numbering).

local TABLESTYLE = "ShadedTable"
local MATHSTYLE = "ShadingBlock"

local function has_math(ils)
  for _, inl in ipairs(ils) do
    if inl.t == "Math" then return true end
    if inl.t == "Span" and has_math(inl.content) then return true end
  end
  return false
end

local function blank(inl)
  return inl.t == "Space" or inl.t == "SoftBreak" or inl.t == "LineBreak"
    or (inl.t == "Str" and inl.text:match("^%s*$") ~= nil)
    or (inl.t == "Span" and #inl.content == 0)
end

local function blank_para(b)
  if b.t ~= "Para" and b.t ~= "Plain" then return false end
  for _, inl in ipairs(b.content) do
    if not blank(inl) then return false end
  end
  return true
end

local function trim_blank(list)
  while #list > 0 and blank(list[1]) do list:remove(1) end
  while #list > 0 and blank(list[#list]) do list:remove(#list) end
  return list
end

local function marked(el)
  if not el.classes:includes("mark") then el.classes:insert(1, "mark") end
  return el
end

-- The writer's highlight pen reaches mark spans but not div contents, so a
-- region's paragraphs carry their text inside a mark span of their own.
local function pen(b)
  b.content = pandoc.List(
    { pandoc.Span(b.content, pandoc.Attr("", { "mark" }, {})) }
  )
  return b
end

local PEN = { Header = pen, Para = pen, Plain = pen }

function Div(el)
  local fill = el.attributes["background-color"] ~= nil
  if not fill and not el.classes:includes("mark") then return nil end
  el.attributes["background-color"] = nil
  while #el.content > 0 and blank_para(el.content[1]) do
    el.content:remove(1)
  end
  while #el.content > 0 and blank_para(el.content[#el.content]) do
    el.content:remove(#el.content)
  end
  local last = el.content[#el.content]
  if last ~= nil and last.t == "Table" then
    el.content:remove(#el.content)
    last.attributes["custom-style"] = TABLESTYLE
    if #el.content == 0 then return last end
    return pandoc.List({ el, last })
  end
  el.content = el.content:map(function(b)
    if (b.t == "Para" or b.t == "Plain" or b.t == "Header")
        and has_math(b.content) then
      -- the writer's pen never reaches OMML runs (convertMath bypasses
      -- the highlight environment), so math-bearing paragraphs take the
      -- pen-colored band instead
      return pandoc.Div({ b },
        pandoc.Attr("", {}, { ["custom-style"] = MATHSTYLE }))
    end
    if b.t == "Header" or b.t == "Para" then return pen(b) end
    if b.t == "Table" then return pandoc.walk_block(b, PEN) end
    return b
  end)
  return el
end

function Para(el)
  local only = el.content[1]
  if #el.content == 1 and only.t == "Span"
      and only.classes:includes("mark") then
    trim_blank(only.content)
    if #only.content == 0 then return pandoc.List() end
    if has_math(only.content) then
      return pandoc.Div({ pandoc.Para(only.content) },
        pandoc.Attr("", {}, { ["custom-style"] = MATHSTYLE }))
    end
  end
  if blank_para(el) then return pandoc.List() end
  return nil
end

function Plain(el)
  if blank_para(el) then return pandoc.List() end
  return nil
end

function Span(el)
  if el.attributes["background-color"] == nil then return nil end
  el.attributes["background-color"] = nil
  return marked(el)
end

function Figure(el)
  if #el.content == 1 and el.content[1].t == "Table" then
    local t = el.content[1]
    if #(t.caption.long or {}) == 0 and #(el.caption.long or {}) > 0 then
      t.caption = pandoc.Caption(el.caption.short, el.caption.long)
    end
    if t.identifier == "" then
      t.identifier = el.identifier
    end
    return t
  end
  return nil
end
