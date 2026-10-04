-- Typ2docx content adjustments. The Typst reader captures highlight
-- regions as mark divs/spans covering their whole body (multi-paragraph
-- and math-bearing bodies included) and block/box fills as
-- background-color attributes; the filter normalizes fills to marks
-- and dissolves each marked region into mark spans, one around every
-- paragraph's, heading's and cell's inline content, for the docx
-- writer's pen, which covers every run inside a mark span, text and
-- OMML math alike, and labels marked captions inside the mark span,
-- so their "Table 9:" supplements take the pen too. Reference entries
-- the draft declares as added in the revision (cite keys under the
-- added-refs metadata key, set by the reader's #metadata handler from
-- #metadata((<key>, ..)) in the source) take
-- the same pen: citeproc fills the refs div with entries identified
-- ref-<key>, so the keys mark their entries in place, one References
-- list with sparing highlights. The filter's whole
-- caption treatment is one pen span per marked caption (the
-- caption-mark attribute keeps the paragraph handlers off them): the
-- writer forces caption paragraph styles and builds the supplements
-- itself, beyond the filter's reach. The reader
-- also emits whitespace-only paragraphs for comment lines and bracket
-- newlines, and anchor-only paragraphs for labels; Typst source never
-- carries an intentional empty paragraph, so they are dropped, and a
-- region trims them from its edges. A figure wrapping
-- only a table flattens to the table (caption position and numbering).
-- Tables stay inside their mark region to the final pen pass, which
-- spans every run in their cells as it does for text and math. A note
-- paragraph (italic
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
-- treatment is this pen span, in two shapes. A caption inside a marked
-- region is changed content and takes a bare mark span: the writer pens
-- every run in one, so the whole body and the supplement highlight
-- together. Outside a region a caption is penned only where its own
-- source carries marks, so the wrapper carries the caption-mark
-- attribute, which the writer's pen deliberately does not match: the
-- body keeps to its inner marks while the label, which reads the mark
-- class, still takes the pen. The attribute also keeps the paragraph
-- handlers from reworking caption paragraphs behind the writer's back.
local function caption_pen(b, in_region)
  local only = b.content[1]
  if #b.content == 1 and only.t == "Span"
      and only.classes:includes("mark") then
    return b
  end
  local attr
  if in_region then
    attr = pandoc.Attr("", { "mark" }, {})
  else
    attr = pandoc.Attr("", { "mark" }, { [CAPMARK] = "" })
  end
  b.content = pandoc.List({ pandoc.Span(b.content, attr) })
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
    if in_region or block_marked(b) then
      blocks[i] = caption_pen(b, in_region)
    end
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

-- A float's note paragraph opens with an italicized "Note." and hangs
-- off the table or image above it, wherever that float ended up
-- (alone or closing a highlight region).
local function is_note_para(b)  if b.t ~= "Para" then return false end
  local first = b.content[1]
  if first == nil or first.t ~= "Emph" then return false end
  local s = first.content[1]
  return s ~= nil and s.t == "Str" and s.text:match("^Note%.?$") ~= nil
end

function Figure(el)
  local in_region = el.attributes["in-region"] ~= nil
  captioned(el, in_region)
  -- A figure whose body ends in a note para is a bundled float (the
  -- source-side figure wrapper ties the note to its content): re-emit
  -- one movable unit carrying [content, note], so the fixpoint moves
  -- them together and the docx chain binds the note into the unit.
  local note = nil
  if #el.content > 1 and is_note_para(el.content[#el.content]) then
    note = el.content[#el.content]
    el.content:remove(#el.content)
  end
  local flattened = nil
  if #el.content == 1 and el.content[1].t == "Table" then
    local t = el.content[1]
    if #(t.caption.long or {}) == 0 and #(el.caption.long or {}) > 0 then
      -- pandoc.Caption(short, long) rejects a nil short; the one-arg
      -- form sets long directly.
      t.caption = pandoc.Caption(el.caption.long)
    end
    if t.identifier == "" then
      t.identifier = el.identifier
    end
    if t.attributes["placement"] == nil
        and el.attributes["placement"] ~= nil then
      t.attributes["placement"] = el.attributes["placement"]
    end
    flattened = t
  end
  if note then
    local unit = { flattened or el, note }
    return pandoc.Div(unit, pandoc.Attr("", {}, { placement = "auto" }))
  end
  return flattened
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

-- References added in a revision, highlighted in place. The draft
-- declares their cite keys under the added-refs metadata key (set by
-- the typst reader's #metadata handler from a label list in the
-- source, #metadata((<key>, ..)) <added-refs>: labels are names, so
-- the value is a plain key list, apart from the citation machinery);
-- citeproc has already filled the refs div with entries whose
-- identifiers are ref-<key>, so the keys mark their entries and the
-- final pen pass highlights them.
local function collect_added_keys(v, keys)
  if type(v) == "string" then
    keys[v] = true
  elseif type(v) == "table" and v.t == nil then
    for _, x in ipairs(v) do collect_added_keys(x, keys) end
  end
end

local function mark_added_refs(doc)
  local v = doc.meta["added-refs"]
  if v == nil then return end
  local keys = {}
  collect_added_keys(v, keys)
  if next(keys) == nil then
    io.stderr:write(
      "typ2docx: added-refs must be cite keys, as in #metadata((<key>, ..)) <added-refs>\n")
    return
  end
  for _, b in ipairs(doc.blocks) do
    if b.t == "Div" and b.identifier == "refs" then
      for _, e in ipairs(b.content) do
        local id = e.t == "Div" and e.identifier or ""
        if id:sub(1, 4) == "ref-" and keys[id:sub(5)] then
          marked(e)
          keys[id:sub(5)] = nil
        end
      end
    end
  end
  for k in pairs(keys) do
    io.stderr:write(
      string.format("typ2docx: added-refs key %s has no reference entry\n", k))
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

-- A floated block inside a highlight region is lifted into its own
-- mark-wrapped unit at the same spot, so the fixpoint may move it
-- (moving a bare float out of its region would silently strip the
-- revision mark). The region splits into adjacent mark fragments,
-- visually identical to one region since the pen is per-run; the
-- region's identifier stays on the first emitted piece.
local function lift_floats(blocks)
  local out = pandoc.List()
  for _, b in ipairs(blocks) do
    if b.t == "Div" and b.classes:includes("mark") then
      local buf = pandoc.List()
      local first = true
      local function piece_attr()
        if first then
          first = false
          return b.attr
        end
        return pandoc.Attr("", { "mark" }, {})
      end
      local function flush()
        while #buf > 0 and blank_para(buf[1]) do buf:remove(1) end
        while #buf > 0 and blank_para(buf[#buf]) do buf:remove(#buf) end
        if #buf > 0 then
          out:insert(pandoc.Div(buf, piece_attr()))
          buf = pandoc.List()
        end
      end
      for _, c in ipairs(b.content) do
        if c.attributes ~= nil and c.attributes["placement"] ~= nil then
          flush()
          local attr = piece_attr()
          attr.attributes["placement"] = "auto"
          out:insert(pandoc.Div({ c }, attr))
        else
          buf:insert(c)
        end
      end
      flush()
    else
      out:insert(b)
    end
  end
  return out
end

-- The final pen pass. The docx writer pens mark spans, not mark divs
-- (a span's pen covers every run inside it, text and OMML math alike,
-- which is also how markdown's <mark> and the reader's inline
-- highlights are rendered), so every marked region dissolves into
-- per-paragraph mark spans: paragraphs, headings, note divs, list
-- items, figure bodies and table cells each get one span around their
-- inline content. Captions keep the pen span the caption pass already
-- made, and floats keep the mark fragments the fixpoint lifted them
-- into; only the runs change hands, not the structure. Code has no
-- inlines to wrap, so a marked code block re-voices itself through the
-- two contracts that do reach its runs: the writer renders a Code
-- inline exactly as it renders a code block (one paragraph, lines
-- split into runs), and a custom-style div stamps the paragraph with
-- the Source Code style the block itself would have taken.
local pen_blocks

local function penned(b)
  if b.t ~= "Para" and b.t ~= "Plain" then return false end
  local only = b.content[1]
  return #b.content == 1 and only ~= nil and only.t == "Span"
    and only.classes:includes("mark")
end

local function pen_inlines(ils)
  if #ils == 0 then return ils end
  return pandoc.List({ pandoc.Span(ils, pandoc.Attr("", { "mark" }, {})) })
end

local function pen_rows(rows)
  for _, row in ipairs(rows or {}) do
    for _, cell in ipairs(row.cells or {}) do
      pen_blocks(cell.content, true)
    end
  end
end

local function pen_block(b, inside)
  if b.t == "Para" or b.t == "Plain" then
    if inside and not penned(b) then b.content = pen_inlines(b.content) end
  elseif b.t == "Header" then
    if inside then b.content = pen_inlines(b.content) end
  elseif b.t == "LineBlock" then
    if inside then
      for j, line in ipairs(b.content) do b.content[j] = pen_inlines(line) end
    end
  elseif b.t == "CodeBlock" then
    if inside then
      local attr = pandoc.Attr(b.identifier, b.classes, b.attributes)
      local code = pandoc.Code(b.text, attr)
      local span = pandoc.Span(pandoc.List({ code }),
        pandoc.Attr("", { "mark" }, {}))
      return pandoc.Div(pandoc.List({ pandoc.Para(pandoc.List({ span })) }),
        pandoc.Attr("", {}, { ["custom-style"] = "Source Code" }))
    end
  elseif b.t == "Table" then
    if inside then
      pen_rows(b.head and b.head.rows)
      for _, body in ipairs(b.bodies or {}) do
        pen_rows(body.head)
        pen_rows(body.body)
      end
      pen_rows(b.foot and b.foot.rows)
      pen_blocks(b.caption.long or {}, true)
    end
  elseif b.t == "Figure" then
    pen_blocks(b.content, inside)
    if inside then pen_blocks(b.caption.long or {}, true) end
  elseif b.t == "Div" then
    pen_blocks(b.content, inside or b.classes:includes("mark"))
  elseif b.t == "BlockQuote" then
    pen_blocks(b.content, inside)
  elseif b.t == "BulletList" or b.t == "OrderedList" then
    for _, item in ipairs(b.content) do pen_blocks(item, inside) end
  end
  return b
end

pen_blocks = function(blocks, inside)
  for i, b in ipairs(blocks) do blocks[i] = pen_block(b, inside) end
  return blocks
end

function Pandoc(doc)
  -- House default: every table and figure floats (placement = auto) so
  -- Word keeps it whole and near where it was written. Explicit source
  -- decisions win: the reader carries placement: none through as an
  -- opt-out and auto/top/bottom as intent.
  doc = doc:walk({
    Table = function(el)
      if el.attributes["placement"] == nil then
        el.attributes["placement"] = "auto"
        return el
      end
    end,
    Figure = function(el)
      if el.attributes["placement"] == nil then
        el.attributes["placement"] = "auto"
        return el
      end
    end,
  })
  doc.blocks = lift_floats(doc.blocks)
  mark_notes(doc.blocks)
  mark_added_refs(doc)
  pen_blocks(doc.blocks)
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
