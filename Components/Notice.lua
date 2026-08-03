--- Shows a dismissible notice modal for a one-way message.
-- Use this instead of printing to chat for anything the user needs to acknowledge.
-- @param props table  { title, message, tone, confirmText, w }
--   tone: "warning" for a blocked but expected action (deleting a built-in theme),
--         "danger" for something that actually went wrong, "success" for a completed
--         action, nil for neutral information
-- @return table  Modal handle
function SuuUI.Components.Notice(props)
    local modal = SuuUI.Components.Modal({
        title          = props.title,
        message        = props.message,
        confirmText    = props.confirmText or "OK",
        confirmVariant = props.tone,
        dismissOnly    = true,
        autoDestroy    = true,
        w              = props.w,
    })
    modal:Show()
    return modal
end
