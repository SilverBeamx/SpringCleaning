
-------------------
require "ISUI/Maps/ISWorldMap";
local Spring = require("Spring");

print("[SpringCleaning] Loading...");
-------------------

local function init()
    print("[SpringCleaning] Booted");

    -- Init stuff
    Spring.getSymbolsApi();
    Spring.registerTextures();
    Spring.mpInitialized = false;

    -- Check if player is offline
    if not isClient() and not isServer() then

        -- Load previously saved map data
        Spring.loadCellsFromFile();

        -- Initial map refresh
        Spring.refreshMap();

        -- Do an initial tick
        Spring.doSPTick();

        -- Register event listeners
        Events.OnTick.Add(Spring.SPCheckTick);
        Events.OnSave.Add(Spring.saveCellsToFile);
    end

    if isClient() then
        -- Load preferences
        Spring.loadSavedDataFromFile();
    end

end

function Spring.SPCheckTick()
    Spring.currentTick = Spring.currentTick + 1;

	if Spring.currentTick > Spring.tickRate then
        Spring.currentTick = 1;

        Spring.doSPTick();
    end
end

-- This only needs to be done offline
function Spring.doSPTick()

    -- Always refresh map instance before drawing/removing
    Spring.getSymbolsApi();

    -- Fetch cell data
    local currentPlayer = getPlayer();
    local cellsAroundPlayerList = Spring.getCellsSurroundingPlayer(currentPlayer, Spring.cellRadius);
    local cellsWithZombiesAroundPlayerList = Spring.assignZombiesToGrid(currentPlayer);
    cellsWithZombiesAroundPlayerList = Spring.fuseLists(cellsAroundPlayerList, cellsWithZombiesAroundPlayerList, Spring.SkipUnknown.DONT_SKIP);

    -- Save new cell data
    Spring.cellsList = Spring.fuseLists(Spring.cellsList, cellsWithZombiesAroundPlayerList, Spring.SkipUnknown.SKIP);

    -- Recompute borders (this needs to be done only for new cells)
    local cellsToBeRedrawnCoordsList = Spring.getCellsSurroundingPlayer(currentPlayer, Spring.cellRadius+1);
    local cellsToBeUpdatedList = {};
    local coordsRangeToUpdate = {minX = 1000000, minY = 1000000, maxX = 0, maxY = 0};
    for cellCoords, _  in pairs(cellsToBeRedrawnCoordsList) do
        if Spring.cellsList[cellCoords] ~= nil then
            cellsToBeUpdatedList[cellCoords] = Spring.cellsList[cellCoords];
            if cellsToBeUpdatedList[cellCoords].x > coordsRangeToUpdate.maxX then
                coordsRangeToUpdate.maxX = cellsToBeUpdatedList[cellCoords].x;
            end
            if cellsToBeUpdatedList[cellCoords].x < coordsRangeToUpdate.minX then
                coordsRangeToUpdate.minX = cellsToBeUpdatedList[cellCoords].x;
            end
            if cellsToBeUpdatedList[cellCoords].y > coordsRangeToUpdate.maxY then
                coordsRangeToUpdate.maxY = cellsToBeUpdatedList[cellCoords].y;
            end
            if cellsToBeUpdatedList[cellCoords].y < coordsRangeToUpdate.minY then
                coordsRangeToUpdate.minY = cellsToBeUpdatedList[cellCoords].y;
            end
        end
    end
    coordsRangeToUpdate.maxX = coordsRangeToUpdate.maxX + Spring.cellSize;
    coordsRangeToUpdate.maxY = coordsRangeToUpdate.maxY + Spring.cellSize;

    cellsToBeUpdatedList = Spring.assignBordersToGrid(Spring.cellsList, cellsToBeUpdatedList);
    Spring.cellsList = Spring.fuseLists(Spring.cellsList, cellsToBeUpdatedList, Spring.SkipUnknown.SKIP);

    if Spring.Preferences.DrawOnMapEnabled then
        -- Reset map symbols
        Spring.wipeCellRangeFromMap(coordsRangeToUpdate);

        -- Add zombie count text and colors
        Spring.drawCellsListOnMap(cellsToBeUpdatedList);
    end

end

local function onServerCommandReceived(module, command, receivedData)

    if module ~= Spring.moduleName then
        return;
    end

    if command == Spring.commands.ACK_INITIAL_SYNC then
        --print("[SpringCleaning] Initial sync received")
        -- Do initial full redraw
        Spring.cellsList = receivedData;
        Spring.getSymbolsApi();
        Spring.refreshMap(Spring.cellsList);
        Spring.mpInitialized = true;
    elseif command == Spring.commands.UPDATE then
        --print("[SpringCleaning] Update received");

        if not Spring.mpInitialized then
            --print("[SpringCleaning] Initial sync requested");
            -- Request data from the server
            sendClientCommand(Spring.moduleName, Spring.commands.REQ_INITIAL_SYNC, {});
        else
            if Spring.Preferences.DrawOnMapEnabled then
                Spring.getSymbolsApi();
                -- Wipe ranges
                for _, coordsRangeToUpdate in pairs(receivedData["coordsRangeToUpdateList"]) do
                    -- Reset map symbols
                    Spring.wipeCellRangeFromMap(coordsRangeToUpdate);
                end

                -- Draw new cells
                Spring.drawCellsListOnMap(receivedData["cellsToBeUpdatedList"]);
            end

            -- Save new cells
            Spring.cellsList = Spring.fuseLists(Spring.cellsList, receivedData["cellsToBeUpdatedList"], Spring.SkipUnknown.SKIP);
        end
    end

end

-- Add map button (code thanks to Draw On Map mod)
ISWorldMap.vanillaCreateChildren = ISWorldMap.createChildren;
ISWorldMap.createChildren = function(self)
	self:vanillaCreateChildren();

    local buttonHeight = getTextManager():getFontHeight(UIFont.Small) + 2 * 2;

    self.springCleaningButton = ISButton:new(getCore():getScreenWidth() - 155, getCore():getScreenHeight() - 100, 100, buttonHeight, "Toggle Zombie Density", self, self.handleSpringCleaningButtonClick);
    self:addChild(self.springCleaningButton);
end

ISWorldMap.handleSpringCleaningButtonClick = function(self)
    -- Fetch latest mapApi
    Spring.getSymbolsApi();
    -- Toggle map visibility
    if Spring.Preferences.DrawOnMapEnabled then
        Spring.wipeZombieCountsFromMap();
        Spring.wipeZombieDensityZonesFromMap();
        Spring.Preferences.DrawOnMapEnabled = false;
    else
        Spring.drawCellsListOnMap(Spring.cellsList);
        Spring.Preferences.DrawOnMapEnabled = true;
    end
end
-----

-- Register initial event listeners
Events.OnGameStart.Add(init);

if isClient() then
    Events.OnServerCommand.Add(onServerCommandReceived);
    -- Save preferences
    Events.OnDisconnect.Add(Spring.saveModData)
end
