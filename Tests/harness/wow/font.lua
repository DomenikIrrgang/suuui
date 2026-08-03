-- Deterministic text metrics model.
--
-- Real glyph advances are font-file data we cannot read here, so the harness uses a
-- fixed monospace-equivalent model. It is exposed rather than hidden: tests compute
-- their expected sizes with the same helpers, so an assertion states "as wide as this
-- text at this size" instead of hardcoding a pixel count that only holds for one ratio.
local M = {}

--- Average glyph advance as a fraction of the font point size.
M.widthRatio = 0.5

--- Single-line height as a fraction of the font point size.
M.heightRatio = 1.25

--- Default point size when a widget never had SetFont called (GameFontNormal).
M.defaultSize = 12

local ceil, max, floor = math.ceil, math.max, math.floor

--- Strips WoW markup that carries no width: colour codes, texture escapes.
-- @param text string
-- @return string
function M.strip(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|T.-|t", "")
    return text
end

--- Width of a single line of text at a point size, ignoring any layout bound.
-- @param line string
-- @param size number
-- @return number
function M.lineWidth(line, size)
    return ceil(#line * (size or M.defaultSize) * M.widthRatio)
end

--- Height of one line at a point size.
-- @param size number
-- @return number
function M.lineHeight(size)
    return ceil((size or M.defaultSize) * M.heightRatio)
end

local function splitParagraphs(text)
    local out = {}
    for chunk in (text .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = chunk end
    if #out > 1 and out[#out] == "" then out[#out] = nil end
    if #out == 0 then out[1] = "" end
    return out
end

local function wrap(line, size, bound, breakWords)
    local perChar = (size or M.defaultSize) * M.widthRatio
    local maxChars = max(1, floor(bound / perChar))
    if #line <= maxChars then return { line } end

    local lines, currentLine = {}, ""
    for word in line:gmatch("%S+") do
        local candidate = (currentLine == "") and word or (currentLine .. " " .. word)
        if #candidate <= maxChars then
            currentLine = candidate
        else
            if currentLine ~= "" then lines[#lines + 1] = currentLine end
            -- The client only breaks inside a word when non-space wrap is enabled.
            -- Otherwise a word wider than the bound stays on its line and is clipped.
            if breakWords then
                while #word > maxChars do
                    lines[#lines + 1] = word:sub(1, maxChars)
                    word = word:sub(maxChars + 1)
                end
            end
            currentLine = word
        end
    end
    if currentLine ~= "" then lines[#lines + 1] = currentLine end
    if #lines == 0 then lines[1] = "" end
    return lines
end

--- Measures text as the client would render it.
-- @param text string
-- @param size number      Font point size
-- @param wordWrap bool    Whether wrapping is enabled (WoW default: true)
-- @param bound number     Assigned width in pixels, or nil for unbounded
-- @param nonSpaceWrap bool  Whether breaking inside a word is allowed (default: false)
-- @return number, number, number  renderedWidth, height, lineCount
function M.measure(text, size, wordWrap, bound, nonSpaceWrap)
    local clean = M.strip(text)
    size = size or M.defaultSize
    local lh = M.lineHeight(size)

    if clean == "" then return 0, 0, 0 end

    local paragraphs = splitParagraphs(clean)
    local lines = {}

    if wordWrap and bound and bound > 0 then
        for _, p in ipairs(paragraphs) do
            for _, l in ipairs(wrap(p, size, bound, nonSpaceWrap)) do
                lines[#lines + 1] = l
            end
        end
    else
        lines = paragraphs
    end

    local widest = 0
    for _, l in ipairs(lines) do widest = max(widest, M.lineWidth(l, size)) end

    local rendered = widest
    if bound and bound > 0 and rendered > bound then rendered = bound end

    return rendered, #lines * lh, #lines
end

--- Narrowest box that renders the text without cutting glyphs.
-- Wrap off: the whole longest line. Wrap on: the widest single word, because the
-- client only breaks inside a word when non-space wrap is enabled — a one-glyph
-- label in a box narrower than the glyph is clipped, not re-flowed.
-- @param text string
-- @param size number
-- @param wordWrap bool
-- @param nonSpaceWrap bool
-- @return number
function M.minWidth(text, size, wordWrap, nonSpaceWrap)
    local clean = M.strip(text)
    if clean == "" then return 0 end
    if not wordWrap then return M.unbounded(clean, size) end
    if nonSpaceWrap then return 0 end
    local widest = 0
    for word in clean:gmatch("%S+") do widest = max(widest, M.lineWidth(word, size)) end
    return widest
end

--- Unbounded width of text: what it would occupy with no layout constraint.
-- @param text string
-- @param size number
-- @return number
function M.unbounded(text, size)
    local clean = M.strip(text)
    if clean == "" then return 0 end
    local widest = 0
    for _, p in ipairs(splitParagraphs(clean)) do
        widest = max(widest, M.lineWidth(p, size))
    end
    return widest
end

return M
