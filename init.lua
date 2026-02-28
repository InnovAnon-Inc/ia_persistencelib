-- ia_persistencelib/init.lua

--assert(fakelib ~= nil)
--
--persistencelib = {}
--
---- Helper to serialize inventory lists including layout metadata
--local function serialize_inventory(inv)
--    local inv_data = {}
--    local lists = inv:get_lists()
--
--    for listname, _ in pairs(lists) do
--        inv_data[listname] = {
--            size = inv:get_size(listname),
--            width = inv:get_width(listname),
--            items = {}
--        }
--
--        -- Store each stack as a string
--        for i = 1, inv_data[listname].size do
--            local stack = inv:get_stack(listname, i)
--            inv_data[listname].items[i] = stack:to_string()
--        end
--    end
--    return inv_data
--end
--
---- Serializes a fakelib player's full state
---- Includes identity, physical state, inventory, metadata, and visual properties.
--function persistencelib.get_state(fake_player)
--    -- Ensure we are working with a valid bridged object or proxy
--    assert(fake_player ~= nil, "[persistencelib] Cannot get state of nil player")
--    assert(fake_player.get_player_name ~= nil, "[persistencelib] Object is not a valid player proxy")
--
--    return {
--        -- Identity & Physics
--        name        = fake_player:get_player_name(),
--        pos         = fake_player:get_pos(),
--
--        -- Perspective
--        pitch       = fake_player:get_look_vertical(),
--        yaw         = fake_player:get_look_horizontal(),
--
--        -- Inventory & Equipment (Now with width/size safety)
--        inventory   = serialize_inventory(fake_player:get_inventory()),
--        wield_index = fake_player:get_wield_index(),
--        wield_list  = fake_player:get_wield_list(),
--
--        -- Metadata
--        meta        = fake_player:get_meta():to_table(),
--
--        -- Volatile Input
--        controls    = fake_player:get_player_control(),
--
--        -- Visual Properties (Textures, Mesh, etc.)
--        -- This relies on the 'properties' cache in the fakelib bridge
--        properties  = fake_player.data and fake_player.data.properties or {}
--    }
--end
--
---- Restores state into a fakelib player object
--function persistencelib.apply_state(fake_player, state_data)
--    if not fake_player or not state_data then return end
--
--    -- 1. Restore Metadata (Priority: Attributes might modify behaviors)
--    if state_data.meta then
--        fake_player:get_meta():from_table(state_data.meta)
--    end
--
--    -- 2. Restore Inventory (With Width Support)
--    local inv = fake_player:get_inventory()
--    if state_data.inventory then
--        for listname, data in pairs(state_data.inventory) do
--            -- Reconstruct list structure
--            inv:set_size(listname, data.size or #data.items)
--            inv:set_width(listname, data.width or 0)
--
--            -- Fill stacks
--            for i, stack_str in ipairs(data.items) do
--                inv:set_stack(listname, i, ItemStack(stack_str))
--            end
--        end
--    end
--
--    -- 3. Restore Physical State (Now correctly bridged to ia_fake_player)
--    if state_data.pos   then fake_player:set_pos(state_data.pos) end
--    if state_data.pitch then fake_player:set_look_vertical(state_data.pitch) end
--    if state_data.yaw   then fake_player:set_look_horizontal(state_data.yaw) end
--
--    -- 4. Restore Internal State (Relies on the 'data' trapdoor in the bridge)
--    if state_data.wield_index then
--        fake_player.data.wield_index = state_data.wield_index
--    end
--    if state_data.wield_list then
--        fake_player.data.wield_list = state_data.wield_list
--    end
--
--    -- 5. Restore Visual Properties
--    -- This ensures that persisted textures (from 3d_armor/skins) 
--    -- overwrite the engine's default placeholders immediately.
--    if state_data.properties and next(state_data.properties) then
--        fake_player:set_properties(state_data.properties)
--    end
--end












-- ia_persistencelib/init.lua

-- Ensure critical dependencies are present for logging and logic
assert(fakelib ~= nil)
assert(futil   ~= nil)

persistencelib = {}

---------------------------
-- 1. Internal Helpers
---------------------------

-- Helper to resolve internal data storage (Handles both Proxy and Bridged Entity)
-- This ensures we can access internal state (wield_index, etc.) even after bridging.
local function get_internal_data(player)
    if not player then return nil end
    -- Direct access if it's the fakelib proxy
    if player.data then return player.data end
    -- Access via the bridge if it's the LuaEntity table
    if player.fake_player and player.fake_player.data then
        return player.fake_player.data
    end
    return nil
end

-- Helper to serialize inventory lists including layout metadata
local function serialize_inventory(inv)
    if not inv then
        minetest.log("[persistencelib] serialize_inventory: inv is nil")
        return {}
    end

    local inv_data = {}
    local lists = inv:get_lists()

    for listname, _ in pairs(lists) do
        inv_data[listname] = {
            size = inv:get_size(listname),
            width = inv:get_width(listname),
            items = {}
        }

        -- Store each stack as a string (ItemStack objects cannot be serialized directly)
        for i = 1, inv_data[listname].size do
            local stack = inv:get_stack(listname, i)
            inv_data[listname].items[i] = stack:to_string()
        end
    end
    return inv_data
end

---------------------------
-- 2. Public API
---------------------------

-- Serializes a fakelib player's full state
-- Includes identity, physical state, inventory, metadata, and visual properties.
function persistencelib.get_state(fake_player)
    -- CHANGE: Hardened assertions and added lifecycle logging
    assert(fake_player ~= nil, "[persistencelib] Cannot get state of nil player")
    assert(fake_player.get_player_name ~= nil, "[persistencelib] Object is not a valid player proxy")

    local name = fake_player:get_player_name()
    minetest.log("[persistencelib] get_state: Gathering state for: %s", name)

    local internal = get_internal_data(fake_player)
    if not internal then
        minetest.log("[persistencelib] get_state: No internal data found for: %s", name)
    end

    local state = {
        -- Identity & Physics
        name        = name,
        pos         = fake_player:get_pos(),

        -- Perspective
        pitch       = fake_player:get_look_vertical(),
        yaw         = fake_player:get_look_horizontal(),

        -- Inventory & Equipment
        inventory   = serialize_inventory(fake_player:get_inventory()),
        wield_index = fake_player:get_wield_index(),
        wield_list  = fake_player:get_wield_list(),

        -- Metadata
        meta        = fake_player:get_meta():to_table(),

        -- Volatile Input
        controls    = fake_player:get_player_control(),

        -- Visual Properties (Textures, Mesh, etc.)
        -- CHANGE: Fetching directly from engine to ensure we capture mod-applied changes
        properties  = fake_player:get_properties()
    }

    -- Validation: Ensure the table is serializable (no hidden userdata/functions)
    local test_ser = minetest.serialize(state)
    if not test_ser then
        minetest.log("[persistencelib] get_state: FAILED to serialize state for %s!", name)
    else
        minetest.log("[persistencelib] get_state: Captured %d bytes for %s", #test_ser, name)
    end

    return state
end

-- Restores state into a fakelib player object
function persistencelib.apply_state(fake_player, state_data)
	minetest.log('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')
    -- CHANGE: Added defensive checks and application logging
    if not fake_player then
        minetest.log("[persistencelib] apply_state: fake_player is nil")
        return
    end
    if not state_data then
        minetest.log("[persistencelib] apply_state: state_data is nil")
        return
    end

    local name = fake_player:get_player_name() or "unknown"
    minetest.log("[persistencelib] apply_state: Restoring state for: %s", name)

    -- 1. Restore Metadata (Priority: Attributes might modify behaviors)
    if state_data.meta then
        fake_player:get_meta():from_table(state_data.meta)
    end

    -- 2. Restore Inventory (With Width Support)
    local inv = fake_player:get_inventory()
    if state_data.inventory and inv then
        for listname, data in pairs(state_data.inventory) do
            inv:set_size(listname, data.size or #data.items)
            inv:set_width(listname, data.width or 0)

            for i, stack_str in ipairs(data.items) do
                inv:set_stack(listname, i, ItemStack(stack_str))
            end
        end
    end

    -- 3. Restore Physical State
    if state_data.pos   then fake_player:set_pos(state_data.pos) end
    if state_data.pitch then fake_player:set_look_vertical(state_data.pitch) end
    if state_data.yaw   then fake_player:set_look_horizontal(state_data.yaw) end

    -- 4. Restore Internal State (Wielding)
    -- CHANGE: Uses helper to correctly resolve the internal data table
    local internal = get_internal_data(fake_player)
    if internal then
        if state_data.wield_index then internal.wield_index = state_data.wield_index end
        if state_data.wield_list  then internal.wield_list  = state_data.wield_list  end
    end

    -- 5. Restore Visual Properties
    if state_data.properties and next(state_data.properties) then
        fake_player:set_properties(state_data.properties)
        minetest.log("[persistencelib] apply_state: Visual properties applied for: %s", name)
    end

    minetest.log("[persistencelib] apply_state: Complete for: %s", name)
end
