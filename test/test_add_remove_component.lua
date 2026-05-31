-- test_add_remove_component.lua — 测试 Clump:addComponent / removeComponent

local BASE = "e:/MTA-Server-DGS/mods/deathmatch/resources/rw/MTARW"

local _print = print; print = function() end
dofile(BASE .. "/test/mta_mock.lua")
print = _print

local modules = {
    "core/binary/reader.lua", "core/binary/writer.lua",
    "utils/bitops.lua", "utils/math3d.lua", "utils/tableutil.lua",
    "core/schema/types.lua", "core/schema/registry.lua", "core/schema/engine.lua",
    "core/base.lua",
    "dff/enums.lua", "dff/primitives.lua", "dff/material.lua", "dff/plugins.lua",
    "dff/uvanim.lua", "dff/framelist.lua", "dff/geometry.lua",
    "dff/atomic.lua", "dff/clump.lua", "dff/dffio.lua",
    "col/colio.lua",
}
for _, mod in ipairs(modules) do dofile(BASE .. "/" .. mod) end

local function check(label, cond)
    if cond then
        print("[OK] " .. label)
    else
        print("[FAIL] " .. label)
    end
end

print("========== Test: Clump:addComponent / removeComponent ==========\n")

-- Test 1: Create a new Clump and add components
print("--- Test 1: Create Clump & add 3 components ---")
local dff = DFFIO:new()
local clump = dff:createClump(GTASA)

check("Empty clump has 0 atomics", #clump.atomics == 0)
check("Empty clump has 0 frames", #clump.frameList.struct.frameInfo == 0)
check("Empty clump has 0 geometries", #clump.geometryList.geometries == 0)

-- Add 3 components
local a1 = clump:addComponent({ name = "Root" })
local a2 = clump:addComponent({ name = "Child1", parentFrame = 0 })
local a3 = clump:addComponent({ name = "Child2", parentFrame = 0, position = {1, 2, 3} })

check("After add: 3 atomics", #clump.atomics == 3)
check("After add: 3 frames", #clump.frameList.struct.frameInfo == 3)
check("After add: 3 geometries", #clump.geometryList.geometries == 3)

check("Atomic[1] frameIndex=0", a1.struct.frameIndex == 0)
check("Atomic[1] geometryIndex=0", a1.struct.geometryIndex == 0)
check("Atomic[2] frameIndex=1", a2.struct.frameIndex == 1)
check("Atomic[2] geometryIndex=1", a2.struct.geometryIndex == 1)
check("Atomic[3] frameIndex=2", a3.struct.frameIndex == 2)
check("Atomic[3] geometryIndex=2", a3.struct.geometryIndex == 2)

-- Check frame names
check("Frame[1] name = 'Root'", clump.frameList.frames[1].frame.name == "Root")
check("Frame[2] name = 'Child1'", clump.frameList.frames[2].frame.name == "Child1")
check("Frame[3] name = 'Child2'", clump.frameList.frames[3].frame.name == "Child2")

-- Check parentFrame references
check("FrameInfo[1] parentFrame = -1 (root)", clump.frameList.struct.frameInfo[1].parentFrame == -1)
check("FrameInfo[2] parentFrame = 0", clump.frameList.struct.frameInfo[2].parentFrame == 0)
check("FrameInfo[3] parentFrame = 0", clump.frameList.struct.frameInfo[3].parentFrame == 0)

-- Check position
check("FrameInfo[3] position = {1,2,3}",
    clump.frameList.struct.frameInfo[3].positionVector[1] == 1 and
    clump.frameList.struct.frameInfo[3].positionVector[2] == 2 and
    clump.frameList.struct.frameInfo[3].positionVector[3] == 3)

-- Check clump counts
check("ClumpStruct atomicCount = 3", clump.struct.atomicCount == 3)

-- Test the geometries exist
check("Geo[1] exists", clump.geometryList.geometries[1] ~= nil)
check("Geo[2] exists", clump.geometryList.geometries[2] ~= nil)
check("Geo[3] exists", clump.geometryList.geometries[3] ~= nil)
check("Geo[1] has materialList", clump.geometryList.geometries[1].materialList ~= nil)
check("Geo[1] has extension", clump.geometryList.geometries[1].extension ~= nil)

print("")

-- Test 2: Remove the middle component (index 2 = Child1)
print("--- Test 2: Remove component at index 2 ---")
local removed = clump:removeComponent(2)

check("removeComponent returns Atomic", removed ~= false and removed.type == Atomic.typeID)
check("Removed atomic had frameIndex=1", removed.struct.frameIndex == 1)
check("After remove: 2 atomics", #clump.atomics == 2)
check("After remove: 2 frames", #clump.frameList.struct.frameInfo == 2)
check("After remove: 2 geometries", #clump.geometryList.geometries == 2)

-- After removing index 2 (frameIdx=1, geoIdx=1), the old index 3 (frameIdx=2, geoIdx=2)
-- should shift down: frameIdx 2→1, geoIdx 2→1
check("Atomic[1] (was Root) still frameIndex=0",
    clump.atomics[1].struct.frameIndex == 0)
check("Atomic[2] (was Child2) now frameIndex=1",
    clump.atomics[2].struct.frameIndex == 1)
check("Atomic[2] now geometryIndex=1",
    clump.atomics[2].struct.geometryIndex == 1)

-- Frame names should now be Root and Child2
check("Frame[1] name = 'Root'",
    clump.frameList.frames[1].frame.name == "Root")
check("Frame[2] name = 'Child2'",
    clump.frameList.frames[2].frame.name == "Child2")

-- parentFrame for Child2 was 0, Root was 0 (parent of Root was -1)
-- After removing FrameInfo[2] (parent was at idx 1), Child2's parentFrame should
-- still be 0 since 0 < 1 (the removed index)
check("FrameInfo[2] (Child2) parentFrame still 0",
    clump.frameList.struct.frameInfo[2].parentFrame == 0)

print("")

-- Test 3: Remove component at index 1 (Root)
print("--- Test 3: Remove component at index 1 ---")
local removed2 = clump:removeComponent(1)
check("removeComponent returns Atomic", removed2 ~= false)
check("After remove: 1 atomics", #clump.atomics == 1)
check("After remove: 1 frame", #clump.frameList.struct.frameInfo == 1)
check("Last atomic frameIndex=0", clump.atomics[1].struct.frameIndex == 0)
check("Last atomic geometryIndex=0", clump.atomics[1].struct.geometryIndex == 0)
check("Last frame name = 'Child2'",
    clump.frameList.frames[1].frame.name == "Child2")
-- Child2's parentFrame was 0 which equals the removed frameIdx (0),
-- so it should be set to -1 (root)
check("Child2 parentFrame → -1 after parent removed",
    clump.frameList.struct.frameInfo[1].parentFrame == -1)

print("")

-- Test 4: Save & reload roundtrip
print("--- Test 4: Save & reload roundtrip ---")
local tmpPath = BASE .. "/test/_test_addremove.dff"
dff:save(tmpPath)

local dff2 = DFFIO:new()
dff2:load(tmpPath)
check("Reloaded: 1 clump", #dff2.clumps == 1)
local c2 = dff2.clumps[1]
check("Reloaded: 1 atomic", #c2.atomics == 1)
check("Reloaded: 1 frame", #c2.frameList.struct.frameInfo == 1)
check("Reloaded: 1 geometry", #c2.geometryList.geometries == 1)
check("Reloaded: frame name = 'Child2'",
    c2.frameList.frames[1].frame.name == "Child2")
check("Reloaded: frameIndex=0", c2.atomics[1].struct.frameIndex == 0)
check("Reloaded: geometryIndex=0", c2.atomics[1].struct.geometryIndex == 0)

os.remove(tmpPath)

-- Test 5: Borderline cases
print("\n--- Test 5: Edge cases ---")
check("removeComponent(0) → false", clump:removeComponent(0) == false)
check("removeComponent(99) → false", clump:removeComponent(99) == false)

-- addComponent with no config
local a4 = clump:addComponent()
check("addComponent() auto-names", a4.struct.frameIndex == 1)
check("Auto-name Component_2", clump.frameList.frames[2].frame.name == "Component_2")

print("\n========== Tests Complete ==========")
