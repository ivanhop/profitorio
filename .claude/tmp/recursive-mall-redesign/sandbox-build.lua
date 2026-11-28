-- Trims a fresh copy of the colin save down to the mall on logistic network 18 ("mall sandbox").
-- Run on a fresh instance (NOT the harness), from the repo root:
--   python tools/check/probe_client.py --host 127.0.0.1 --port 2712N --password probe < .claude/tmp/recursive-mall-redesign/sandbox-build.lua
-- It writes script-output/sandbox_*.txt and saves <write-data>/saves/mall-sandbox.zip.
-- Re-run against a newer save: check KEEP (the mall box) and EXTRA (spare warehouse spots) first.
-- RULES: the client flattens each block to one line, so no trailing "--" comments on code lines.
/silent-command
game.tick_paused = true
SB = {}
SB.s = game.surfaces.nauvis
SB.TRIGGER = {-207.5, 122.5}
SB.MASK_CC = {-223.5, 106.5}
SB.WAREHOUSE = {-208, 135}
SB.TARGET = "kr-research-server"
SB.BATCH = 50
SB.BATCHES = 10
SB.FACTOR = 10
SB.NEAR_SLOTS = 80
-- Everything in this box is kept except belts and stray chests (a belt loop runs at x = -206.5).
SB.KEEP = {{-249, 100}, {-204.9, 153}}
SB.SKIP_TYPES = {["transport-belt"] = true, ["underground-belt"] = true, ["splitter"] = true, ["container"] = true}
-- Spare storage warehouses, nearest first; free once the speed-module block east of the mall is gone.
SB.EXTRA = {}
for _, x in pairs({-202, -196, -190}) do for _, y in pairs({135, 129, 141, 123, 147, 117}) do SB.EXTRA[#SB.EXTRA + 1] = {x, y} end end
function SB.at(pos, name) return SB.s.find_entities_filtered{position = pos, radius = 0.6, name = name}[1] end
function SB.net() return SB.at(SB.TRIGGER, "requester-chest").logistic_network end
function SB.key(name, q) return name .. "/" .. (q or "normal") end
function SB.contents()
  local t = {}
  for _, it in pairs(SB.net().get_contents()) do t[SB.key(it.name, it.quality)] = it.count end
  return t
end
function SB.dump(file, t)
  local o = {}
  for k, v in pairs(t) do o[#o + 1] = k .. "=" .. v end
  table.sort(o)
  helpers.write_file(file, table.concat(o, "\n"), false, 0)
end
function SB.kept(e)
  local p = e.position
  if p.x < SB.KEEP[1][1] or p.x > SB.KEEP[2][1] or p.y < SB.KEEP[1][2] or p.y > SB.KEEP[2][2] then return false end
  return not SB.SKIP_TYPES[e.type]
end
SB.before = SB.contents()
SB.dump("sandbox_net18_before.txt", SB.before)
local n = SB.net()
SB.robots_before = n.all_logistic_robots .. " logistic, " .. n.all_construction_robots .. " construction, " .. #n.cells .. " roboports"
rcon.print("recorded network 18: " .. SB.robots_before)
---
/silent-command
-- What the stock must cover: the mall's recipes (the save's own mask), and BATCHES x 50 servers expanded down to non-mask items.
local cb = SB.at(SB.MASK_CC, "constant-combinator").get_control_behavior()
local mask = {}
for _, sec in pairs(cb.sections) do for _, f in pairs(sec.filters) do if f.value then mask[f.value.name] = true end end end
SB.uses = {}
for m in pairs(mask) do
  local r = prototypes.recipe[m]
  if r then for _, i in pairs(r.ingredients) do if i.type == "item" then SB.uses[i.name] = true end end end
end
SB.raw = {}
local function expand(item, n)
  local r = prototypes.recipe[item]
  if mask[item] and r then
    local out = 1
    for _, p in pairs(r.products) do if p.name == item then out = p.amount or 1 end end
    for _, i in pairs(r.ingredients) do expand(i.name, i.amount * n / out) end
  else SB.raw[item] = (SB.raw[item] or 0) + n end
end
expand(SB.TARGET, SB.BATCH)
SB.mask = mask
SB.target = {}
-- Items the mall makes keep today's stock exactly: their stock is on the list (D = missing - stock), so
-- inflating it hides demand. Measured: 10x copper cable (260) kept cable off the list, 0 changes vs 136.
for k, v in pairs(SB.before) do
  local name = k:match("^(.-)/")
  if mask[name] then SB.target[k] = math.max(0, v)
  elseif SB.uses[name] then SB.target[k] = math.max(0, SB.FACTOR * v)
  elseif v > 0 then SB.target[k] = v end
end
for name, per in pairs(SB.raw) do
  local k = SB.key(name)
  SB.target[k] = math.max(SB.target[k] or 0, math.ceil(per * SB.BATCHES))
end
SB.dump("sandbox_target.txt", SB.target)
rcon.print("raw per " .. SB.BATCH .. " servers: " .. serpent.line(SB.raw))
---
/silent-command
-- Trim nauvis: delete every chunk outside a one-chunk margin around the mall, and every non-mall entity inside it.
local s = SB.s
local cx1, cy1 = math.floor(SB.KEEP[1][1] / 32) - 1, math.floor(SB.KEEP[1][2] / 32) - 1
local cx2, cy2 = math.floor((SB.EXTRA[#SB.EXTRA][1] + 3) / 32) + 1, math.floor(SB.KEEP[2][2] / 32) + 1
SB.chunks = {cx1, cy1, cx2, cy2}
local deleted, destroyed = 0, 0
for c in s.get_chunks() do
  if c.x < cx1 or c.x > cx2 or c.y < cy1 or c.y > cy2 then s.delete_chunk(c) deleted = deleted + 1 end
end
local net = SB.net()
for _, e in pairs(s.find_entities_filtered{area = {{cx1 * 32, cy1 * 32}, {(cx2 + 1) * 32, (cy2 + 1) * 32}}}) do
  if e.valid and not SB.kept(e) then
    local robot = e.type == "logistic-robot" or e.type == "construction-robot"
    if not (robot and e.logistic_network == net) then e.destroy() destroyed = destroyed + 1 end
  end
end
for _, p in pairs(game.forces.player.platforms) do p.destroy(1) end
for _, surf in pairs(game.surfaces) do if surf.name ~= "nauvis" and not surf.platform then game.delete_surface(surf) end end
s.generate_with_lab_tiles = true
s.peaceful_mode = true
game.map_settings.enemy_expansion.enabled = false
game.map_settings.enemy_evolution.enabled = false
game.map_settings.pollution.enabled = false
s.clear_pollution()
game.ticks_to_run = 3
rcon.print("chunks " .. serpent.line(SB.chunks) .. " kept; deleted " .. deleted .. " chunks, destroyed " .. destroyed .. " entities in the margin; running 3 ticks")
---
/silent-command
-- Power: one electric-energy-interface per electric network left among the kept entities.
local s = SB.s
local nets, sample = {}, {}
for _, e in pairs(s.find_entities_filtered{area = SB.KEEP}) do
  local id = e.electric_network_id
  if id and e.type ~= "electric-pole" then nets[id] = (nets[id] or 0) + 1 sample[id] = sample[id] or e end
end
SB.eei = {}
for id, e in pairs(sample) do
  local spot = {-208, 114}
  local placed
  for dy = 0, 12 do
    for _, yy in pairs({spot[2] + dy, spot[2] - dy}) do
      if not placed then
        local p = s.find_non_colliding_position("electric-energy-interface", {spot[1], yy}, 0.5, 0.5)
        if p then
          local eei = s.create_entity{name = "electric-energy-interface", position = p, force = "player"}
          if eei and eei.electric_network_id == id then placed = eei elseif eei then eei.destroy() end
        end
      end
    end
  end
  if not placed then
    for dx = -20, 20, 2 do for dy = -20, 20, 2 do
      if not placed then
        local p = s.find_non_colliding_position("electric-energy-interface", {e.position.x + dx, e.position.y + dy}, 1, 0.5)
        if p then
          local eei = s.create_entity{name = "electric-energy-interface", position = p, force = "player"}
          if eei and eei.electric_network_id == id then placed = eei elseif eei then eei.destroy() end
        end
      end
    end end
  end
  assert(placed, "no spot for an energy interface on electric network " .. id)
  placed.electric_buffer_size = 1e15
  placed.power_production = 1e13
  placed.power_usage = 0
  placed.energy = 1e15
  placed.destructible = false
  SB.eei[#SB.eei + 1] = placed
end
local o = {}
for id, c in pairs(nets) do o[#o + 1] = "net " .. id .. ": " .. c .. " consumers" end
for _, eei in pairs(SB.eei) do o[#o + 1] = "EEI at " .. serpent.line(eei.position) .. " net " .. eei.electric_network_id end
rcon.print(table.concat(o, "; "))
---
/silent-command
-- Stock: empty the original warehouse, then fill target - (what kept chests and robots still hold).
local s = SB.s
local wh = SB.at(SB.WAREHOUSE, "kr-storage-warehouse")
wh.get_inventory(defines.inventory.chest).clear()
local have = SB.contents()
local todo = {}
for k, want in pairs(SB.target) do
  local d = want - math.max(0, have[k] or 0)
  if d > 0 then local name, q = k:match("^(.-)/(.*)$") todo[#todo + 1] = {name = name, quality = q, count = d, raw = SB.raw[name] ~= nil} end
end
table.sort(todo, function(a, b) if a.raw ~= b.raw then return a.raw end return a.name < b.name end)
local stores = {wh}
local function next_store()
  local p = SB.EXTRA[#stores]
  assert(p, "out of EXTRA warehouse spots")
  local e = s.create_entity{name = "kr-storage-warehouse", position = p, force = "player"}
  assert(e and e.logistic_network == SB.net(), "spare warehouse at " .. serpent.line(p) .. " is not on network 18")
  stores[#stores + 1] = e
  return e
end
-- The original warehouse first takes NEAR_SLOTS stacks of each raw input of the server tree, so their pickup distance stays as today.
for _, t in pairs(todo) do
  if t.raw then
    local n = math.min(t.count, SB.NEAR_SLOTS * prototypes.item[t.name].stack_size)
    t.count = t.count - wh.insert{name = t.name, quality = t.quality, count = n}
  end
end
local cur = wh
for _, t in pairs(todo) do
  while t.count > 0 do
    local got = cur.insert{name = t.name, quality = t.quality, count = t.count}
    t.count = t.count - got
    if t.count > 0 then cur = (cur == wh and #stores > 1) and stores[2] or next_store() end
  end
end
SB.after = SB.contents()
SB.dump("sandbox_net18_after.txt", SB.after)
local short = {}
for k, want in pairs(SB.target) do if (SB.after[k] or 0) < want then short[#short + 1] = k .. " " .. (SB.after[k] or 0) .. "<" .. want end end
rcon.print(#stores .. " storage warehouses; short: " .. (#short == 0 and "none" or table.concat(short, ", ")))
---
/silent-command
-- After 300 ticks (roboports charge from the interface): verify power and stock, then save unpaused like the original.
function SB.verify()
local s = SB.s
local c, bad, low = {}, {}, {}
local ds = defines.entity_status
for _, e in pairs(s.find_entities_filtered{area = {{SB.chunks[1] * 32, SB.chunks[2] * 32}, {(SB.chunks[3] + 1) * 32, (SB.chunks[4] + 1) * 32}}}) do
  c[e.name] = (c[e.name] or 0) + 1
  local ok, st = pcall(function() return e.status end)
  if ok and (st == ds.low_power or st == ds.no_power) then bad[#bad + 1] = e.name .. "@" .. e.position.x .. "," .. e.position.y end
  if e.type == "roboport" and e.energy < e.electric_buffer_size * 0.99 then low[#low + 1] = e.position.x .. "," .. e.position.y end
end
local n = SB.net()
SB.robots_after = n.all_logistic_robots .. " logistic, " .. n.all_construction_robots .. " construction, " .. #n.cells .. " roboports, " .. #n.storages .. " storages"
local chunks = 0
for _ in s.get_chunks() do chunks = chunks + 1 end
local surf = {}
for _, x in pairs(game.surfaces) do surf[#surf + 1] = x.name end
local o = {"entities " .. serpent.line(c), "low/no power: " .. (#bad == 0 and "none" or table.concat(bad, " ")), "roboports not full: " .. (#low == 0 and "none" or table.concat(low, " ")), "network 18 before: " .. SB.robots_before, "network 18 after: " .. SB.robots_after, "chunks " .. chunks .. ", surfaces " .. table.concat(surf, ",")}
helpers.write_file("sandbox_report.txt", table.concat(o, "\n"), false, 0)
end
script.on_nth_tick(300, function()
  script.on_nth_tick(300, nil)
  SB.verify()
  game.tick_paused = false
  game.server_save("mall-sandbox")
end)
game.ticks_to_run = 301
rcon.print("running 301 ticks; then script-output/sandbox_report.txt and saves/mall-sandbox.zip")
