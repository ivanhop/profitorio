-- Load once per server start:  python tools/check/probe_client.py --host 127.0.0.1 --port <rcon> --password probe < harness.lua
-- Then call H.* from later /silent-command lines. Globals persist for the life of the server process.
-- RULES for this file: the client flattens each block to ONE line, so never put a trailing "--" comment
-- on a code line (it swallows the rest). Whole-line comments are fine.
/silent-command
H = {}
H.s = game.surfaces.nauvis
H.TRIGGER = {-207.5, 122.5}
H.RIG_CHEST = {-222.5, 148.5}
H.MALL_AREA = {{-245, 102}, {-214, 138}}
function H.at(pos, name) return H.s.find_entities_filtered{position = pos, radius = 0.6, name = name}[1] end
function H.cells()
  local c = {}
  for i = 0, 9 do c[#c + 1] = H.at({-224.5, 108.5 + 3 * i}, "assembling-machine-2") end
  for i = 9, 0, -1 do c[#c + 1] = H.at({-234.5, 108.5 + 3 * i}, "assembling-machine-2") end
  return c
end
function H.net() return H.at(H.TRIGGER, "requester-chest").logistic_network end
function H.rig_off() H.at(H.RIG_CHEST, "requester-chest").get_control_behavior().set_requests = false end
function H.demand(item, n)
  local sec = H.at(H.TRIGGER, "requester-chest").get_requester_point().get_section(1)
  if not item or n == 0 then sec.clear_slot(1) else sec.set_slot(1, {value = {name = item, quality = "normal"}, min = n}) end
end
function H.stock(items) local n, o = H.net(), {} for _, it in pairs(items) do o[it] = n.get_item_count(it) end return o end
function H.hoard()
  local t = 0
  for _, e in pairs(H.s.find_entities_filtered{area = H.MALL_AREA, name = "requester-chest"}) do t = t + e.get_item_count() end
  return t
end
function H.rname(e) local r = e.get_recipe() return r and r.name or "-" end
---
/silent-command
function H.run(ticks, tag)
  local cells = H.cells()
  local st = {tag = tag or "run", t0 = game.tick, ticks = ticks, cell = {}, recipe = {}, log = {}}
  for i, e in pairs(cells) do
    st.cell[i] = {r = H.rname(e), pf = e.products_finished, changes = 0, work = 0, starved = 0, none = 0, crafts = 0}
  end
  H.state = st
  script.on_nth_tick(1, function()
    local now = game.tick - st.t0
    for i, e in pairs(cells) do
      local c = st.cell[i]
      local r = H.rname(e)
      if r ~= c.r then
        c.changes = c.changes + 1
        st.log[#st.log + 1] = now .. " C" .. i .. " " .. c.r .. " -> " .. r
        c.r = r
      end
      local pf = e.products_finished
      if pf > c.pf then
        local rr = st.recipe[r] or {ticks = 0, crafts = 0}
        rr.crafts = rr.crafts + (pf - c.pf)
        st.recipe[r] = rr
        c.crafts = c.crafts + (pf - c.pf)
      end
      c.pf = pf
      if r == "-" then c.none = c.none + 1
      else
        local rr = st.recipe[r] or {ticks = 0, crafts = 0}
        rr.ticks = rr.ticks + 1
        st.recipe[r] = rr
        if e.status == defines.entity_status.working then c.work = c.work + 1 else c.starved = c.starved + 1 end
      end
    end
    if now + 1 >= ticks then script.on_nth_tick(1, nil) H.done = true end
  end)
  H.done = false
  return "running " .. ticks .. " ticks from " .. game.tick
end
function H.report()
  local st = H.state
  if not H.done then return "not done yet, tick " .. (game.tick - st.t0) .. "/" .. st.ticks end
  local W, S, N, CH = 0, 0, 0, 0
  local lines = {}
  for i, c in pairs(st.cell) do
    W = W + c.work S = S + c.starved N = N + c.none CH = CH + c.changes
    lines[#lines + 1] = string.format("C%-2d %-28s work=%-5d starved=%-5d none=%-5d changes=%-3d crafts=%d", i, c.r, c.work, c.starved, c.none, c.changes, c.crafts)
  end
  local T = st.ticks * 20
  local head = string.format("[%s] %d ticks: working %.0f%%  recipe-but-not-working %.0f%%  no-recipe %.0f%%  recipe changes %d  chest hoard %d items",
    st.tag, st.ticks, 100 * W / T, 100 * S / T, 100 * N / T, CH, H.hoard())
  local rec = {}
  for r, v in pairs(st.recipe) do rec[#rec + 1] = string.format("  %-28s cells=%.2f crafts=%d", r, v.ticks / st.ticks, v.crafts) end
  table.sort(rec)
  helpers.write_file(st.tag .. "_changes.txt", table.concat(st.log, "\n"))
  return head .. "\n" .. table.concat(lines, "\n") .. "\nper recipe (avg cells assigned):\n" .. table.concat(rec, "\n") .. "\n(change log: script-output/" .. st.tag .. "_changes.txt)"
end
function H.export(file, area)
  local inv = game.create_inventory(1)
  inv.insert("blueprint")
  local bp = inv[1]
  bp.create_blueprint{surface = H.s, force = "player", area = area or {{-245, 102}, {-214, 138}}}
  helpers.write_file(file .. ".txt", bp.export_stack())
  helpers.write_file(file .. ".json", helpers.table_to_json(bp.get_blueprint_entities()))
  inv.destroy()
  return "exported " .. file
end
rcon.print("harness loaded, " .. #H.cells() .. " cells")
