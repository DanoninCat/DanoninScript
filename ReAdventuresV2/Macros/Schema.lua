-- Re Adventures V2 - Macro schema helpers

local Schema = {}

Schema.NAME = "re-adventures-macro"
Schema.VERSION = 2

Schema.EVENTS = {
    PLACE_DETECTED = true,
    UPGRADE_DETECTED = true,
    UNIT_REMOVED = true,
    WAVE_CHANGED = true,
    BASE_LIFE_CHANGED = true,
    MATCH_PHASE_CHANGED = true,
}

function Schema.validate(macro)
    if type(macro) ~= "table" then
        return false, "macro must be a table"
    end

    if macro.schema ~= Schema.NAME then
        return false, "unsupported macro schema"
    end

    if macro.version ~= Schema.VERSION then
        return false, "unsupported macro version"
    end

    if type(macro.map) ~= "table" then
        return false, "macro map metadata is missing"
    end

    if type(macro.events) ~= "table" then
        return false, "macro events are missing"
    end

    if type(macro.snapshots) ~= "table" then
        return false, "macro snapshots are missing"
    end

    for index, event in ipairs(macro.events) do
        if type(event) ~= "table" then
            return false, "invalid event at index " .. tostring(index)
        end

        if type(event.type) ~= "string" then
            return false, "event type missing at index " .. tostring(index)
        end

        if type(event.t) ~= "number" then
            return false, "event time missing at index " .. tostring(index)
        end
    end

    return true
end

function Schema.describe(macro)
    local ok, err = Schema.validate(macro)

    if not ok then
        return {
            valid = false,
            error = err,
        }
    end

    return {
        valid = true,
        schema = macro.schema,
        version = macro.version,
        name = macro.name,
        libraryId = macro.libraryId,
        area = macro.map and macro.map.area,
        level = macro.map and macro.map.level,
        duration = macro.duration,
        eventCount = #macro.events,
        snapshotCount = #macro.snapshots,
    }
end

return Schema
