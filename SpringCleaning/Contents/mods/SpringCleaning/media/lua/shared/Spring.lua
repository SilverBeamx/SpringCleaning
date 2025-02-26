
-------------------
require 'ISUI/Maps/ISWorldMap'
require 'ISUI/Maps/ISMiniMap'

local Json = require("Json");

print("[SpringCleaning] Loading...");
-------------------

local Spring = {};
Spring.savefileName = "springCleaning.json";
Spring.saveData = {};
Spring.CURRENT_SAVE_VERSION = 2;
Spring.currentTick = 0;
Spring.tickRate = 300;
Spring.cellSize = 100;
Spring.cellRadius = 1;
Spring.mapApi = nil;
Spring.mapSymbolsApi = nil;
Spring.cellsList = {};
Spring.zombiesLeftText = "zombie(s) left";
Spring.ZombieDensity = {UNKNOWN=-1,EMPTY=0,LOW=1,MEDIUM=2,HIGH=3};
Spring.SkipUnknown = {DONT_SKIP=false, SKIP=true};
Spring.cellTextures = {
    ["SpringCellFill"] = "media/ui/CellFill.png",
    ["SpringCellBorderUp"] = "media/ui/CellBorderUp.png",
    ["SpringCellBorderLeft"] = "media/ui/CellBorderLeft.png",
    ["SpringCellBorderDown"] = "media/ui/CellBorderDown.png",
    ["SpringCellBorderRight"] = "media/ui/CellBorderRight.png"
};

Spring.moduleName = "SpringCleaning";
Spring.commands = {REQ_INITIAL_SYNC="reqInitialSync",ACK_INITIAL_SYNC="ackInitialSync",UPDATE="update"};

Spring.Preferences= {
    DrawOnMapEnabled = true
};

-- Save/Load Management

function Spring.getCurrentFormattedSaveName()
    local saveInfo = getLatestSave();

    return table.concat(saveInfo,"|");
end

function Spring.saveModData()
    local fileWriterObj = getFileWriter(Spring.savefileName, true, false);
    local json = Json.Encode(Spring.saveData);
    fileWriterObj:write(json);
    fileWriterObj:close();
end

function Spring.saveCellsToFile()
    local formattedFileName = Spring.getCurrentFormattedSaveName();
    Spring.saveData[formattedFileName] = Spring.cellsList;

    Spring.saveModData();
end

function Spring.loadModData()
    local fileReaderObj = getFileReader(Spring.savefileName, true);
    local json = "";
    local line = fileReaderObj:readLine();
    while line ~= nil do
        json = json .. line;
        line = fileReaderObj:readLine()
    end
    fileReaderObj:close();

    if json and json ~= "" then
        Spring.saveData = Json.Decode(json);
    else
        Spring.saveData = {};
    end
end

function Spring.loadSavedDataFromFile()
    -- Init saved mod data
    Spring.loadModData();

    -- Do a version check and wipe data is save version increased
    if Spring.saveData["Version"] == nil or Spring.saveData["Version"] < Spring.CURRENT_SAVE_VERSION then
        Spring.saveData = {["Version"] = Spring.CURRENT_SAVE_VERSION, ["Preferences"] = Spring.Preferences};
    end

    -- Retrieve preferences
    Spring.Preferences = Spring.saveData["Preferences"];
end

function Spring.loadCellsFromFile()
    local formattedFileName = Spring.getCurrentFormattedSaveName();

    -- Load saved data
    Spring.loadSavedDataFromFile()

    -- Retrieve cell save data
    if Spring.saveData[formattedFileName] ~= nil then
        Spring.cellsList = Spring.saveData[formattedFileName];
    else
        Spring.cellsList = {};
    end
end

--------------

function Spring.getSymbolsApi()
    local mapApi;

    if ISWorldMap_instance then
        mapApi = ISWorldMap_instance.javaObject:getAPIv1();
    else
        mapApi = UIWorldMap.new(nil):getAPIv1();
        mapApi:setMapItem(MapItem:getSingleton());
    end
    Spring.mapApi = mapApi;
    Spring.mapSymbolsApi = mapApi:getSymbolsAPI();
end

function Spring.registerTextures()
    for texName, texPath in pairs(Spring.cellTextures) do
        if Spring.getBuildNumber() == 41 then
            MapSymbolDefinitions.getInstance():addTexture(texName, texPath, 100, 100);
        else
            MapSymbolDefinitions.getInstance():addTexture(texName, texPath, 20, 20, nil);
        end
    end
end

function Spring.getBuildNumber()
    return getCore():getGameVersion():getMajor();
end

function Spring.getCellsSurroundingPlayer(currentPlayer, radius)
    local cellGrid = {}

    --Get player position aligned to cellSize
    local playerX = math.floor(currentPlayer:getX()/Spring.cellSize)*Spring.cellSize;
    local playerY = math.floor(currentPlayer:getY()/Spring.cellSize)*Spring.cellSize;

    -- Get grid of the cells surrounding player
    for i=-radius, radius, 1 do
        local cellX = playerX + (i*Spring.cellSize);
        if cellX > 0 then -- and lesser than what?
            for j=-radius, radius, 1 do
                local cellY = playerY + (j*Spring.cellSize);
                if cellY > 0 then -- and lesser than what?
                    local cellCoordinatesString = Spring.formatCoordinates(cellX, cellY);
                    local cellInitialDensity = Spring.ZombieDensity.UNKNOWN;
                    -- The only guaranteed fully explored cell 
                    -- (in relation to the moving window of player:getCell()) is the one the player is in
                    if cellX == playerX and cellY == playerY then
                        cellInitialDensity = Spring.ZombieDensity.EMPTY;
                    end
                    cellGrid[cellCoordinatesString] = {x = cellX, y = cellY, amount = 0, density = cellInitialDensity, borders = {}};
                end
            end
        end
    end
    return cellGrid
end

function Spring.assignZombiesToGrid(currentPlayer)
    local zombieCellData = {};
    local zombieList = currentPlayer:getCell():getZombieList();
    local zombieCount = zombieList:size();

    -- Divide detected zombies in cells of size cellSize on each dimension
    if zombieCount > 0 then
        for i=0,zombieCount-1,1 do
            local zombie = zombieList:get(i);
            if zombie then
                --Align the retrieved zombies to cellSize
                local zombieCellX = math.floor(zombie:getX()/Spring.cellSize)*Spring.cellSize;
                local zombieCellY = math.floor(zombie:getY()/Spring.cellSize)*Spring.cellSize;
                --Count the zombies per cell in a table/array indexed by "zombieCellX,zombieCellY"
                local cellCoordinatesString = Spring.formatCoordinates(zombieCellX, zombieCellY);
                if zombieCellData[cellCoordinatesString] == nil then
                    zombieCellData[cellCoordinatesString] = {x = zombieCellX, y = zombieCellY, amount = 1, density = Spring.ZombieDensity.LOW, borders = {}};
                else
                    zombieCellData[cellCoordinatesString].amount = zombieCellData[cellCoordinatesString].amount + 1;
                end
            end
        end
    end

    -- Assign density status to each cell
    for cellCoordinatesString, cellData in pairs(zombieCellData) do
        local zombieAmount = cellData.amount;

        if zombieAmount > 30 and zombieAmount <= 60 then
            zombieCellData[cellCoordinatesString].density = Spring.ZombieDensity.MEDIUM;
        elseif zombieAmount > 60 then
            zombieCellData[cellCoordinatesString].density = Spring.ZombieDensity.HIGH;
        end
    end

    return zombieCellData
end

function Spring.formatCoordinates(x,y)
    return x..","..y;
end

function Spring.getCellFromCoordinates(cellsList,x,y)
    return cellsList[Spring.formatCoordinates(x,y)];
end

function Spring.getBorderingCellsCoordinates(x,y)
    -- Return bordering cells relative to an x,y in the keys of a table
    local borderCoordinates = {};
    local tempCoord;

    -- Left
    if x - Spring.cellSize > 0 then
        tempCoord = Spring.formatCoordinates(x-Spring.cellSize,y);
        borderCoordinates[tempCoord] = 1;
    end
    -- Right
    tempCoord = Spring.formatCoordinates(x+Spring.cellSize,y);
    borderCoordinates[tempCoord] = 1;
    -- Up
    if y - Spring.cellSize > 0 then
        tempCoord = Spring.formatCoordinates(x,y-Spring.cellSize);
        borderCoordinates[tempCoord] = 1;
    end
    -- Down
    tempCoord = Spring.formatCoordinates(x,y+Spring.cellSize);
    borderCoordinates[tempCoord] = 1;

    return borderCoordinates;
end

function Spring.fuseLists(victimList, overwritingList, skipUnknown)
    for overIndex, overData in pairs(overwritingList) do
        if skipUnknown then
            if victimList[overIndex] == nil or overData.density ~= Spring.ZombieDensity.UNKNOWN then
                victimList[overIndex] = overData;
            end
        else
            victimList[overIndex] = overData;
        end
    end

    return victimList;
end

function Spring.assignBordersToGrid(cellsList, cellListToUpdate)
    local tempCell;

    for _, cellData in pairs(cellListToUpdate) do
        -- Left
        tempCell = Spring.getCellFromCoordinates(cellsList,cellData.x-Spring.cellSize,cellData.y);
        if tempCell == nil or tempCell.density ~= cellData.density then
            cellData.borders["Left"] = true;
        else
            cellData.borders["Left"] = false;
        end
        -- Right
        tempCell = Spring.getCellFromCoordinates(cellsList,cellData.x+Spring.cellSize,cellData.y);
        if tempCell == nil or tempCell.density ~= cellData.density then
            cellData.borders["Right"] = true;
        else
            cellData.borders["Right"] = false;
        end
        -- Up
        tempCell = Spring.getCellFromCoordinates(cellsList,cellData.x,cellData.y-Spring.cellSize);
        if tempCell == nil or tempCell.density ~= cellData.density then
            cellData.borders["Up"] = true;
        else
            cellData.borders["Up"] = false;
        end
        -- Down
        tempCell = Spring.getCellFromCoordinates(cellsList,cellData.x,cellData.y+Spring.cellSize);
        if tempCell == nil or tempCell.density ~= cellData.density then
            cellData.borders["Down"] = true;
        else
            cellData.borders["Down"] = false;
        end
    end

    return cellListToUpdate;
end

function Spring.refreshMap()

    -- Reset map symbols
    Spring.wipeZombieCountsFromMap();
    Spring.wipeZombieDensityZonesFromMap();

    if Spring.Preferences.DrawOnMapEnabled then
        -- Add initial zombie count text and colors
        Spring.drawCellsListOnMap(Spring.cellsList);
    end
end

function Spring.drawCellsListOnMap(cellsList)
    -- Add initial zombie count text and colors
    for _,cellData in pairs(cellsList) do
        Spring.addZombieDensityZone(cellData);
        Spring.addZombieCellInfoTextToMap(cellData);
    end
end

function Spring.addZombieCellInfoTextToMap(cellData)
    if cellData.density == Spring.ZombieDensity.UNKNOWN then
        Spring.addZombieCountToMap(cellData.x,cellData.y,"???");
    else
        if cellData.amount > 0 then
            Spring.addZombieCountToMap(cellData.x,cellData.y,cellData.amount);
        end
    end
end

function Spring.addZombieCountToMap(x,y,count)
    Spring.mapSymbolsApi:addUntranslatedText(count.." "..Spring.zombiesLeftText,UIFont.Small,x+(0.2*Spring.cellSize),y+(0.45*Spring.cellSize));
end

function Spring.wipeCellRangeFromMap(coordsRangeToUpdate)

    local markersAmount = Spring.mapSymbolsApi:getSymbolCount();
	for index=markersAmount-1,0,-1 do

        local marker = Spring.mapSymbolsApi:getSymbolByIndex(index);
        local markerX = marker:getWorldX();
        local markerY = marker:getWorldY();
        -- Check that the symbol is in range
        if markerX >= coordsRangeToUpdate.minX and markerX < coordsRangeToUpdate.maxX and markerY >= coordsRangeToUpdate.minY and markerY < coordsRangeToUpdate.maxY then

            -- Filter only text symbols
            if marker ~= nil and instanceof(marker,"WorldMapSymbolsV1$WorldMapTextSymbolV1") then
                local markerText = marker:getUntranslatedText();
                if markerText ~= nil then
                    if markerText:sub(-#Spring.zombiesLeftText) == Spring.zombiesLeftText then
                        Spring.mapSymbolsApi:removeSymbolByIndex(index);
                    end
                end
            end

            -- Wipe texture symbol
            if marker ~= nil and instanceof(marker,"WorldMapSymbolsV1$WorldMapTextureSymbolV1") then
                -- Filter only symbols from Spring Cleaning
                local markerTexture = marker:getSymbolID();
                if markerTexture ~= nil and Spring.cellTextures[markerTexture] ~= nil then
                    Spring.mapSymbolsApi:removeSymbolByIndex(index);
                end
            end
        end
	end
end

function Spring.wipeZombieCountsFromMap()
    Spring.getSymbolsApi();
    local markersAmount = Spring.mapSymbolsApi:getSymbolCount();
    for i=markersAmount-1,0,-1 do
        local marker = Spring.mapSymbolsApi:getSymbolByIndex(i);
        -- Filter only text symbols
        if marker ~= nil and instanceof(marker,"WorldMapSymbolsV1$WorldMapTextSymbolV1") then
            local markerText = marker:getUntranslatedText();
            if markerText ~= nil then
                if markerText:sub(-#Spring.zombiesLeftText) == Spring.zombiesLeftText then
                    Spring.mapSymbolsApi:removeSymbolByIndex(i);
                end
            end
        end
    end
end

function Spring.wipeZombieDensityZonesFromMap()
    Spring.getSymbolsApi();
    local markersAmount = Spring.mapSymbolsApi:getSymbolCount();
    for i=markersAmount-1,0,-1 do
        local marker = Spring.mapSymbolsApi:getSymbolByIndex(i);
        -- Filter only texture symbols
        if marker ~= nil and instanceof(marker,"WorldMapSymbolsV1$WorldMapTextureSymbolV1") then
            -- Filter only symbols from Spring Cleaning
            local markerTexture = marker:getSymbolID();
            if markerTexture ~= nil and Spring.cellTextures[markerTexture] ~= nil then
                Spring.mapSymbolsApi:removeSymbolByIndex(i);
            end
        end
    end
end

function Spring.wipeMap()
    local markersAmount = Spring.mapSymbolsApi:getSymbolCount();
    for i=markersAmount-1,0,-1 do
        Spring.mapSymbolsApi:removeSymbolByIndex(i);
    end
end

function Spring.addZombieDensityZone(cellData)
    local textureSpecs;
    if Spring.getBuildNumber() == 41 then
        textureSpecs = {r = 0, g = 0, b = 0, opacity = 0.6, scale = 1};
    else
        textureSpecs = {r = 0, g = 0, b = 0, opacity = 0.6, scale = Spring.cellSize/20};
    end

    if cellData.density == Spring.ZombieDensity.EMPTY then
        -- Green
        textureSpecs.g = 1;
    elseif cellData.density == Spring.ZombieDensity.LOW then
        -- Bright Yellow
        textureSpecs.r = 1;
        textureSpecs.g = 170/255;
        textureSpecs.b = 29/255;
    elseif cellData.density == Spring.ZombieDensity.MEDIUM then
        -- Red Orange
        textureSpecs.r = 1;
        textureSpecs.g = 77/255;
    elseif cellData.density == Spring.ZombieDensity.HIGH then
        -- Red
        textureSpecs.r = 1;
    elseif cellData.density == Spring.ZombieDensity.UNKNOWN then
        -- Light Grey
        textureSpecs.r = 173/255;
        textureSpecs.g = 173/255;
        textureSpecs.b = 173/255;
    end

    -- Add fill
    local texture = Spring.mapSymbolsApi:addTexture("SpringCellFill",cellData.x,cellData.y);
    texture:setRGBA(textureSpecs.r, textureSpecs.g, textureSpecs.b, textureSpecs.opacity);
    texture:setScale(textureSpecs.scale);

    -- Add borders
    if cellData.borders["Left"] ~= nil and cellData.borders["Left"] then
        texture = Spring.mapSymbolsApi:addTexture("SpringCellBorderLeft",cellData.x,cellData.y);
        texture:setRGBA(textureSpecs.r, textureSpecs.g, textureSpecs.b, 1);
        texture:setScale(textureSpecs.scale);
    end
    if cellData.borders["Right"] ~= nil and cellData.borders["Right"] then
        texture = Spring.mapSymbolsApi:addTexture("SpringCellBorderRight",cellData.x,cellData.y);
        texture:setRGBA(textureSpecs.r, textureSpecs.g, textureSpecs.b, 1);
        texture:setScale(textureSpecs.scale);
    end
    if cellData.borders["Up"] ~= nil and cellData.borders["Up"] then
        texture = Spring.mapSymbolsApi:addTexture("SpringCellBorderUp",cellData.x,cellData.y);
        texture:setRGBA(textureSpecs.r, textureSpecs.g, textureSpecs.b, 1);
        texture:setScale(textureSpecs.scale);
    end
    if cellData.borders["Down"] ~= nil and cellData.borders["Down"] then
        texture = Spring.mapSymbolsApi:addTexture("SpringCellBorderDown",cellData.x,cellData.y);
        texture:setRGBA(textureSpecs.r, textureSpecs.g, textureSpecs.b, 1);
        texture:setScale(textureSpecs.scale);
    end
end

return Spring;