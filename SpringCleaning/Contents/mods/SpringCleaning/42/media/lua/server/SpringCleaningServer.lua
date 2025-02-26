
-------------------
local Spring = require("Spring");

print("[SpringCleaning] Loading...");
-------------------

local function serverInit()
    print("[SpringCleaning] Booted");

    -- Init stuff
    Spring.getSymbolsApi();
    Spring.registerTextures();

    -- Set tickrate lower for server as server has slower tickrate
    Spring.tickRate = 150;

    -- Load previously saved map data
    Spring.loadCellsFromFile();

    -- Do an initial tick
    Spring.doServerTick();

    -- Register event listeners
    Events.OnTick.Add(Spring.serverCheckTick);
    Events.OnSave.Add(Spring.saveCellsToFile);
    
end

function Spring.serverCheckTick()
    Spring.currentTick = Spring.currentTick + 1;

	if Spring.currentTick > Spring.tickRate then
        Spring.currentTick = 1;

        Spring.doServerTick();
    end
end

function Spring.doServerTick()

    -- Do a similar loop to the offline client, but for each connected client
    local clientUpdateTable = {};
    local allCellsToBeUpdated = {};
    local allCoordsToBeUpdated = {};

    local connectedPlayers = getOnlinePlayers();
    local connectedPlayersSize = connectedPlayers:size();

    -- Why would the for loop run with playerSize 0 ???????
    if connectedPlayersSize > 0 then
        for playerIndex=0, connectedPlayersSize-1, 1 do
            -- Fetch cell data
            local player = connectedPlayers:get(playerIndex);
            local cellsAroundPlayerList = Spring.getCellsSurroundingPlayer(player, Spring.cellRadius);
            local cellsWithZombiesAroundPlayerList = Spring.assignZombiesToGrid(player);
            cellsWithZombiesAroundPlayerList = Spring.fuseLists(cellsAroundPlayerList, cellsWithZombiesAroundPlayerList, Spring.SkipUnknown.DONT_SKIP);

            -- Save new cell data
            Spring.cellsList = Spring.fuseLists(Spring.cellsList, cellsWithZombiesAroundPlayerList, Spring.SkipUnknown.SKIP);

            -- Recompute borders (this needs to be done only for new cells)
            local cellsToBeRedrawnCoordsList = Spring.getCellsSurroundingPlayer(player, Spring.cellRadius+1);
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

            -- Compose data for the clients
            allCellsToBeUpdated = Spring.fuseLists(allCellsToBeUpdated, cellsToBeUpdatedList, Spring.SkipUnknown.SKIP);
            allCoordsToBeUpdated[#allCoordsToBeUpdated+1] = coordsRangeToUpdate;
        end
    end

    -- Send data to the clients
    if allCellsToBeUpdated ~= {} then
        --print("[SpringCleaning] Sending update data to players");
        clientUpdateTable["cellsToBeUpdatedList"] = allCellsToBeUpdated;
        clientUpdateTable["coordsRangeToUpdateList"] = allCoordsToBeUpdated;

        sendServerCommand(Spring.moduleName, Spring.commands.UPDATE, clientUpdateTable);
    end

end

local function onClientCommandReceived(module, command, player, receivedData)

    if module ~= Spring.moduleName then
        return;
    end

    if command == Spring.commands.REQ_INITIAL_SYNC then
        --print("[SpringCleaning] Sending initial sync");
        -- Send full cellsList to the client
        sendServerCommand(player, Spring.moduleName, Spring.commands.ACK_INITIAL_SYNC, Spring.cellsList);
    end
end


if isServer() then
    Events.OnServerStarted.Add(serverInit);
    Events.OnClientCommand.Add(onClientCommandReceived);
end