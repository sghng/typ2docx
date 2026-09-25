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
-- region trims them from its edges. A figure wrapping
-- only a table flattens to the table (caption position and numbering).
-- Tables stay inside their mark region to the writer, which pens every
-- run in them as it does for text and math. A note paragraph (italic
-- "Note." opening a paragraph that follows a table or image) is a
-- float annotation, not a paragraph start: the filter wraps it in a
-- no-indent div and the writer drops its first-line indent. APA: the
-- references
-- section starts on a new page, so a raw page-break run goes at the
-- start of the header preceding citeproc's empty refs div (inside
-- the header paragraph, so the break leaves no blank line), and every
-- appendix after the refs div opens its level-1 heading with the same
-- break run, a label line ("Appendix", lettered when the paper has
-- more than one), and a line break before the title. Appendix
-- headings sit at the top level or open a highlight region, so the
-- zone is walked in order and level-1 headings are collected
-- wherever they appear.

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

-- A float's note paragraph opens with an italicized "Note." and hangs
-- off the table or image above it, wherever that float ended up
-- (alone or closing a highlight region).
local function is_note_para(b)
  if b.t ~= "Para" then return false end
  local first = b.content[1]
  if first == nil or first.t ~= "Emph" then return false end
  local s = first.content[1]
  return s ~= nil and s.t == "Str" and s.text:match("^Note%.?$") ~= nil
end

local function ends_with_float(b)
  if b.t == "Table" or b.t == "Figure" then return true end
  if b.t == "Div" then
    for i = #b.content, 1, -1 do
      local c = b.content[i]
      if not blank_para(c) then return ends_with_float(c) end
    end
  end
  return false
end

local function mark_notes(blocks)
  for i = 1, #blocks do
    local b = blocks[i]
    if b.t == "Div" then mark_notes(b.content) end
    if i > 1 and is_note_para(b) and ends_with_float(blocks[i - 1]) then
      blocks[i] = pandoc.Div({ b }, pandoc.Attr("", { "no-indent" }, {}))
    end
  end
end

local function collect_appendix_heads(blocks, first, out)
  for i = first, #blocks do
    local b = blocks[i]
    if b.t == "Header" and b.level == 1 then
      out[#out + 1] = b
    elseif b.t == "Div" then
      collect_appendix_heads(b.content, 1, out)
    end
  end
end

local function label_appendices(doc, from)
  local heads = {}
  collect_appendix_heads(doc.blocks, from, heads)
  for n, head in ipairs(heads) do
    local label = "Appendix"
    if #heads > 1 then label = label .. " " .. string.char(64 + n) end
    head.content:insert(1, pandoc.RawInline("openxml",
      '<w:r><w:br w:type="page" /></w:r>'))
    head.content:insert(2, pandoc.Str(label))
    head.content:insert(3, pandoc.LineBreak())
  end
end

function Pandoc(doc)
  mark_notes(doc.blocks)
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
      label_appendices(doc, i + 1)
      break
    end
  end
  return doc
end
