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

-- The faces an enUS client ships. Restored on every setup so a test that adds one does
-- not leak it into the next.
local DEFAULT_FACES = {
    ["fonts/frizqt__.ttf"] = { widthRatio = 0.5,  heightRatio = 1.25 },
    ["fonts/arialn.ttf"]   = { widthRatio = 0.38, heightRatio = 1.25 },
    ["fonts/morpheus.ttf"] = { widthRatio = 0.7,  heightRatio = 1.5  },
    ["fonts/skurri.ttf"]   = { widthRatio = 0.55, heightRatio = 1.25 },
}

--- Per-face metrics, keyed by normalised path. A face swap changes glyph advance
--- without changing point size, so without this a spec asserting a font change would
--- measure identically before and after and pass for the wrong reason.
---
--- This table is also the set of faces the client can load: SetFont rejects anything
--- absent from it, which is how the real client reports a missing font file and the
--- only way font path validation can be tested.
M.faces = {}

--- Normalises a font path the way the client does: either slash, any case.
-- @param path string
-- @return string
function M.normalise(path)
    if type(path) ~= "string" then return "" end
    return (path:gsub("\\", "/"):lower())
end

--- Restores the default face table. Called on every harness setup.
function M.resetFaces()
    M.faces = {}
    for path, ratios in pairs(DEFAULT_FACES) do
        M.faces[path] = { widthRatio = ratios.widthRatio, heightRatio = ratios.heightRatio }
    end
end

--- Makes a font path loadable, as a locale client or a media addon does.
-- @param path string
-- @param widthRatio number   Optional glyph advance ratio
-- @param heightRatio number  Optional line height ratio
function M.addFace(path, widthRatio, heightRatio)
    M.faces[M.normalise(path)] = {
        widthRatio  = widthRatio  or M.widthRatio,
        heightRatio = heightRatio or M.heightRatio,
    }
end

M.resetFaces()

--- Whether the client can load a font path.
-- @param path string
-- @return bool
function M.hasFace(path)
    return M.faces[M.normalise(path)] ~= nil
end

--- Metric ratios for a face, defaulting to the base model for an unknown path.
-- @param path string
-- @return number, number  widthRatio, heightRatio
function M.ratios(path)
    local face = M.faces[M.normalise(path)]
    if not face then return M.widthRatio, M.heightRatio end
    return face.widthRatio or M.widthRatio, face.heightRatio or M.heightRatio
end

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
-- @param path string  Optional font path; omitted uses the base metric model
-- @return number
function M.lineWidth(line, size, path)
    local wr = M.ratios(path)
    return ceil(#line * (size or M.defaultSize) * wr)
end

--- Height of one line at a point size.
-- @param size number
-- @param path string  Optional font path
-- @return number
function M.lineHeight(size, path)
    local _, hr = M.ratios(path)
    return ceil((size or M.defaultSize) * hr)
end

local function splitParagraphs(text)
    local out = {}
    for chunk in (text .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = chunk end
    if #out > 1 and out[#out] == "" then out[#out] = nil end
    if #out == 0 then out[1] = "" end
    return out
end

local function wrap(line, size, bound, breakWords, path)
    local perChar = (size or M.defaultSize) * M.ratios(path)
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
-- @param path string     Optional font path
-- @return number, number, number  renderedWidth, height, lineCount
function M.measure(text, size, wordWrap, bound, nonSpaceWrap, path)
    local clean = M.strip(text)
    size = size or M.defaultSize
    local lh = M.lineHeight(size, path)

    if clean == "" then return 0, 0, 0 end

    local paragraphs = splitParagraphs(clean)
    local lines = {}

    if wordWrap and bound and bound > 0 then
        for _, p in ipairs(paragraphs) do
            for _, l in ipairs(wrap(p, size, bound, nonSpaceWrap, path)) do
                lines[#lines + 1] = l
            end
        end
    else
        lines = paragraphs
    end

    local widest = 0
    for _, l in ipairs(lines) do widest = max(widest, M.lineWidth(l, size, path)) end

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
-- @param path string  Optional font path
-- @return number
function M.minWidth(text, size, wordWrap, nonSpaceWrap, path)
    local clean = M.strip(text)
    if clean == "" then return 0 end
    if not wordWrap then return M.unbounded(clean, size, path) end
    if nonSpaceWrap then return 0 end
    local widest = 0
    for word in clean:gmatch("%S+") do
        widest = max(widest, M.lineWidth(word, size, path))
    end
    return widest
end

--- Unbounded width of text: what it would occupy with no layout constraint.
-- @param text string
-- @param size number
-- @param path string  Optional font path
-- @return number
function M.unbounded(text, size, path)
    local clean = M.strip(text)
    if clean == "" then return 0 end
    local widest = 0
    for _, p in ipairs(splitParagraphs(clean)) do
        widest = max(widest, M.lineWidth(p, size, path))
    end
    return widest
end

return M
