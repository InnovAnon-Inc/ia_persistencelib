--assert(futil ~= nil)
assert(fakelib ~= nil)

persistencelib = {}

-- Helper to serialize inventory lists including layout metadata
local function serialize_inventory(inv)
    local inv_data = {}
    local lists = inv:get_lists()

    for listname, _ in pairs(lists) do
        inv_data[listname] = {
            size = inv:get_size(listname),
            width = inv:get_width(listname),
            items = {}
        }

        -- Store each stack as a string
        for i = 1, inv_data[listname].size do
            local stack = inv:get_stack(listname, i)
            inv_data[listname].items[i] = stack:to_string()
        end
    end
    return inv_data
end

-- Serializes a fakelib player's full state
function persistencelib.get_state(fake_player)
    if not fake_player then return nil end

    return {
        -- Identity & Physics
        name        = fake_player:get_player_name(),
        pos         = fake_player:get_pos(),

        -- Perspective
        pitch       = fake_player:get_look_vertical(),
        yaw         = fake_player:get_look_horizontal(),

        -- Inventory & Equipment (Now with width/size safety)
        inventory   = serialize_inventory(fake_player:get_inventory()),
        wield_index = fake_player:get_wield_index(),
        wield_list  = fake_player:get_wield_list(),

        -- Metadata
        meta        = fake_player:get_meta():to_table(),

        -- Volatile Input
        controls    = fake_player:get_player_control()
    }
end

-- Restores state into a fakelib player object
function persistencelib.apply_state(fake_player, state_data)
    if not fake_player or not state_data then return end

    -- 1. Restore Metadata (Priority: Attributes might modify behaviors)
    if state_data.meta then
        fake_player:get_meta():from_table(state_data.meta)
    end

    -- 2. Restore Inventory (With Width Support)
    local inv = fake_player:get_inventory()
    if state_data.inventory then
        for listname, data in pairs(state_data.inventory) do
            -- Reconstruct list structure
            inv:set_size(listname, data.size or #data.items)
            inv:set_width(listname, data.width or 0)

            -- Fill stacks
            for i, stack_str in ipairs(data.items) do
                inv:set_stack(listname, i, ItemStack(stack_str))
            end
        end
    end

    -- 3. Restore Position & Perspective
    if state_data.pos   then fake_player:set_pos(state_data.pos) end
    if state_data.pitch then fake_player:set_look_vertical(state_data.pitch) end
    if state_data.yaw   then fake_player:set_look_horizontal(state_data.yaw) end

    -- 4. Restore Wield State
    if state_data.wield_index then
        fake_player.data.wield_index = state_data.wield_index
    end
    if state_data.wield_list then
        fake_player.data.wield_list = state_data.wield_list
    end
end
