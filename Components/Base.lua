local pairs = pairs
local S = SuuUI.UISignals

-- The six accessors every component handle repeats verbatim, plus SetSize.
-- SetSize deliberately does not emit SIZE_CHANGED: that comes from the frame's own
-- OnSizeChanged hook so an explicit resize and a layout-driven one behave identically.
local builders = {
    GetWidth  = function(field) return function(self) return self[field]:GetWidth()  end end,
    GetHeight = function(field) return function(self) return self[field]:GetHeight() end end,
    IsShown   = function(field) return function(self) return self[field]:IsShown()   end end,
    GetFrame  = function(field) return function(self) return self[field]            end end,
    SetSize   = function(field) return function(self, w, h) self[field]:SetSize(w, h) end end,
    Show      = function(field)
        return function(self)
            self[field]:Show()
            S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, true)
        end
    end,
    Hide      = function(field)
        return function(self)
            self[field]:Hide()
            S:Emit(self, S.SIGNALS.VISIBILITY_CHANGED, false)
        end
    end,
}

--- Installs the standard handle accessors onto a component metatable.
-- Only fills in methods the metatable does not already define, so a component
-- keeping a custom SetSize/Show/Hide is untouched.
-- @param meta table   the component's metatable
-- @param field string the handle field holding the widget (default "_f")
-- @return table  the metatable, for chaining
function SuuUI.Components.InstallBase(meta, field)
    field = field or "_f"
    for name, build in pairs(builders) do
        if meta[name] == nil then meta[name] = build(field) end
    end
    return meta
end
