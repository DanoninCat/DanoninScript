-- Re Adventures V2 - Macros UI contract
-- This file describes the controls to add to the EXISTING Loader UI.
-- It does not create a ScreenGui/window itself.

return {
    id = "macros",
    title = "Macros",

    controls = {
        {
            id = "macro_name",
            type = "input",
            label = "Macro Name",
            placeholder = "Example: Namek Story",
        },
        {
            id = "record_macro",
            type = "button",
            label = "Record Macro",
            action = "StartRecording",
        },
        {
            id = "stop_save_macro",
            type = "button",
            label = "Stop & Save",
            action = "StopRecording",
        },
        {
            id = "macro_list",
            type = "dropdown",
            label = "Saved Macros",
            source = "ListMacros",
            selectAction = "SelectMacro",
            valueKey = "id",
            textKey = "name",
        },
        {
            id = "rename_macro",
            type = "input_action",
            label = "Rename Macro",
            action = "RenameMacro",
        },
        {
            id = "delete_macro",
            type = "button",
            label = "Delete Macro",
            action = "DeleteMacro",
        },
        {
            id = "import_macro",
            type = "multiline_action",
            label = "Import Macro",
            action = "ImportMacro",
        },
        {
            id = "export_macro",
            type = "button",
            label = "Export Selected Macro",
            action = "ExportSelectedMacro",
        },
        {
            id = "macro_info",
            type = "status",
            label = "Macro Info",
            source = "GetMacrosSummary",
        },
    },
}
