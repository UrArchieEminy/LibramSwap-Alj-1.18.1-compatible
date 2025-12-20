-- LibramSwap.lua (Turtle WoW 1.12 / Turtle WoW 1.18.x compatible)
-- Rank-aware version (handles "/cast Name(Rank X)" and plain "/cast Name").
-- Swaps relic-slot items for specific spells, but ONLY when the spell is ready (no CD/GCD).
-- Preserves Paladin Judgement gating (only swap ≤35% target HP) and per-spell throttles
-- that start AFTER the first successful swap for that spell.

-- =====================
-- Locals / Aliases
-- =====================
local GetContainerNumSlots  = GetContainerNumSlots
local GetContainerItemLink  = GetContainerItemLink
local UseContainerItem      = UseContainerItem
local GetInventoryItemLink  = GetInventoryItemLink
local GetSpellName          = GetSpellName
local GetSpellCooldown      = GetSpellCooldown
local GetActionText         = GetActionText
local GetTime               = GetTime
local string_find           = string.find
local BOOKTYPE_SPELL        = BOOKTYPE_SPELL or "spell"
local BOOKTYPE_PET          = BOOKTYPE_PET or "pet"
local BOOK_TYPES            = { BOOKTYPE_SPELL, BOOKTYPE_PET }

-- Relic slot (libram/idol/totem) is slot 18 in Vanilla/Turtle
local RELIC_SLOT = 18

-- Spells that should avoid GCD-triggering equip methods (cat spam like Claw)
local NO_GCD_SWAP_SPELLS = { ["Claw"] = true }

-- === Bag Index ===
local NameIndex   = {}  -- [itemName] = {bag=#, slot=#, link="|Hitem:..|h[Name]|h|r"}
local IdIndex     = {}  -- [itemID]   = {bag=#, slot=#, link=...}

-- === Spell cache ===
local SpellCache = {}

-- Safety: block swaps when vendor/bank/auction/trade/mail/quest/gossip is open
local function IsInteractionBusy()
    return (MerchantFrame and MerchantFrame:IsVisible())
        or (BankFrame and BankFrame:IsVisible())
        or (AuctionFrame and AuctionFrame:IsVisible())
        or (TradeFrame and TradeFrame:IsVisible())
        or (MailFrame and MailFrame:IsVisible())
        or (QuestFrame and QuestFrame:IsVisible())
        or (GossipFrame and GossipFrame:IsVisible())
end

local lastEquippedRelic = nil

-- Global (generic) throttle for GCD-based swaps
local lastSwapTime = 0

-- Track idle time and Devotion Aura state (Paladin-only behavior, but state is always present)
local lastInputTime = 0
local IDLE_DEVOTION_DELAY = 1.5
local isProvidingDevotionAura = false

-- Shaman low-health Rebirth check throttle
local lastRebirthSwapTime = 0
local REBIRTH_CHECK_THROTTLE = 1.0

-- =====================
-- Config (Saved Vars)
-- =====================
LibramSwapDb = LibramSwapDb or {
    enabled = true,
    spam = true,

    -- user-selected ruleset: "paladin", "druid", "shaman"
    classMode = nil,

    -- PALADIN choose-one
    consecrationMode = "faithful", -- faithful | farraki
    holyStrikeMode   = "eternal",  -- eternal | radiance

    -- DRUID choose-one
    druidRipMode          = "emerald",  -- emerald | laceration | savagery
    druidBiteMode         = "emerald",  -- emerald | laceration
    druidRakeMode         = "ferocity", -- ferocity | savagery
    druidHealingTouchMode = "health",   -- health | longevity
    druidMoonfireMode     = "moonfang", -- moonfang | moon

    -- SHAMAN choose-one
    shamanEarthShockMode       = "broken",   -- broken | stone | rage | rotten
    shamanFrostShockMode       = "stone",    -- stone | rage
    shamanFlameShockMode       = "stone",    -- stone | rage | flicker
    shamanLightningBoltMode    = "crackling",-- crackling | static | storm
    shamanLesserHealMode       = "life",     -- life | sustaining | corrupted
    shamanWaterShieldMode      = "tides",    -- tides | calming
    shamanLightningStrikeMode  = "crackling",-- crackling | tides | calming
}

-- Keep original generic throttle for GCD spells
local SWAP_THROTTLE_GENERIC = 1.48

-- Per-spell throttles (begin applying AFTER the first successful swap of that spell)
local PER_SPELL_THROTTLE = {
    ["Judgement"]       = 7.8,
}

-- spell ready allowance (in seconds)
local SPELL_READY_ALLOWANCE = 0.15

-- =====================
-- PALADIN relics
-- =====================
local CONSECRATION_FAITHFUL = "Libram of the Faithful"
local CONSECRATION_FARRAKI  = "Libram of the Farraki Zealot"

local HOLY_STRIKE_ETERNAL_TOWER = "Libram of the Eternal Tower"
local HOLY_STRIKE_RADIANCE      = "Libram of Radiance"

local PALADIN_RELIC_MAP = {
    ["Consecration"]                  = CONSECRATION_FAITHFUL,
    ["Holy Shield"]                   = "Libram of the Dreamguard",
    ["Holy Light"]                    = "Libram of Radiance",
    ["Flash of Light"]                = "Libram of Light",
    ["Cleanse"]                       = "Libram of Grace",
    ["Hammer of Justice"]             = "Libram of the Justicar",
    ["Hand of Freedom"]               = "Libram of the Resolute",
    ["Crusader Strike"]               = "Libram of the Eternal Tower",
    ["Holy Strike"]                   = HOLY_STRIKE_ETERNAL_TOWER,
    ["Judgement"]                     = "Libram of Final Judgement",
    ["Seal of Wisdom"]                = "Libram of Hope",
    ["Seal of Light"]                 = "Libram of Hope",
    ["Seal of Justice"]               = "Libram of Hope",
    ["Seal of Command"]               = "Libram of Hope",
    ["Seal of the Crusader"]          = "Libram of Fervor",
    ["Seal of Righteousness"]         = "Libram of Hope",
    ["Devotion Aura"]                 = "Libram of Truth",
    ["Blessing of Wisdom"]            = "Libram of Veracity",
    ["Blessing of Might"]             = "Libram of Veracity",
    ["Blessing of Kings"]             = "Libram of Veracity",
    ["Blessing of Sanctuary"]         = "Libram of Veracity",
    ["Blessing of Light"]             = "Libram of Veracity",
    ["Blessing of Salvation"]         = "Libram of Veracity",
    ["Greater Blessing of Wisdom"]    = "Libram of Veracity",
    ["Greater Blessing of Kings"]     = "Libram of Veracity",
    ["Greater Blessing of Sanctuary"] = "Libram of Veracity",
    ["Greater Blessing of Light"]     = "Libram of Veracity",
    ["Greater Blessing of Salvation"] = "Libram of Veracity",
}

-- =====================
-- DRUID relics
-- =====================
local DRUID_IDOLS = {
    rip = {
        emerald    = "Idol of the Emerald Rot",
        laceration = "Idol of Laceration",
        savagery   = "Idol of Savagery",
    },
    bite = {
        emerald    = "Idol of the Emerald Rot",
        laceration = "Idol of Laceration",
    },
    rake = {
        ferocity = "Idol of Ferocity",
        savagery = "Idol of Savagery",
    },
    ht = {
        health    = "Idol of Health",
        longevity = "Idol of Longevity",
    },
    moonfire = {
        moonfang = "Idol of the Moonfang",
        moon     = "Idol of the Moon",
    },
}

local DRUID_FIXED_MAP = {
    ["Starfire"]           = { "Idol of Ebb and Flow" },
    ["Regrowth"]           = { "Idol of the Forgotten Wilds" },
    ["Savage Bite"]        = { "Idol of the Moonfang" },
    ["Shred"]              = { "Idol of the Moonfang" },
    ["Claw"]               = { "Idol of Ferocity" },

    ["Bear Form"]          = { "Idol of the Wildshifter" },
    ["Dire Bear Form"]     = { "Idol of the Wildshifter" },
    ["Cat Form"]           = { "Idol of the Wildshifter" },
    ["Travel Form"]        = { "Idol of the Wildshifter" },
    ["Swift Travel Form"]  = { "Idol of the Wildshifter" },
    ["Moonkin Form"]       = { "Idol of the Wildshifter" },
    ["Tree of Life Form"]  = { "Idol of the Wildshifter" },

    ["Aquatic Form"]       = { "Idol of Fluidity" },
    ["Maul"]               = { "Idol of Brutality" },
    ["Swipe"]              = { "Idol of Brutality" },
    ["Thorns"]             = { "Idol of Evergrowth" },
    ["Insect Swarm"]       = { "Idol of Propagation" },
    ["Rejuvenation"]       = { "Idol of Rejuvenation" },
    ["Demoralizing Roar"]  = { "Idol of the Apex Predator" },
    ["Entangling Roots"]   = { "Idol of the Thorned Grove" },
}

-- =====================
-- SHAMAN relics
-- =====================
local SHAMAN_TOTEMS = {
    earthshock = {
        broken = "Totem of Broken Earth",
        stone  = "Totem of the Stone Breaker",
        rage   = "Totem of Rage",
        rotten = "Totem of the Rotten Roots",
    },
    frostshock = {
        stone = "Totem of the Stone Breaker",
        rage  = "Totem of Rage",
    },
    flameshock = {
        stone   = "Totem of the Stone Breaker",
        rage    = "Totem of Rage",
        flicker = "Totem of the Endless Flicker",
    },
    lightningbolt = {
        crackling = "Totem of Crackling Thunder",
        static    = "Totem of Static Charge",
        storm     = "Totem of the Storm",
    },
    lhw = {
        life      = "Totem of Life",
        sustaining= "Totem of Sustaining",
        corrupted = "Totem of the Corrupted Current",
    },
    watershield = {
        tides   = "Totem of Tides",
        calming = "Totem of the Calming River",
    },
    lightningstrike = {
        crackling = "Totem of Crackling Thunder",
        tides     = "Totem of Tides",
        calming   = "Totem of the Calming River",
    },
}

local SHAMAN_FIXED_MAP = {
    ["Strength of Earth Totem"] = { "Totem of Earthstorm" },
    ["Grace of Air"]            = { "Totem of Earthstorm" },
    ["Molten Blast"]            = { "Totem of Eruption" },
    ["Hex"]                     = { "Totem of Bad Mojo" },
    ["Chain Lightning"]         = { "Totem of the Storm" }
}
local SHAMAN_REBIRTH_TOTEM = "Totem of Rebirth"

-- =====================
-- Dynamic watched items index
-- =====================
local WatchedNames = {}

local function wipeTable(t) for k in pairs(t) do t[k] = nil end end
local function AddWatched(name) if name and name ~= "" then WatchedNames[name] = true end end

local function RefreshWatchedNames()
    wipeTable(WatchedNames)
    local mode = LibramSwapDb.classMode
    if not mode then return end

    if mode == "paladin" then
        for _, itemName in pairs(PALADIN_RELIC_MAP) do AddWatched(itemName) end
        AddWatched(CONSECRATION_FAITHFUL); AddWatched(CONSECRATION_FARRAKI)
        AddWatched(HOLY_STRIKE_ETERNAL_TOWER); AddWatched(HOLY_STRIKE_RADIANCE)

    elseif mode == "druid" then
        -- choose-one idol options
        for _, v in pairs(DRUID_IDOLS.rip) do AddWatched(v) end
        for _, v in pairs(DRUID_IDOLS.bite) do AddWatched(v) end
        for _, v in pairs(DRUID_IDOLS.rake) do AddWatched(v) end
        for _, v in pairs(DRUID_IDOLS.ht) do AddWatched(v) end
        for _, v in pairs(DRUID_IDOLS.moonfire) do AddWatched(v) end
        -- fixed list
        for _, list in pairs(DRUID_FIXED_MAP) do for _, v in ipairs(list) do AddWatched(v) end end

    elseif mode == "shaman" then
        for _, v in pairs(SHAMAN_TOTEMS.earthshock) do AddWatched(v) end
        for _, v in pairs(SHAMAN_TOTEMS.frostshock) do AddWatched(v) end
        for _, v in pairs(SHAMAN_TOTEMS.flameshock) do AddWatched(v) end
        for _, v in pairs(SHAMAN_TOTEMS.lightningbolt) do AddWatched(v) end
        for _, v in pairs(SHAMAN_TOTEMS.lhw) do AddWatched(v) end
        for _, v in pairs(SHAMAN_TOTEMS.watershield) do AddWatched(v) end
        for _, v in pairs(SHAMAN_TOTEMS.lightningstrike) do AddWatched(v) end
        for _, list in pairs(SHAMAN_FIXED_MAP) do for _, v in ipairs(list) do AddWatched(v) end end
        AddWatched(SHAMAN_REBIRTH_TOTEM)
    end
end

-- Extract numeric itemID from an item link (1.12 safe)
local function ItemIDFromLink(link)
    if not link then return nil end
    local _, _, id = string_find(link, "item:(%d+)")
    return id and tonumber(id) or nil
end

local function BuildBagIndex()
    wipeTable(NameIndex)
    wipeTable(IdIndex)

    if not LibramSwapDb.classMode then return end

    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag)
        if slots and slots > 0 then
            for slot = 1, slots do
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local _, _, bracketName = string_find(link, "%[(.-)%]")
                    if bracketName and WatchedNames[bracketName] then
                        NameIndex[bracketName] = { bag = bag, slot = slot, link = link }
                        local id = ItemIDFromLink(link)
                        if id then
                            IdIndex[id] = { bag = bag, slot = slot, link = link }
                        end
                    end
                end
            end
        end
    end
end

local function ReindexAll()
    RefreshWatchedNames()
    BuildBagIndex()
end

-- =====================
-- Class selection UX
-- =====================
local function PrintClassPrompt()
    DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Select a class ruleset: |cFFFFD700/ls class paladin|r, |cFFFFD700/ls class druid|r, or |cFFFFD700/ls class shaman|r")
end

local function PrintClassCommands(mode)
    if mode == "paladin" then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Class set to |cFFFFD700PALADIN|r")
        DEFAULT_CHAT_FRAME:AddMessage("  |cFFFFD700/ls consecration [faithful / farraki]|r")
        DEFAULT_CHAT_FRAME:AddMessage("  |cFFFFD700/ls holystrike [eternal / radiance]|r")
    elseif mode == "druid" then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Class set to |cFFFFD700DRUID|r")
        DEFAULT_CHAT_FRAME:AddMessage("  |cFFFFD700/ls rip [emerald / laceration / savagery]|r")
        DEFAULT_CHAT_FRAME:AddMessage("  |cFFFFD700/ls bite [emerald / laceration]|r")
        DEFAULT_CHAT_FRAME:AddMessage("  |cFFFFD700/ls rake [ferocity / savagery]|r")
        DEFAULT_CHAT_FRAME:AddMessage("  |cFFFFD700/ls healingtouch [health / longevity]|r")
        DEFAULT_CHAT_FRAME:AddMessage("  |cFFFFD700/ls moonfire [moonfang / moon]|r")
    elseif mode == "shaman" then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Class set to |cFFFFD700SHAMAN|r")
        DEFAULT_CHAT_FRAME:AddMessage("  |cFFFFD700/ls earthshock [broken / stone / rage / rotten]|r")
        DEFAULT_CHAT_FRAME:AddMessage("  |cFFFFD700/ls frostshock [stone / rage]|r")
        DEFAULT_CHAT_FRAME:AddMessage("  |cFFFFD700/ls flameshock [stone / rage / flicker]|r")
        DEFAULT_CHAT_FRAME:AddMessage("  |cFFFFD700/ls lightningbolt [crackling / static / storm]|r")
        DEFAULT_CHAT_FRAME:AddMessage("  |cFFFFD700/ls lesserheal [life / sustaining / corrupted]|r")
        DEFAULT_CHAT_FRAME:AddMessage("  |cFFFFD700/ls watershield [tides / calming]|r")
        DEFAULT_CHAT_FRAME:AddMessage("  |cFFFFD700/ls lightningstrike [crackling / tides / calming]|r")
        DEFAULT_CHAT_FRAME:AddMessage("  Special: if HP ≤ 5% and Reincarnation is ready, equips |cFFFFD700Totem of Rebirth|r.")
    end
    DEFAULT_CHAT_FRAME:AddMessage("  |cFFFFD700/ls status|r, |cFFFFD700/ls spam|r, |cFFFFD700/ls on|r, |cFFFFD700/ls off|r")
end

-- =====================
-- Event frame
-- =====================
local LibramSwapFrame = CreateFrame("Frame")
LibramSwapFrame:RegisterEvent("PLAYER_LOGIN")
LibramSwapFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
LibramSwapFrame:RegisterEvent("BAG_UPDATE")

LibramSwapFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        if not LibramSwapDb.classMode then
            PrintClassPrompt()
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Using ruleset: |cFFFFD700" .. string.upper(LibramSwapDb.classMode) .. "|r (change: |cFFFFD700/ls class <paladin|druid|shaman>|r)")
        end

        ReindexAll()
        lastInputTime = GetTime()
        isProvidingDevotionAura = false
        lastRebirthSwapTime = 0

    elseif event == "BAG_UPDATE" then
        BuildBagIndex()
    end
end)

-- =====================
-- Rank-aware spell parsing
-- =====================
local function NormalizeSpellName(name)
    if not name then return nil end
    name = string.gsub(name, "^%s*!", "")
    name = string.gsub(name, "^%s+", "")
    name = string.gsub(name, "%s+$", "")
    return name
end

local function SplitNameAndRank(spellSpec)
    if not spellSpec then return nil, nil end
    spellSpec = NormalizeSpellName(spellSpec)
    local _, _, base, rnum = string_find(spellSpec, "^(.-)%s*%(%s*[Rr][Aa][Nn][Kk]%s*(%d+)%s*%)%s*$")
    if base then
        return (string.gsub(base, "%s+$", "")), ("Rank " .. rnum)
    end
    return (string.gsub(spellSpec, "%s+$", "")), nil
end

-- gets spell readiness by ID
local function IsSpellReadyById(spellId, bookType)
    local start, duration, enabled = GetSpellCooldown(spellId, bookType or BOOKTYPE_SPELL)
    if not (start and duration) then return false end
    if enabled == 0 then return false end
    if start == 0 or duration == 0 then return true end
    local remaining = (start + duration) - GetTime()
    return remaining <= SPELL_READY_ALLOWANCE
end

-- Accepts: "Name" or "Name(Rank X)". If a rank is specified, require that exact rank.
local function IsSpellReady(spellSpec)
    local cache = SpellCache[spellSpec]
    local spellId = cache and cache.id or nil
    local bookType = cache and cache.bookType or nil
    local base, reqRank = nil, nil

    if spellId and bookType then
        base, reqRank = SplitNameAndRank(spellSpec)
        if not base then return false end
        local n, r = GetSpellName(spellId, bookType)
        if (not n) or (n ~= base) or (reqRank and r ~= reqRank) then
            spellId = nil
            bookType = nil
        end
    end

    if not spellId then
        if not base then
            base, reqRank = SplitNameAndRank(spellSpec)
        end
        if not base then return false end

        for _, bt in ipairs(BOOK_TYPES) do
            for i = 1, 300 do
                local name, rank = GetSpellName(i, bt)
                if not name then break end
                local nameMatches = (name == base)
                local rankMatches = (not reqRank) or (rank and rank == reqRank)
                if nameMatches and rankMatches then
                    spellId = i
                    bookType = bt
                    SpellCache[spellSpec] = { id = i, bookType = bt }
                    break
                end
            end
            if spellId then break end
        end
    end

    if not spellId then return false end
    return IsSpellReadyById(spellId, bookType)
end

local function FindSpellIdByName(name, rank)
    name = NormalizeSpellName(name)
    if not name then return nil, nil end
    for _, bt in ipairs(BOOK_TYPES) do
        for i = 1, 300 do
            local n, r = GetSpellName(i, bt)
            if not n then break end
            if n == name and (not rank or rank == "" or r == rank) then
                return i, bt
            end
        end
    end
    return nil, nil
end

-- =====================
-- Helpers
-- =====================
local function HasItemInBags(itemName)
    local ref = NameIndex[itemName]
    if ref then
        local current = GetContainerItemLink(ref.bag, ref.slot)
        if current and string_find(current, itemName, 1, true) then
            return ref.bag, ref.slot
        end
        BuildBagIndex()
        ref = NameIndex[itemName]
        if ref then
            local verify = GetContainerItemLink(ref.bag, ref.slot)
            if verify and string_find(verify, itemName, 1, true) then
                return ref.bag, ref.slot
            end
        end
        return nil
    end

    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag)
        if slots and slots > 0 then
            for slot = 1, slots do
                local link = GetContainerItemLink(bag, slot)
                if link and string.find(link, itemName, 1, true) then
                    NameIndex[itemName] = { bag = bag, slot = slot, link = link }
                    local id = ItemIDFromLink(link)
                    if id then IdIndex[id] = { bag = bag, slot = slot, link = link } end
                    return bag, slot
                end
            end
        end
    end
    return nil
end

local function HasRelic(itemName)
    return (lastEquippedRelic == itemName) or HasItemInBags(itemName)
end

local function TargetHealthPct()
    if not UnitExists("target") or UnitIsDeadOrGhost("target") then return nil end
    local maxHP = UnitHealthMax("target")
    if not maxHP or maxHP == 0 then return nil end
    return (UnitHealth("target") / maxHP) * 100
end

-- Per-spell throttle state
local perSpellHasSwapped = {}
local perSpellLastSwap   = {}

local function EquipRelicForSpell(spellName, itemName)
    local equipped = GetInventoryItemLink("player", RELIC_SLOT)
    if equipped and string_find(equipped, itemName, 1, true) then
        lastEquippedRelic = itemName
        return false
    end

    if IsInteractionBusy() then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r |cFFFF5555Swap blocked (interaction window open).|r")
        return false
    end

    local now = GetTime()
    local perDur = PER_SPELL_THROTTLE[spellName]
    if perDur then
        if perSpellHasSwapped[spellName] then
            local last = perSpellLastSwap[spellName] or 0
            if (now - last) < perDur then
                return false
            end
        end
    else
        if (now - lastSwapTime) < SWAP_THROTTLE_GENERIC then
            return false
        end
    end

    local bag, slot = HasItemInBags(itemName)
    if bag and slot then
        if CursorHasItem and CursorHasItem() then return false end
        if NO_GCD_SWAP_SPELLS[spellName] and PickupContainerItem and PickupInventoryItem then
            if ClearCursor then ClearCursor() end
            PickupContainerItem(bag, slot)
            if CursorHasItem and CursorHasItem() then
                PickupInventoryItem(RELIC_SLOT)
                if CursorHasItem and CursorHasItem() then
                    -- Put it back if swap failed to avoid cursor lock
                    PickupContainerItem(bag, slot)
                end
            end
        else
            UseContainerItem(bag, slot)
        end

        local equippedNow = GetInventoryItemLink("player", RELIC_SLOT)
        if not (equippedNow and string_find(equippedNow, itemName, 1, true)) then
            return false
        end
        lastEquippedRelic = itemName

        if perDur then
            if not perSpellHasSwapped[spellName] then perSpellHasSwapped[spellName] = true end
            perSpellLastSwap[spellName] = now
        else
            lastSwapTime = now
        end

        if LibramSwapDb.spam then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Equipped |cFFFFD700" .. itemName .. "|r |cFF888888(" .. spellName .. ")|r")
        end
        return true
    end
    return false
end

-- =====================
-- Resolver (classMode-aware + choose-one)
-- =====================
local function ResolveRelicForSpell(spellName)
    local mode = LibramSwapDb.classMode
    if not mode then return nil end

    if mode == "paladin" then
        if spellName == "Consecration" then
            local primary = (LibramSwapDb.consecrationMode == "farraki") and CONSECRATION_FARRAKI or CONSECRATION_FAITHFUL
            local fallback= (primary == CONSECRATION_FARRAKI) and CONSECRATION_FAITHFUL or CONSECRATION_FARRAKI
            if HasRelic(primary) then return primary end
            if HasRelic(fallback) then return fallback end
            return nil
        end

        if spellName == "Holy Strike" then
            local primary = (LibramSwapDb.holyStrikeMode == "radiance") and HOLY_STRIKE_RADIANCE or HOLY_STRIKE_ETERNAL_TOWER
            local fallback= (primary == HOLY_STRIKE_RADIANCE) and HOLY_STRIKE_ETERNAL_TOWER or HOLY_STRIKE_RADIANCE
            if HasRelic(primary) then return primary end
            if HasRelic(fallback) then return fallback end
            return nil
        end

        local libram = PALADIN_RELIC_MAP[spellName]
        if not libram then return nil end

        if spellName == "Flash of Light" then
            if not HasRelic("Libram of Light") and HasRelic("Libram of Divinity") then
                libram = "Libram of Divinity"
            end
        end
        return libram
    end

    if mode == "druid" then
        if spellName == "Rip" then
            local primary = DRUID_IDOLS.rip[LibramSwapDb.druidRipMode]
            if primary and HasRelic(primary) then return primary end
            -- fallback order (stable)
            local order = { "emerald", "laceration", "savagery" }
            for _, k in ipairs(order) do
                local it = DRUID_IDOLS.rip[k]
                if it and HasRelic(it) then return it end
            end
            return nil
        end

        if spellName == "Ferocious Bite" then
            local primary = DRUID_IDOLS.bite[LibramSwapDb.druidBiteMode]
            if primary and HasRelic(primary) then return primary end
            local order = { "emerald", "laceration" }
            for _, k in ipairs(order) do
                local it = DRUID_IDOLS.bite[k]
                if it and HasRelic(it) then return it end
            end
            return nil
        end

        if spellName == "Rake" then
            local primary = DRUID_IDOLS.rake[LibramSwapDb.druidRakeMode]
            if primary and HasRelic(primary) then return primary end
            local order = { "ferocity", "savagery" }
            for _, k in ipairs(order) do
                local it = DRUID_IDOLS.rake[k]
                if it and HasRelic(it) then return it end
            end
            return nil
        end

        if spellName == "Healing Touch" then
            local primary = DRUID_IDOLS.ht[LibramSwapDb.druidHealingTouchMode]
            if primary and HasRelic(primary) then return primary end
            local order = { "health", "longevity" }
            for _, k in ipairs(order) do
                local it = DRUID_IDOLS.ht[k]
                if it and HasRelic(it) then return it end
            end
            return nil
        end

        if spellName == "Moonfire" then
            local primary = DRUID_IDOLS.moonfire[LibramSwapDb.druidMoonfireMode]
            if primary and HasRelic(primary) then return primary end
            local order = { "moonfang", "moon" }
            for _, k in ipairs(order) do
                local it = DRUID_IDOLS.moonfire[k]
                if it and HasRelic(it) then return it end
            end
            return nil
        end

        local fixed = DRUID_FIXED_MAP[spellName]
        if not fixed then return nil end
        for _, it in ipairs(fixed) do
            if HasRelic(it) then return it end
        end
        return nil
    end

    if mode == "shaman" then
        if spellName == "Earth Shock" then
            local primary = SHAMAN_TOTEMS.earthshock[LibramSwapDb.shamanEarthShockMode]
            if primary and HasRelic(primary) then return primary end
            local order = { "broken", "stone", "rage", "rotten" }
            for _, k in ipairs(order) do
                local it = SHAMAN_TOTEMS.earthshock[k]
                if it and HasRelic(it) then return it end
            end
            return nil
        end

        if spellName == "Frost Shock" then
            local primary = SHAMAN_TOTEMS.frostshock[LibramSwapDb.shamanFrostShockMode]
            if primary and HasRelic(primary) then return primary end
            local order = { "stone", "rage" }
            for _, k in ipairs(order) do
                local it = SHAMAN_TOTEMS.frostshock[k]
                if it and HasRelic(it) then return it end
            end
            return nil
        end

        if spellName == "Flame Shock" then
            local primary = SHAMAN_TOTEMS.flameshock[LibramSwapDb.shamanFlameShockMode]
            if primary and HasRelic(primary) then return primary end
            local order = { "stone", "rage", "flicker" }
            for _, k in ipairs(order) do
                local it = SHAMAN_TOTEMS.flameshock[k]
                if it and HasRelic(it) then return it end
            end
            return nil
        end

        if spellName == "Lightning Bolt" then
            local primary = SHAMAN_TOTEMS.lightningbolt[LibramSwapDb.shamanLightningBoltMode]
            if primary and HasRelic(primary) then return primary end
            local order = { "crackling", "static", "storm" }
            for _, k in ipairs(order) do
                local it = SHAMAN_TOTEMS.lightningbolt[k]
                if it and HasRelic(it) then return it end
            end
            return nil
        end

        if spellName == "Lesser Healing Wave" then
            local primary = SHAMAN_TOTEMS.lhw[LibramSwapDb.shamanLesserHealMode]
            if primary and HasRelic(primary) then return primary end
            local order = { "life", "sustaining", "corrupted" }
            for _, k in ipairs(order) do
                local it = SHAMAN_TOTEMS.lhw[k]
                if it and HasRelic(it) then return it end
            end
            return nil
        end

        if spellName == "Water Shield" then
            local primary = SHAMAN_TOTEMS.watershield[LibramSwapDb.shamanWaterShieldMode]
            if primary and HasRelic(primary) then return primary end
            local order = { "tides", "calming" }
            for _, k in ipairs(order) do
                local it = SHAMAN_TOTEMS.watershield[k]
                if it and HasRelic(it) then return it end
            end
            return nil
        end

        if spellName == "Lightning Strike" then
            local primary = SHAMAN_TOTEMS.lightningstrike[LibramSwapDb.shamanLightningStrikeMode]
            if primary and HasRelic(primary) then return primary end
            local order = { "crackling", "tides", "calming" }
            for _, k in ipairs(order) do
                local it = SHAMAN_TOTEMS.lightningstrike[k]
                if it and HasRelic(it) then return it end
            end
            return nil
        end

        local fixed = SHAMAN_FIXED_MAP[spellName]
        if not fixed then return nil end
        for _, it in ipairs(fixed) do
            if HasRelic(it) then return it end
        end
        return nil
    end

    return nil
end

-- =====================
-- Hidden Tooltip (action bar spell read)
-- =====================
local hiddenActionTooltip = CreateFrame("GameTooltip", "LibramSwapActionTooltip", UIParent, "GameTooltipTemplate")

local function GetActionSpellName(slot)
    hiddenActionTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    hiddenActionTooltip:SetAction(slot)
    local name = LibramSwapActionTooltipTextLeft1:GetText()
    local rank = LibramSwapActionTooltipTextRight1:GetText()
    hiddenActionTooltip:Hide()
    return name, rank
end

-- =====================
-- OnUpdate: paladin devotion idle + shaman rebirth condition
-- =====================
LibramSwapFrame:SetScript("OnUpdate", function(self, elapsed)
    if not LibramSwapDb.enabled then return end
    if not LibramSwapDb.classMode then return end

    local now = GetTime()

    -- PALADIN: idle devotion swap
    if LibramSwapDb.classMode == "paladin" then
        if isProvidingDevotionAura and lastInputTime > 0 and (now - lastInputTime) >= IDLE_DEVOTION_DELAY then
            local devotionLibram = "Libram of Truth"
            if HasRelic(devotionLibram) then
                EquipRelicForSpell("Devotion Aura", devotionLibram)
            end
            lastInputTime = now
        end
    end

    -- SHAMAN: low HP + Reincarnation ready -> Totem of Rebirth
    if LibramSwapDb.classMode == "shaman" then
        if (now - lastRebirthSwapTime) >= REBIRTH_CHECK_THROTTLE then
            lastRebirthSwapTime = now
            local maxHP = UnitHealthMax("player")
            if maxHP and maxHP > 0 then
                local hpPct = (UnitHealth("player") / maxHP) * 100
                if hpPct <= 5 then
                    if IsSpellReady("Reincarnation") then
                        if HasRelic(SHAMAN_REBIRTH_TOTEM) then
                            EquipRelicForSpell("Reincarnation", SHAMAN_REBIRTH_TOTEM)
                        end
                    end
                end
            end
        end
    end
end)

-- =====================
-- Hooks (CastSpellByName / CastSpell / UseAction)
-- =====================
local Original_CastSpellByName = CastSpellByName
local Original_CastSpell = CastSpell
local Original_UseAction = UseAction

local function HandleSpellCast(base, rank, spellId, bookType)
    if not LibramSwapDb.enabled then return end
    if not LibramSwapDb.classMode then return end
    base = NormalizeSpellName(base)
    if not base or base == "" then return end

    -- any spell cast counts as input
    lastInputTime = GetTime()

    -- Paladin-only: track provider of Devotion Aura
    if LibramSwapDb.classMode == "paladin" then
        if base == "Devotion Aura" then
            isProvidingDevotionAura = true
        elseif string_find(base, "Aura", 1, true) then
            isProvidingDevotionAura = false
        end
    end

    local relic = ResolveRelicForSpell(base)
    if not relic then return end

    -- readiness
    local ready
    if spellId then
        local bt = bookType
        if not bt then
            local n = GetSpellName(spellId, BOOKTYPE_SPELL)
            if n == base then
                bt = BOOKTYPE_SPELL
            else
                local pn = GetSpellName(spellId, BOOKTYPE_PET)
                if pn == base then
                    bt = BOOKTYPE_PET
                end
            end
        end
        ready = IsSpellReadyById(spellId, bt)
    else
        local spec = (rank and rank ~= "") and (base .. "(" .. rank .. ")") or base
        ready = IsSpellReady(spec)
    end
    if not ready then return end

    -- Paladin Judgement gating
    if LibramSwapDb.classMode == "paladin" and base == "Judgement" then
        local hp = TargetHealthPct()
        if hp and hp <= 35 then
            EquipRelicForSpell(base, relic)
        end
    else
        EquipRelicForSpell(base, relic)
    end
end

function CastSpellByName(spellName, bookType)
    local name, rank = SplitNameAndRank(spellName)
    HandleSpellCast(name, rank)
    return Original_CastSpellByName(spellName, bookType)
end

function CastSpell(spellIndex, bookType)
    local bt = bookType or BOOKTYPE_SPELL
    if bt ~= BOOKTYPE_SPELL and bt ~= BOOKTYPE_PET then
        return Original_CastSpell(spellIndex, bookType)
    end
    local name, rank = GetSpellName(spellIndex, bt)
    HandleSpellCast(name, rank, spellIndex, bt)
    return Original_CastSpell(spellIndex, bookType)
end

function UseAction(slot, checkCursor, onSelf)
    if GetActionText(slot) then
        return Original_UseAction(slot, checkCursor, onSelf)
    end

    local name, rank = GetActionSpellName(slot)

    local spellId, bookType = FindSpellIdByName(name, rank)
    if not spellId and name then
        spellId, bookType = FindSpellIdByName(name, nil)
    end

    HandleSpellCast(name, rank, spellId, bookType)
    return Original_UseAction(slot, checkCursor, onSelf)
end

-- =====================
-- Slash Commands
-- =====================
local function trim(s) return (string.gsub(s or "", "^%s*(.-)%s*$", "%1")) end

local function printStatus()
    local status = LibramSwapDb.enabled and "|cFF00FF00ENABLED|r" or "|cFFFF0000DISABLED|r"
    DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap] Status:|r " .. status)

    local spamStatus = LibramSwapDb.spam and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"
    DEFAULT_CHAT_FRAME:AddMessage("  Swap messages: " .. spamStatus)

    if not LibramSwapDb.classMode then
        DEFAULT_CHAT_FRAME:AddMessage("  Class ruleset: |cFFFF5555NOT SET|r (use |cFFFFD700/ls class <paladin|druid|shaman>|r)")
        return
    end

    DEFAULT_CHAT_FRAME:AddMessage("  Class ruleset: |cFFFFD700" .. string.upper(LibramSwapDb.classMode) .. "|r")

    if LibramSwapDb.classMode == "paladin" then
        local consec = (LibramSwapDb.consecrationMode == "farraki") and CONSECRATION_FARRAKI or CONSECRATION_FAITHFUL
        local hs     = (LibramSwapDb.holyStrikeMode == "radiance") and HOLY_STRIKE_RADIANCE or HOLY_STRIKE_ETERNAL_TOWER
        DEFAULT_CHAT_FRAME:AddMessage("  Consecration: |cFFFFD700" .. consec .. "|r")
        DEFAULT_CHAT_FRAME:AddMessage("  Holy Strike:  |cFFFFD700" .. hs .. "|r")

    elseif LibramSwapDb.classMode == "druid" then
        DEFAULT_CHAT_FRAME:AddMessage("  Rip:           |cFFFFD700" .. (DRUID_IDOLS.rip[LibramSwapDb.druidRipMode] or "?") .. "|r")
        DEFAULT_CHAT_FRAME:AddMessage("  Ferocious Bite:|cFFFFD700" .. (DRUID_IDOLS.bite[LibramSwapDb.druidBiteMode] or "?") .. "|r")
        DEFAULT_CHAT_FRAME:AddMessage("  Rake:          |cFFFFD700" .. (DRUID_IDOLS.rake[LibramSwapDb.druidRakeMode] or "?") .. "|r")
        DEFAULT_CHAT_FRAME:AddMessage("  Healing Touch: |cFFFFD700" .. (DRUID_IDOLS.ht[LibramSwapDb.druidHealingTouchMode] or "?") .. "|r")
        DEFAULT_CHAT_FRAME:AddMessage("  Moonfire:      |cFFFFD700" .. (DRUID_IDOLS.moonfire[LibramSwapDb.druidMoonfireMode] or "?") .. "|r")

    elseif LibramSwapDb.classMode == "shaman" then
        DEFAULT_CHAT_FRAME:AddMessage("  Earth Shock:      |cFFFFD700" .. (SHAMAN_TOTEMS.earthshock[LibramSwapDb.shamanEarthShockMode] or "?") .. "|r")
        DEFAULT_CHAT_FRAME:AddMessage("  Frost Shock:      |cFFFFD700" .. (SHAMAN_TOTEMS.frostshock[LibramSwapDb.shamanFrostShockMode] or "?") .. "|r")
        DEFAULT_CHAT_FRAME:AddMessage("  Flame Shock:      |cFFFFD700" .. (SHAMAN_TOTEMS.flameshock[LibramSwapDb.shamanFlameShockMode] or "?") .. "|r")
        DEFAULT_CHAT_FRAME:AddMessage("  Lightning Bolt:   |cFFFFD700" .. (SHAMAN_TOTEMS.lightningbolt[LibramSwapDb.shamanLightningBoltMode] or "?") .. "|r")
        DEFAULT_CHAT_FRAME:AddMessage("  Lesser Heal Wave: |cFFFFD700" .. (SHAMAN_TOTEMS.lhw[LibramSwapDb.shamanLesserHealMode] or "?") .. "|r")
        DEFAULT_CHAT_FRAME:AddMessage("  Water Shield:     |cFFFFD700" .. (SHAMAN_TOTEMS.watershield[LibramSwapDb.shamanWaterShieldMode] or "?") .. "|r")
        DEFAULT_CHAT_FRAME:AddMessage("  Lightning Strike: |cFFFFD700" .. (SHAMAN_TOTEMS.lightningstrike[LibramSwapDb.shamanLightningStrikeMode] or "?") .. "|r")
    end
end

local function HandleLibramSwapCommand(msg)
    msg = string.lower(trim(msg))
    local _, _, cmd, arg = string_find(msg, "^(%S*)%s*(.-)$")
    cmd = cmd or ""
    arg = string.lower(trim(arg or ""))

    if cmd == "on" then
        LibramSwapDb.enabled = true
        DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r |cFF00FF00ENABLED|r")

    elseif cmd == "off" then
        LibramSwapDb.enabled = false
        DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r |cFFFF0000DISABLED|r")

    elseif cmd == "spam" then
        LibramSwapDb.spam = not LibramSwapDb.spam
        local spamStatus = LibramSwapDb.spam and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"
        DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Swap messages " .. spamStatus)

    elseif cmd == "class" then
        if arg == "paladin" or arg == "druid" or arg == "shaman" then
            LibramSwapDb.classMode = arg
            DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Class ruleset set to |cFFFFD700" .. string.upper(arg) .. "|r")
            isProvidingDevotionAura = false
            lastInputTime = GetTime()
            lastRebirthSwapTime = 0
            ReindexAll()
            PrintClassCommands(arg)
        else
            PrintClassPrompt()
        end

    -- PALADIN choose-one
    elseif cmd == "consecration" or cmd == "consec" or cmd == "c" then
        if LibramSwapDb.classMode ~= "paladin" then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r |cFFFF5555Paladin-only. Use /ls class paladin|r"); return
        end
        if arg == "faithful" or arg == "f" then LibramSwapDb.consecrationMode = "faithful"
        elseif arg == "farraki" or arg == "z" or arg == "zealot" then LibramSwapDb.consecrationMode = "farraki"
        else DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Usage: /ls consecration [faithful / farraki]|r"); return end
        DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Consecration set to |cFFFFD700" .. ((LibramSwapDb.consecrationMode=="farraki") and CONSECRATION_FARRAKI or CONSECRATION_FAITHFUL) .. "|r")
        ReindexAll()

    elseif cmd == "holystrike" or cmd == "hs" then
        if LibramSwapDb.classMode ~= "paladin" then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r |cFFFF5555Paladin-only. Use /ls class paladin|r"); return
        end
        if arg == "radiance" or arg == "r" then LibramSwapDb.holyStrikeMode = "radiance"
        elseif arg == "eternal" or arg == "e" then LibramSwapDb.holyStrikeMode = "eternal"
        else DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Usage: /ls holystrike [eternal / radiance]|r"); return end
        DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Holy Strike set to |cFFFFD700" .. ((LibramSwapDb.holyStrikeMode=="radiance") and HOLY_STRIKE_RADIANCE or HOLY_STRIKE_ETERNAL_TOWER) .. "|r")
        ReindexAll()

    -- DRUID choose-one
    elseif cmd == "rip" then
        if LibramSwapDb.classMode ~= "druid" then DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r |cFFFF5555Druid-only. Use /ls class druid|r"); return end
        if arg=="emerald" or arg=="laceration" or arg=="savagery" then LibramSwapDb.druidRipMode = arg
        else DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Usage: /ls rip [emerald / laceration / savagery]|r"); return end
        DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Rip set to |cFFFFD700" .. DRUID_IDOLS.rip[LibramSwapDb.druidRipMode] .. "|r")
        ReindexAll()

    elseif cmd == "bite" then
        if LibramSwapDb.classMode ~= "druid" then DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r |cFFFF5555Druid-only. Use /ls class druid|r"); return end
        if arg=="emerald" or arg=="laceration" then LibramSwapDb.druidBiteMode = arg
        else DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Usage: /ls bite [emerald / laceration]|r"); return end
        DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Ferocious Bite set to |cFFFFD700" .. DRUID_IDOLS.bite[LibramSwapDb.druidBiteMode] .. "|r")
        ReindexAll()

    elseif cmd == "rake" then
        if LibramSwapDb.classMode ~= "druid" then DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r |cFFFF5555Druid-only. Use /ls class druid|r"); return end
        if arg=="ferocity" or arg=="savagery" then LibramSwapDb.druidRakeMode = arg
        else DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Usage: /ls rake [ferocity / savagery]|r"); return end
        DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Rake set to |cFFFFD700" .. DRUID_IDOLS.rake[LibramSwapDb.druidRakeMode] .. "|r")
        ReindexAll()

    elseif cmd == "healingtouch" or cmd == "ht" then
        if LibramSwapDb.classMode ~= "druid" then DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r |cFFFF5555Druid-only. Use /ls class druid|r"); return end
        if arg=="health" or arg=="longevity" then LibramSwapDb.druidHealingTouchMode = arg
        else DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Usage: /ls healingtouch [health / longevity]|r"); return end
        DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Healing Touch set to |cFFFFD700" .. DRUID_IDOLS.ht[LibramSwapDb.druidHealingTouchMode] .. "|r")
        ReindexAll()

    elseif cmd == "moonfire" then
        if LibramSwapDb.classMode ~= "druid" then DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r |cFFFF5555Druid-only. Use /ls class druid|r"); return end
        if arg=="moonfang" or arg=="moon" then LibramSwapDb.druidMoonfireMode = arg
        else DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Usage: /ls moonfire [moonfang / moon]|r"); return end
        DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Moonfire set to |cFFFFD700" .. DRUID_IDOLS.moonfire[LibramSwapDb.druidMoonfireMode] .. "|r")
        ReindexAll()

    -- SHAMAN choose-one
    elseif cmd == "earthshock" then
        if LibramSwapDb.classMode ~= "shaman" then DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r |cFFFF5555Shaman-only. Use /ls class shaman|r"); return end
        if arg=="broken" or arg=="stone" or arg=="rage" or arg=="rotten" then LibramSwapDb.shamanEarthShockMode = arg
        else DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Usage: /ls earthshock [broken / stone / rage / rotten]|r"); return end
        DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Earth Shock set to |cFFFFD700" .. SHAMAN_TOTEMS.earthshock[LibramSwapDb.shamanEarthShockMode] .. "|r")
        ReindexAll()

    elseif cmd == "frostshock" then
        if LibramSwapDb.classMode ~= "shaman" then DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r |cFFFF5555Shaman-only. Use /ls class shaman|r"); return end
        if arg=="stone" or arg=="rage" then LibramSwapDb.shamanFrostShockMode = arg
        else DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Usage: /ls frostshock [stone / rage]|r"); return end
        DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Frost Shock set to |cFFFFD700" .. SHAMAN_TOTEMS.frostshock[LibramSwapDb.shamanFrostShockMode] .. "|r")
        ReindexAll()

    elseif cmd == "flameshock" then
        if LibramSwapDb.classMode ~= "shaman" then DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r |cFFFF5555Shaman-only. Use /ls class shaman|r"); return end
        if arg=="stone" or arg=="rage" or arg=="flicker" then LibramSwapDb.shamanFlameShockMode = arg
        else DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Usage: /ls flameshock [stone / rage / flicker]|r"); return end
        DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Flame Shock set to |cFFFFD700" .. SHAMAN_TOTEMS.flameshock[LibramSwapDb.shamanFlameShockMode] .. "|r")
        ReindexAll()

    elseif cmd == "lightningbolt" or cmd == "lb" then
        if LibramSwapDb.classMode ~= "shaman" then DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r |cFFFF5555Shaman-only. Use /ls class shaman|r"); return end
        if arg=="crackling" or arg=="static" or arg=="storm" then LibramSwapDb.shamanLightningBoltMode = arg
        else DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Usage: /ls lightningbolt [crackling / static / storm]|r"); return end
        DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Lightning Bolt set to |cFFFFD700" .. SHAMAN_TOTEMS.lightningbolt[LibramSwapDb.shamanLightningBoltMode] .. "|r")
        ReindexAll()

    elseif cmd == "lesserheal" or cmd == "lhw" then
        if LibramSwapDb.classMode ~= "shaman" then DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r |cFFFF5555Shaman-only. Use /ls class shaman|r"); return end
        if arg=="life" or arg=="sustaining" or arg=="corrupted" then LibramSwapDb.shamanLesserHealMode = arg
        else DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Usage: /ls lesserheal [life / sustaining / corrupted]|r"); return end
        DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Lesser Healing Wave set to |cFFFFD700" .. SHAMAN_TOTEMS.lhw[LibramSwapDb.shamanLesserHealMode] .. "|r")
        ReindexAll()

    elseif cmd == "watershield" then
        if LibramSwapDb.classMode ~= "shaman" then DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r |cFFFF5555Shaman-only. Use /ls class shaman|r"); return end
        if arg=="tides" or arg=="calming" then LibramSwapDb.shamanWaterShieldMode = arg
        else DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Usage: /ls watershield [tides / calming]|r"); return end
        DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Water Shield set to |cFFFFD700" .. SHAMAN_TOTEMS.watershield[LibramSwapDb.shamanWaterShieldMode] .. "|r")
        ReindexAll()

    elseif cmd == "lightningstrike" then
        if LibramSwapDb.classMode ~= "shaman" then DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r |cFFFF5555Shaman-only. Use /ls class shaman|r"); return end
        if arg=="crackling" or arg=="tides" or arg=="calming" then LibramSwapDb.shamanLightningStrikeMode = arg
        else DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Usage: /ls lightningstrike [crackling / tides / calming]|r"); return end
        DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r Lightning Strike set to |cFFFFD700" .. SHAMAN_TOTEMS.lightningstrike[LibramSwapDb.shamanLightningStrikeMode] .. "|r")
        ReindexAll()

    elseif cmd == "status" then
        printStatus()

    elseif cmd == "help" or cmd == "?" then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap] Commands:|r")
        DEFAULT_CHAT_FRAME:AddMessage("  |cFFFFD700/ls class <paladin|druid|shaman>|r - Select ruleset")
        DEFAULT_CHAT_FRAME:AddMessage("  |cFFFFD700/ls on|r / |cFFFFD700/ls off|r / |cFFFFD700/ls spam|r / |cFFFFD700/ls status|r")
        if LibramSwapDb.classMode then PrintClassCommands(LibramSwapDb.classMode) end

    elseif cmd == "" then
        LibramSwapDb.enabled = not LibramSwapDb.enabled
        DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r " .. (LibramSwapDb.enabled and "|cFF00FF00ENABLED|r" or "|cFFFF0000DISABLED|r"))

    else
        DEFAULT_CHAT_FRAME:AddMessage("|cFFAAAAFF[LibramSwap]:|r |cFFFF5555Unknown command. Type '/ls help' for usage.|r")
    end
end

SLASH_LIBRAMSWAP1 = "/libramswap"
SLASH_LIBRAMSWAP2 = "/lswap"
SLASH_LIBRAMSWAP3 = "/ls"
SlashCmdList["LIBRAMSWAP"] = HandleLibramSwapCommand
