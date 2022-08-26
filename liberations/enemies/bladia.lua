local EnemySelection = require("scripts/ezlibs-custom/nebulous-liberations/liberations/enemy_selection")
local EnemyHelpers = require("scripts/ezlibs-custom/nebulous-liberations/liberations/enemy_helpers")
local Direction = require("scripts/libs/direction")

local Bladia = {}

--Setup ranked health and damage
local rank = 1
local mob_health = {200, 230, 230, 300, 340, 400}
local mob_damage = {50, 80, 120, 160, 200, 250}
local mob_ranks = {1, 2, 3, 4, 5, 6}

function Bladia:new(instance, position, direction, local_rank)
  if local_rank ~= nil then rank = tonumber(local_rank) end
  local bladia = {
    instance = instance,
    id = nil,
    health = mob_health[rank],
    max_health = mob_health[rank],
    damage = mob_damage[rank],
    rank = mob_ranks[rank],
    x = math.floor(position.x),
    y = math.floor(position.y),
    z = math.floor(position.z),
    encounter = "/server/assets/NebuLibsAssets/encounters/Bladia.zip",
    selection = EnemySelection:new(instance),
    is_engaged = false
  }

  setmetatable(bladia, self)
  self.__index = self

  local shape = {
    { 1 }
  }

  bladia.selection:set_shape(shape, 0, -1)
  bladia:spawn(direction)

  return bladia
end

function Bladia:spawn(direction)
  self.id = Net.create_bot({
    texture_path = "/server/assets/NebuLibsAssets/bots/bladia.png",
    animation_path = "/server/assets/NebuLibsAssets/bots/bladia.animation",
    area_id = self.instance.area_id,
    direction = direction,
    warp_in = false,
    x = self.x + .5,
    y = self.y + .5,
    z = self.z
  })
  Net.set_bot_minimap_color(self.id, EnemyHelpers.boss_minimap_color)
end

function Bladia:get_death_message()
  return "Gyaaaahh!!"
end

function Bladia:do_first_encounter_banter(player_id)
  local co = coroutine.create(function()
    self.is_engaged = true
  end)
  return Async.promisify(co)
end

function Bladia:take_turn()
  local co = coroutine.create(function()
    local player = EnemyHelpers.find_closest_player_session(self.instance, self)
    if not player then return end --No player. Don't bother.
    local distance = EnemyHelpers.chebyshev_tile_distance(self, player.player.x, player.player.y, player.player.z)
    if distance > 5 then return end --Player too far. Don't bother.
    self.selection:move(player.player, Direction.None)
    local targetx = player.player.x
    local targety = player.player.y
    local original_coordinates = {x=targetx, y=targety, z=player.player.z}
    local tile_to_check = Net.get_tile(self.instance.area_id, targetx, targety, player.player.z)

    --Helper function to return if we can move to this tile or not
    local function coordinate_check(checkx, checky)
      if checkx == original_coordinates.x and checky == original_coordinates.y then
        return true
      end
      return false
    end

    local function panel_check(checkx, checky)
      local spare_object = self.instance:get_panel_at(checkx, checky, player.player.z)
      if not spare_object then return false end --No panel, return false, can warp
      if EnemyHelpers.can_move_to(self.instance, spare_object.x, spare_object.y, spare_object.z) then
        return false --can warp
      end
      return true --cannot warp
    end

    if not tile_to_check then return end --No tile, return.
    --Check initial tile location.
    if tile_to_check.gid == 0 or coordinate_check(targetx, targety) or panel_check(targetx, targety) then
      targetx = original_coordinates.x
      targety = original_coordinates.y + 1
    end

    --Reacquire the tile with new coordinates.
    tile_to_check = Net.get_tile(self.instance.area_id, targetx, targety, player.player.z)
    if not tile_to_check then return end --No tile, return.
    if tile_to_check.gid == 0 or coordinate_check(targetx, targety) or panel_check(targetx, targety) then
      targetx = original_coordinates.x
      targety = original_coordinates.y - 1
    end

    --Reacquire the tile with new coordinates.
    tile_to_check = Net.get_tile(self.instance.area_id, targetx, targety, player.player.z)
    if not tile_to_check then return end --No tile, return.
    if tile_to_check.gid == 0 or coordinate_check(targetx, targety) or panel_check(targetx, targety) then
      targety = original_coordinates.y
      targetx = original_coordinates.x + 1
    end

    --Reacquire the tile with new coordinates.
    tile_to_check = Net.get_tile(self.instance.area_id, targetx, targety, player.player.z)
    if not tile_to_check then return end --No tile, return.
    if tile_to_check.gid == 0 or coordinate_check(targetx, targety) or panel_check(targetx, targety) then
      targety = original_coordinates.y
      targetx = original_coordinates.x - 1
    end

    tile_to_check = Net.get_tile(self.instance.area_id, targetx, targety, player.player.z)
    if not tile_to_check then return end --No tile, return.
    if tile_to_check.gid == 0 or coordinate_check(targetx, targety) or panel_check(targetx, targety) then
      return --We can't move anywhere safe. Return.
    end

    --Get the direction to face.
    local target_direction = Direction.diagonal_from_offset((player.player.x - targetx), (player.player.y - targety))

    --Grab example tiles from which to generate a new dark panel.
    local example_panel = self.instance:get_panel_at(self.x, self.y, self.z)
    local example_collision = Net.get_object_by_id(self.instance.area_id, example_panel.visual_object_id)

    if not example_panel or not example_collision then return end --If they don't exist (SOMEHOW) then return.

    Async.await(EnemyHelpers.move(self.instance, self, targetx, targety, player.player.z, target_direction))
    if not self.instance:get_panel_at(targetx, targety, player.player.z) then
      local x = math.floor(targetx) + 1
      local y = math.floor(targety) + 1
      local z = math.floor(player.player.z) + 1

      --Generate the data for the Collision
      local new_panel = {
        name="", type="Dark Panel", visible=true,
        x=x-1, y=y-1, z=z-1, width=example_collision.width, height=example_collision.height,
        data={type="tile", gid=Net.get_tileset(self.instance.area_id, "/server/assets/tiles/Liberation Collision.tsx").first_gid},
        custom_properties={}
      }

      --Generate an ID for the Collision
      new_panel.id = Net.create_object(self.instance.area_id, new_panel)

      --Generate the data for the visual panel
      local visual_panel = {
        name="", type="Dark Panel", visible=true,
        x=x-1, y=y-1, z=z-1, width=example_panel.width, height=example_panel.height,
        data={type="tile", gid=self.instance.BASIC_PANEL_GID_LIST[math.random(#self.instance.BASIC_PANEL_GID_LIST)]},
        custom_properties={}
      }

      --Generate an ID for the visual panel
      visual_panel.id = Net.create_object(self.instance.area_id, visual_panel)

      --Insert the data and the Collision
      new_panel.visual_object_id = visual_panel.id
      new_panel.visual_gid = visual_panel.data.gid
      self.instance.panels[z][y][x] = new_panel

      --Hold for half a second to spawn the tile.
      Async.await(Async.sleep(.5))
    end
    --Indicate the attack range.
    self.selection:indicate()
    --Attack visually.
    EnemyHelpers.play_attack_animation(self)
    --Hurt the player for the set damage
    player:hurt(self.damage)
    --Sleep long enough to let the player ruminate on their mistakes.
    Async.await(Async.sleep(.7))
    --Remove the indicator.
    self.selection:remove_indicators()
  end)

  return Async.promisify(co)
end

return Bladia
