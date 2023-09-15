local officers = require 'server.officers'
local units = require 'server.units'
local utils = require 'server.utils'
local config = require 'config'
local dbSearch = require 'server.dbSearch'

local function addOfficer(playerId)
    if officers.get(playerId) then return end

    local player = Ox.GetPlayer(playerId)

    if player and player.hasGroup(config.policeGroups) then
        officers.add(playerId, player.firstName, player.lastName, player.stateId, 132)
    end
end

for _, playerId in pairs(GetPlayers()) do
    addOfficer(tonumber(playerId))
end

AddEventHandler('ox:playerLoaded', addOfficer)
AddEventHandler('ox:setGroup', addOfficer)

AddEventHandler('ox:playerLogout', function(playerId)
    local officer = officers.get(playerId)

    if officer then
        local state = Player(playerId).state
        units.removePlayerFromUnit(officer, state)
        officers.remove(playerId)
    end
end)

local ox = {}

---@return { label: string, plate: string }[]
function ox.getVehicles(parameters)
    local vehicles = MySQL.rawExecute.await('SELECT `plate`, `model` FROM `vehicles` WHERE `owner` = ?', parameters) or
        {}

    for _, v in pairs(vehicles) do
        v.label = Ox.GetVehicleData(v.model)?.name or v.model
        v.model = nil
    end

    return vehicles
end

---@return table<string, { label: string } | string>[]
function ox.getLicenses(parameters)
    local licenses = MySQL.rawExecute.await(
        'SELECT ox_licenses.label, `issued` FROM character_licenses LEFT JOIN ox_licenses ON ox_licenses.name = character_licenses.name WHERE `charid` = ?',
        parameters) or {}

    return licenses
end

local selectCharacters = [[
    SELECT
        firstName,
        lastName,
        DATE_FORMAT(`dateofbirth`, "%Y-%m-%d") as dob,
        stateId
    FROM
        characters
]]

local selectCharactersByName = selectCharacters .. ' WHERE `firstName` = ? AND `lastName` LIKE ?'
local selectCharacterPartial = selectCharacters .. ' WHERE `lastName` LIKE ? OR `stateId` LIKE ?'

---@param parameters string[]
---@return PartialProfileData[]?
function ox.getCharacters(parameters, match)
    local query = match and selectCharactersByName or match == false and selectCharacterPartial or selectCharacters
    return MySQL.rawExecute.await(query, parameters)
end

local selectOfficers = [[
    SELECT
        firstName,
        lastName,
        characters.stateId,
        character_groups.grade AS grade,
        ox_mdt_profiles.image,
        ox_mdt_profiles.callSign
    FROM
        character_groups
    LEFT JOIN
        characters
    ON
        character_groups.charid = characters.charid
    LEFT JOIN
        ox_mdt_profiles
    ON
        characters.stateId = ox_mdt_profiles.stateId
    WHERE
        character_groups.name = "police"
]]

local selectOfficersByName = selectOfficers .. ' AND (`firstName` = ? AND `lastName` LIKE ?)'
local selectOfficersPartial = selectOfficers .. ' AND (`lastName` LIKE ? OR ox_mdt_profiles.stateId LIKE ?)'
local selectOfficersPaginate = selectOfficers .. 'LIMIT 9 OFFSET ?'
local selectOfficersByNamePaginate = selectOfficersByName .. ' LIMIT 9 OFFSET ?'
local selectOfficersPartialPaginate = selectOfficersPartial .. ' LIMIT 9 OFFSET ?'
local selectOfficersCount = selectOfficers:gsub('SELECT.-FROM', 'SELECT COUNT(*) FROM')

---@param parameters? string[]
---@param match? boolean
---@return Officer[]?
function ox.getOfficers(parameters, match)
    local query = match and selectOfficersByName or match == false and selectOfficersPartial or selectOfficers
    return MySQL.rawExecute.await(query, parameters)
end

---@param source number
---@param search string
utils.registerCallback('ox_mdt:fetchRoster', function(source, search)
    if search == '' then
        return {
            totalRecords = MySQL.prepare.await(selectOfficersCount),
            officers = MySQL.rawExecute.await(selectOfficersPaginate, { 0 })
        }
    end

    return dbSearch(function(parameters, match)
        local response = MySQL.rawExecute.await(match and selectOfficersByNamePaginate or selectOfficersPartialPaginate, parameters)
        print(match and selectOfficersByNamePaginate or selectOfficersPartialPaginate)
        print(json.encode(parameters))

        return {
            totalRecords = #response,
            officers = response,
        }
    end, search, 0)
end)

local selectWarrants = [[
    SELECT
        a.reportId,
        a.stateId,
        b.firstName,
        b.lastName,
        DATE_FORMAT(a.expiresAt, "%Y-%m-%d %T") AS expiresAt
    FROM
        `ox_mdt_warrants` a
    LEFT JOIN
        `characters` b
    ON
        a.stateid = b.stateid
]]

local selectWarrantsByName = selectWarrants .. ' WHERE `firstName` = ? AND `lastName` LIKE ?'
local selectWarrantsPartial = selectWarrants .. ' WHERE `lastName` LIKE ? OR a.stateId LIKE ?'

function ox.getWarrants(parameters, match)
    local query = match and selectWarrantsByName or match == false and selectWarrantsPartial or selectWarrants
    return MySQL.rawExecute.await(query, parameters)
end

local selectProfiles = [[
    SELECT
        characters.stateId,
        characters.firstName,
        characters.lastName,
        DATE_FORMAT(characters.dateofbirth, "%Y-%m-%d") AS dob,
        profile.image
    FROM
        characters
    LEFT JOIN
        ox_mdt_profiles profile
    ON
        profile.stateid = characters.stateid
    LIMIT 10 OFFSET ?
]]

local selectProfilesByName = selectProfiles:gsub('LIMIT', 'WHERE `firstName` = ? AND `lastName` LIKE ? LIMIT')
local selectProfilesPartial = selectProfiles:gsub('LIMIT', 'WHERE `lastName` LIKE ? OR characters.stateId LIKE ? LIMIT')

function ox.getProfiles(parameters, match)
    local query = match and selectProfilesByName or match == false and selectProfilesPartial or selectProfiles
    return MySQL.rawExecute.await(query, parameters)
end

---@param parameters { [1]: number }
---@return FetchOfficers?
function ox.getOfficersInvolved(parameters)
    return MySQL.rawExecute.await([[
        SELECT
            characters.firstName,
            characters.lastName,
            characters.stateId
        FROM
            ox_mdt_reports_officers officer
        LEFT JOIN
            characters
        ON
            characters.stateId = officer.stateId
        WHERE
            reportid = ?
    ]], parameters)
end

---@param parameters { [1]: number }
---@return FetchCriminals?
function ox.getCriminalsInvolved(parameters)
    return MySQL.rawExecute.await([[
        SELECT DISTINCT
            criminal.stateId,
            characters.firstName,
            characters.lastName,
            criminal.reduction,
            DATE_FORMAT(criminal.warrantExpiry, "%Y-%m-%d") AS warrantExpiry,
            criminal.processed,
            criminal.pleadedGuilty
        FROM
            ox_mdt_reports_criminals criminal
        LEFT JOIN
            characters
        ON
            characters.stateId = criminal.stateId
        WHERE
            reportid = ?
    ]], parameters)
end

---@param parameters { [1]: number }
---@return FetchCharges?
function ox.getCriminalCharges(parameters)
    return MySQL.rawExecute.await([[
        SELECT
            stateId,
            charge as label,
            time,
            fine,
            count
        FROM
            ox_mdt_reports_charges
        WHERE
            reportid = ?
        GROUP BY
            charge, stateId
    ]], parameters)
end

---@param parameters { [1]: string }
---@return Profile?
function ox.getCharacterProfile(parameters)
    ---@type Profile
    local profile = MySQL.rawExecute.await([[
        SELECT
            a.firstName,
            a.lastName,
            a.stateId,
            a.charid,
            DATE_FORMAT(a.dateofbirth, "%Y-%m-%d") AS dob,
            a.phoneNumber,
            b.image,
            b.notes
        FROM
            `characters` a
        LEFT JOIN
            `ox_mdt_profiles` b
        ON
            b.stateid = a.stateid
        WHERE
            a.stateId = ?
    ]], parameters)?[1]

    return profile
end

---@param parameters { [1]: number }
---@return Announcement[]?
function ox.getAnnouncements(parameters)
    return MySQL.rawExecute.await([[
        SELECT
            a.id,
            a.contents,
            a.creator AS stateId,
            b.firstName,
            b.lastName,
            DATE_FORMAT(a.createdAt, "%Y-%m-%d %T") AS createdAt
        FROM
            `ox_mdt_announcements` a
        LEFT JOIN
            `characters` b
        ON
            b.stateId = a.creator
        ORDER BY `createdAt` DESC LIMIT 5 OFFSET ?
    ]], parameters)
end

---@param source number
---@param data {stateId: string, group: string, grade: number}
utils.registerCallback('ox_mdt:setOfficerRank', function(source, data)
    local player = Ox.GetPlayerByFilter({stateId = data.stateId})

    -- todo: permission and security checks

    if player then
        for i = 1, #config.policeGroups do
            local group = config.policeGroups[i]
            -- if player has selected police group update it, otherwise remove all the other police groups
            if player.hasGroup(group) and group == data.group then
                player.setGroup(data.group, data.grade + 1)
            else
                player.setGroup(group, -1)
            end
        end

        return true
    end

    local charId = MySQL.prepare.await('SELECT `charid` FROM `characters` WHERE `stateId` = ?', { data.stateId })

    MySQL.prepare.await('UPDATE `character_groups` SET `grade` = ? WHERE `charId` = ? AND `name` = ? ', { data.grade + 1, charId, data.group })

    -- todo: delete other police groups from db?

    return true
end)

---@param source number
---@param stateId number
utils.registerCallback('ox_mdt:fireOfficer', function(source, stateId)
    -- todo: permission and security checks

    local player = Ox.GetPlayerByFilter({stateId = stateId})

    if player then
        for i = 1, #config.policeGroups do
            local group = config.policeGroups[i]
            player.setGroup(group, -1)
        end

        return true
    end

    local charId = MySQL.prepare.await('SELECT `charid` FROM `characters` WHERE `stateId` = ?', { stateId })

    -- todo: delete other police groups
    MySQL.prepare.await('DELETE FROM `character_groups` WHERE `charId` = ? AND `name` = ? ', { charId, 'police' })

    return true
end)

---@param source number
---@param stateId string
utils.registerCallback('ox_mdt:hireOfficer', function(source, stateId)
    -- todo: permission and security checks

    local player = Ox.GetPlayerByFilter({stateId = stateId})

    if player then
        if player.hasGroup(config.policeGroups) then return false end

        player.setGroup('police', 1)
        return true
    end

    local charId = MySQL.prepare.await('SELECT `charid` FROM `characters` WHERE `stateId` = ?', { stateId })

    local success = pcall(MySQL.prepare.await, 'INSERT INTO `character_groups` (`charId`, `name`, `grade`) VALUES (?, ?, ?)', { charId, 'police', 1 })

    return success
end)

return ox
