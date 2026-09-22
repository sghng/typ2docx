-- Typ2docx content adjustments. The Typst reader captures highlight
-- regions as mark divs/spans covering their whole body (multi-paragraph
-- and math-bearing bodies included) and block/box fills as
-- background-color attributes; the filter normalizes fills to marks and
-- leaves all highlighting to the docx writer's native pen, which covers
-- every run inside a mark, text and OMML math alike, and labels marked
-- captions inside the mark span, so their "Table 9:" supplements take
-- the pen too. The filter's whole caption treatment is one pen span per
-- marked caption (the caption-mark attribute keeps the paragraph
-- handlers off them): the writer forces caption paragraph styles and
-- builds the supplements itself, beyond the filter's reach. The reader
-- also emits whitespace-only paragraphs for comment lines and bracket
-- newlines, and anchor-only paragraphs for labels; Typst source never
-- carries an intentional empty paragraph, so they are dropped, and a
-- region trims them before its trailing-table check. A region ending
-- in a table hoists the table out so the following paragraph regains
-- its FirstParagraph margin. A figure wrapping only a table flattens
-- to the table (caption position and numbering). APA: the references
-- section starts on a new page, so a raw page-break run goes at the
-- start of the header preceding citeproc's empty refs div (inside
-- the header paragraph, so the break leaves no blank line).

local CAPMARK = "caption-mark"

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

-- Caption paragraphs take their style from the writer and their
-- supplement runs exist only in its output, so the filter's whole caption
-- treatment is this pen span; the attribute keeps the paragraph handlers
-- from reworking caption paragraphs behind the writer's back.
local function caption_pen(b)
  local only = b.content[1]
  if #b.content == 1 and only.t == "Span"
      and only.attributes[CAPMARK] ~= nil then
    return b
  end
  b.content = pandoc.List(
    { pandoc.Span(b.content,
      pandoc.Attr("", { "mark" }, { [CAPMARK] = "" })) }
  )
  return b
end

-- Inside a marked region every caption block is changed content; outside,
-- a block is penned only when it carries a mark, so the supplement
-- paragraph of a partly marked caption stays clean.
local function is_marked(ils)
  for _, inl in ipairs(ils) do
    if inl.t == "Span" then
      if inl.classes:includes("mark")
          or inl.attributes["background-color"] ~= nil
          or is_marked(inl.content) then
        return true
      end
    end
  end
  return false
end

local function block_marked(b)
  if b.t ~= "Para" and b.t ~= "Plain" then return false end
  return is_marked(b.content)
end

local function captioned(el, in_region)
  local blocks = el.caption.long
  if not blocks then return el end
  for i, b in ipairs(blocks) do
    if in_region or block_marked(b) then blocks[i] = caption_pen(b) end
  end
  return el
end

function Div(el)
  local fill = el.attributes["background-color"] ~= nil
  if not fill and not el.classes:includes("mark") then return nil end
  el.attributes["background-color"] = nil
  if fill then marked(el) end
  while #el.content > 0 and blank_para(el.content[1]) do
    el.content:remove(1)
  end
  while #el.content > 0 and blank_para(el.content[#el.content]) do
    el.content:remove(#el.content)
  end
  local last = el.content[#el.content]
  if last ~= nil and last.t == "Table" then
    el.content:remove(#el.content)
    captioned(last, true)
    if #el.content == 0 then return last end
    return pandoc.List({ el, last })
  end
  el.content = el.content:map(function(b)
    if b.t == "Table" then
      return captioned(b, true)
    end
    if b.t == "Figure" then
      b.attributes["in-region"] = ""
      return captioned(b, true)
    end
    return b
  end)
  return el
end

function Para(el)
  local only = el.content[1]
  if #el.content == 1 and only.t == "Span" then
    if only.attributes[CAPMARK] ~= nil then return nil end
    if only.classes:includes("mark") then
      trim_blank(only.content)
      if #only.content == 0 then return pandoc.List() end
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

function Table(el)
  captioned(el, el.attributes["in-region"] ~= nil)
  return nil
end

function Figure(el)
  local in_region = el.attributes["in-region"] ~= nil
  captioned(el, in_region)
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

function Pandoc(doc)
  for i, b in ipairs(doc.blocks) do
    if b.t == "Div" and b.identifier == "refs" then
      local prev = doc.blocks[i - 1]
      if prev ~= nil and prev.t == "Header" then
        prev.content:insert(1, pandoc.RawInline("openxml",
          '<w:r><w:br w:type="page" /></w:r>'))
      else
        doc.blocks:insert(i, pandoc.RawBlock("openxml",
          '<w:p><w:r><w:br w:type="page" /></w:r></w:p>'))
      end
      break
    end
  end
  return doc
end
