local label_name = "beacon-count"

---@param list string[]
---@return table<string,true>
local function to_map(list)
    local map = {}
    for _, key in ipairs(list) do
        map[key] = true
    end
    return map
end

local crafting_machines = { "assembling-machine", "furnace", "rocket-silo" }
local is_crafting_machine = to_map(crafting_machines)

---@type table<string,LuaEntityPrototype>
local beacon_protos

---@param entity LuaEntity
---@return string @type for this entity or the entity contained in the ghost
local function get_type(entity)
    return entity.type == "entity-ghost" and entity.ghost_type or entity.type
end

---@param entity LuaEntity
---@return string @prototype for this entity or the entity contained in the ghost
local function get_prototype(entity)
    return entity.type == "entity-ghost" and entity.ghost_prototype or entity.prototype
end

---@param player LuaPlayer
local function update_beacon_count(player)
    ---@type LuaGuiElement
    local label = player.gui.top[label_name]
    if not label then
        label = player.gui.top.add { type = "label", name = label_name, visible = false }
    end
    label.visible = false

    if player.mod_settings["rsbc-only-alt-mode"].value and not player.game_view_settings.show_entity_info then
        return
    end

    local machine = player.selected
    if not machine or not is_crafting_machine[get_type(machine)] then
        return
    end

    beacon_protos = beacon_protos or game.get_filtered_entity_prototypes { { filter = "type", type = "beacon" } }

    local normalized_count = 0
    local bounding_box = machine.bounding_box
    for _, beacon_proto in pairs(beacon_protos) do
        local supply_area_distance = beacon_proto.supply_area_distance
        local search_area = {
            {
                bounding_box.left_top.x - supply_area_distance,
                bounding_box.left_top.y - supply_area_distance,
            },
            {
                bounding_box.right_bottom.x + supply_area_distance,
                bounding_box.right_bottom.y + supply_area_distance,
            },
        }
        -- Count number of beacons in range
        local beacons = player.surface.count_entities_filtered {
            area = search_area,
            name = beacon_proto.name,
            to_be_deconstructed = false,
        } + player.surface.count_entities_filtered {
            area = search_area,
            ghost_name = beacon_proto.name,
        }

        normalized_count = normalized_count + beacons * beacon_proto.module_inventory_size * beacon_proto.distribution_effectivity
    end

    local ref_beacon = game.entity_prototypes["beacon"]
    normalized_count = normalized_count / ref_beacon.distribution_effectivity / ref_beacon.module_inventory_size

    if normalized_count == 0 then
        return
    end

    label.caption = { "rsbc-message.label-text", ref_beacon.name, normalized_count }
    label.visible = true
end

script.on_event(defines.events.on_selected_entity_changed,
    ---@param event on_selected_entity_changed
    function(event)
        local player = game.get_player(event.player_index)
        update_beacon_count(player)
    end)

---@param position MapPosition
---@param prototype LuaEntityPrototype
local function handle_beacon_built_destroyed_impl(position, prototype)
    local radius = prototype.supply_area_distance
    for _, player in pairs(game.players) do
        ---@type LuaEntity
        local machine = player.selected
        if machine and is_crafting_machine[machine.type] then
            local box = machine.bounding_box
            if position.x + radius >= box.left_top.x and
                position.x - radius <= box.right_bottom.x and
                position.y + radius >= box.left_top.y and
                position.y - radius <= box.right_bottom.y then
                update_beacon_count(player)
            end
        end
    end
end

---@param entity LuaEntity
local function handle_beacon_built_destroyed(entity)
    handle_beacon_built_destroyed_impl(entity.position, get_prototype(entity))
end

---@type EventFilter[]
local beacon_filter = {
    { filter = "type", type = "beacon" },
    { mode = "or", filter = "ghost_type", type = "beacon" },
}

---@type table<uint64,{position:MapPosition,prototype:LuaEntityPrototype}>
local to_be_destroyed = {}

script.on_event(defines.events.on_built_entity,
    ---@param event on_built_entity
    function(event)
        handle_beacon_built_destroyed(event.created_entity)
    end, beacon_filter)
script.on_event(defines.events.on_player_mined_entity,
    ---@param event on_player_mined_entity
    function(event)
        to_be_destroyed[script.register_on_entity_destroyed(event.entity)] = {
            position = event.entity.position,
            prototype = get_prototype(event.entity),
        }
    end, beacon_filter)
script.on_event(defines.events.on_pre_ghost_deconstructed,
    ---@param event on_pre_ghost_deconstructed
    function(event)
        to_be_destroyed[script.register_on_entity_destroyed(event.ghost)] = {
            position = event.ghost.position,
            prototype = event.ghost.ghost_prototype,
        }
    end, beacon_filter)

script.on_event(defines.events.on_marked_for_deconstruction,
    ---@param event on_marked_for_deconstruction
    function(event)
        handle_beacon_built_destroyed(event.entity)
    end, beacon_filter)
script.on_event(defines.events.on_cancelled_deconstruction,
    ---@param event on_cancelled_deconstruction
    function(event)
        handle_beacon_built_destroyed(event.entity)
    end, beacon_filter)

script.on_event(defines.events.on_player_rotated_entity,
    ---@param event on_player_rotated_entity
    function(event)
        if event.entity.type == "beacon" or is_crafting_machine[get_type(event.entity)] then
            for _, player in pairs(game.players) do
                ---@type LuaEntity
                local machine = player.selected
                if machine and is_crafting_machine[machine.type] then
                    update_beacon_count(player)
                end
            end
        end
    end)

script.on_event(defines.events.on_entity_destroyed,
    ---@param event on_entity_destroyed
    function(event)
        local info = to_be_destroyed[event.registration_number]
        if info then
            to_be_destroyed[event.registration_number] = nil
            handle_beacon_built_destroyed_impl(info.position, info.prototype)
        end
    end)

script.on_event(defines.events.on_player_toggled_alt_mode,
    ---@param event on_player_toggled_alt_mode
    function(event)
        ---@type LuaPlayer
        local player = game.players[event.player_index]
        if player.mod_settings["rsbc-only-alt-mode"].value then
            update_beacon_count(player)
        end
    end)
