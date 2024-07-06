if isServer() then return end

require "ConditionalSpeech01_Config"
local cndSpeechUtil = require "ConditionalSpeech00_Util"
local conditionalSpeechFilter = require "ConditionalSpeech03_Filters"
local phraseSets = require "ConditionalSpeech04_PhraseSet"
local metaValues = require "ConditionalSpeech02b_metaValues"

local ConditionalSpeech = {}

ConditionalSpeech.Speakers = {}

--- filters that shouldn't run if volume is 0 or thoughts
ConditionalSpeech.volumeSensitiveFilters = {["Stutter"]=true,["Stammer"]=true}

--- global paired list of mood types and corresponding filters
ConditionalSpeech.filterTable = {
	["Endurance"] = {"BlurtOut"},
	["Tired"] = {"BlurtOut"},
	["Panic"] = {"panicSwear","Stutter","BlurtOut","SCREAM"},
	["Bored"] = {"BlurtOut"},
	["Bleeding"] = {"BlurtOut"},
	["Angry"] = {"SCREAM"},
	["Pain"] = {"BlurtOut","SCREAM"},
	["Drunk"] = {"BlurtOut","Slurring"},
	["Hyperthermia"] = {"Stammer","BlurtOut"},
	["HasACold"] = {"Congested"},

	--["Hungry"] = nil,
	--["Sick"] = nil,
	--["Unhappy"] = nil,
	--["Wet"] = nil,
	--["Stress"] = nil,
	--["Thirst"] = nil,
	--["Injured"] = nil,
	--["HeavyLoad"] = nil,
	--["Dead"] = nil,
	--["Zombie"] = nil,
	--["Hyperthermia"] = nil,
	--["Windchill"] = nil,
	--["FoodEaten"] = nil
}


--- Cleans up the dialogue and applies filters.
---@param player IsoGameCharacter
function ConditionalSpeech.bIsNPC(player)
	for playerIndex=0, getNumActivePlayers()-1 do
		---@type IsoLivingCharacter | IsoGameCharacter
		local playerObj = getSpecificPlayer(playerIndex)
		if playerObj and (playerObj == player) then
			return false
		end
	end
	return true
end


--- Retrieve MoodLevel Values and Set up MoodArray per player.
---@param player IsoLivingCharacter | IsoGameCharacter
function ConditionalSpeech.load_n_set_Moodles(id,player)
	if not player or player:isDead() then
		return
	end

	ConditionalSpeech.Speakers[player] = true

	local pModData = player:getModData()
	if pModData then
		pModData.cs_lastspoke = {[1]=getTimestamp(), [2]=""}
		pModData.cs_lastPanicTime = getTimestamp()
		pModData.moodleTable = {}

		local moodles = player:getMoodles()
		if moodles then
			--fetches moodles index num
			local moodNum = moodles:getNumMoodles()
			for i=0, moodNum-1 do
				--fetches mood type string based on index
				local moodType = moodles:getMoodleType(i)
				--fetches moodle level based on fetched type
				local foundlevel = moodles:getMoodleLevel(moodType)
				--creates a key value pair of type and found level
				pModData.moodleTable[tostring(moodType)] = foundlevel
			end
		end
	end
end



--- Handler for filters. Text passed through will have mood defined filters applied. Called from within ConditionalSpeech.Speech.
---@param player IsoGameCharacter
function ConditionalSpeech.passMoodleFilters(player,text)
	if not text or not player then
		return
	end

	--filtersToPass will be populated by pairs of filter type and mood levels
	local filtersToPass = {}
	--sortFilters will be populated by only the filter types as to sort based on volumeSensitiveFilters
	local sortFilters = {}

	--for each mood grab stored mood and lvl in player's moodle array
	for MoodID,lvl in pairs(player:getModData().moodleTable) do

		local moodleLevel = lvl
		local MoodID_filters = ConditionalSpeech.filterTable[MoodID]

		--check if mood should be processed
		if moodleLevel > 0 and MoodID_filters then

			--trackPos to maintain order through sorting
			local trackPos = 0
			for _,Filter in pairs(MoodID_filters) do
				if moodleLevel > (filtersToPass[Filter] or 0) then
					filtersToPass[Filter] = moodleLevel

					if ConditionalSpeech.volumeSensitiveFilters[Filter] then
						table.insert(sortFilters,Filter)
					else
						trackPos = trackPos+1
						table.insert(sortFilters,trackPos,Filter)
					end
				end
			end
		end
	end

	--volume to be called and modified depending on filters
	local filtered_vol = 0

	for _,FilterType in ipairs(sortFilters) do
		if not ConditionalSpeech.volumeSensitiveFilters[FilterType] or (filtered_vol > 0 and ConditionalSpeech.volumeSensitiveFilters[FilterType]) then
			--compare sortFilters's value to filtersToPass's keys to find stored intensity
			--[debug]] print("CND-SPEECH: RUN FILTER: ",FilterType,"-")
			local intensity = filtersToPass[FilterType]
			local filter = conditionalSpeechFilter[FilterType]
			local resultText, resultVolume = filter(text, intensity)

			text = resultText or text
			if resultVolume and resultVolume > filtered_vol then filtered_vol = resultVolume end
		end
	end

	if filtered_vol >= metaValues.volumeMax then
		text = text:upper()
	end

	return text,filtered_vol
end



--- Generates speech from a given table/list of phrases.
---@param player IsoGameCharacter
---@param PhraseSetID string String needs to match a table with in ConditionalSpeech.Phrases.
function ConditionalSpeech.generateSpeechFrom(player, PhraseSetID, intensity, MAXintensity, volumeBlock, danger)
	if not player or not PhraseSetID then
		return
	end

	if cndSpeechConfig.config[PhraseSetID]==false then
		return
	end

	if not intensity or intensity <=0 then
		intensity = 1
	end

	if not MAXintensity or MAXintensity <=0 then
		MAXintensity = 1
	end

	-- prevent the player from speaking too soon -- getTimestamp is in seconds
	local lastspoke = player:getModData().cs_lastspoke or {[1]=getTimestamp(), [2]=""}
	--delay between lines is 1 unless they're the same phraset, then it is 3
	if (lastspoke[1]+1 > getTimestamp()) or (lastspoke[1]+3 > getTimestamp() and lastspoke[2]==PhraseSetID) then
		return
	end

	local PhraseTable = phraseSets.Phrases[PhraseSetID]
	if not PhraseTable then
		return
	end

	local dialogue = cndSpeechUtil.rangedRandPick(PhraseTable,intensity,MAXintensity)
	if not dialogue then
		return
	end

	--If "<" is found within the phrase - assume there's a keyword
	while string.find(dialogue, "<") do
		--replace text matching PhraseSetID (KEYWORD) with words from phraseset
		for KEYWORD, PHRASE in pairs(phraseSets.Phrases) do
			local phrases = PHRASE
			if danger and (KEYWORD=="SARCASM") then phrases = phraseSets.Phrases["SWEAR"] end
			dialogue = dialogue:gsub("<"..KEYWORD..">", cndSpeechUtil.pickFrom(phrases))
		end
	end

	local vocal_volume = 0
	dialogue, vocal_volume = ConditionalSpeech.ProcessSpeech(player,dialogue,PhraseSetID, volumeBlock)

	ConditionalSpeech.Say(player, dialogue, vocal_volume)
end


--- Our own version of Say()
function ConditionalSpeech.Say(player, dialogue, vocal_volume)

	--[debug]] print("CND-SPEECH: "..player:getFullName()," (vol:",vocal_volume,") : ",dialogue)
	ConditionalSpeech.applyVolumetricColor_Say(player,tostring(dialogue),vocal_volume)

	if cndSpeechConfig.config.SpeechCanAttractsZombies==true and player and vocal_volume and vocal_volume>0 then
		addSound(nil, player:getX(), player:getY(), player:getZ(), vocal_volume, vocal_volume)
	end
end


--- Cleans up the dialogue and applies filters.
---@param player IsoGameCharacter
---@param dialogue string
function ConditionalSpeech.ProcessSpeech(player, dialogue, PhraseSetID, volumeBlock, volumeOverride)

	--prevent MPCs from speaking if config is set to such
	if ConditionalSpeech.bIsNPC(player)==true then--and cndSpeechConfig.config.NPCsDontTalk==true then
		--[[DEBUG]] print("CND-SPEECH: NO NPC TALK ("..player:getFullName()..")")
		return
	end

	if PhraseSetID then
		-- prevent the player from speaking too soon -- getTimestamp is in seconds
		local lastspoke = player:getModData().cs_lastspoke or {[1]=getTimestamp(), [2]=""}
		if (lastspoke[1]+1 > getTimestamp()) or (lastspoke[1]+3 > getTimestamp() and lastspoke[2]==PhraseSetID) then
			return
		end
		player:getModData().cs_lastspoke = {[1]=getTimestamp(),[2]=PhraseSetID}
	end

	local fc = string.sub(dialogue, 1,1) --fc=first character
	local lc = string.sub(dialogue, -1) --lc=last character
	local vocal_volume = 0

	--avoid filtering/messing with *emotive* text
	if (fc~="*" and lc~="*") and (fc~="[" and lc~="]") and (fc~="<" and lc~=">") then

		--just in case of no punctuation add some
		if lc~="." and lc~="!" and lc~="?" then
			dialogue = dialogue .. "."
		end

		--pass moodle filters if player has a moodle array
		if player:getModData().moodleTable then
			local textResult, volumeResult = ConditionalSpeech.passMoodleFilters(player,dialogue)--have other moods impact dialogue
			dialogue = textResult
			vocal_volume = volumeResult
		end

		--Proper sentence capitalization. Like so.
		dialogue = dialogue:gsub("[!?.]%s", "%0\0"):gsub("%f[%Z]%s*%l", dialogue.upper):gsub("%z", "")
	end

	if volumeOverride then
		vocal_volume = math.max(volumeOverride, vocal_volume)
	end

	if volumeBlock then
		vocal_volume = 0
	end

	return dialogue, vocal_volume
end


--- Blends speech color with gray on a scale with volume. This is called with in ConditionalSpeech.Speech.
---@param player IsoGameCharacter | IsoPlayer
function ConditionalSpeech.applyVolumetricColor_Say(player,text,vol)
	if not player or not text then
		return
	end

	if not vol then
		print("WARN: vol received as nil!  <txt:"..text..">")
		vol = 0
	end

	if (vol <= 0) and (cndSpeechConfig.config.ShowOnlyAudibleSpeech==true) then
		return
	end

	local vc_shift = 0.40+(0.60*((vol or 0)/metaValues.volumeMax))--have a 0.3 base --difference of 0.7 is then multiplied against volume/maxvolume
	---@type ColorInfo
	local Text_Color = getCore():getMpTextColor()
	local tR, tG, tB = Text_Color:getR(), Text_Color:getG(), Text_Color:getB()

	local text_color = { r = tR*vc_shift, g = tG*vc_shift, b = tB*vc_shift, a = vc_shift}--alpha shift based on vc_shift
	local graybase = {r=0.45, g=0.45, b=0.45, a=1}--gray base text_color will be overlayed onto
	local return_color = {r=tR, g=tG, b=tB, a=1}--set up return color


	if cndSpeechConfig.config.SpeechCanAttractsZombies==true then
		return_color.a = 1 - (1 - text_color.a) * (1 - graybase.a)--alpha
		return_color.r = text_color.r * text_color.r / return_color.a + graybase.r * graybase.a * (1 - text_color.a) / return_color.a--red
		return_color.g = text_color.g * text_color.g / return_color.a + graybase.g * graybase.a * (1 - text_color.a) / return_color.a--green
		return_color.b = text_color.b * text_color.b / return_color.a + graybase.b * graybase.a * (1 - text_color.a) / return_color.a--blue
		player:setSpeakColour(Color.new(return_color.r,return_color.g,return_color.b,1))
	end

	--print(" --Text_Color: "..Text_Color:getR()..","..Text_Color:getG()..","..Text_Color:getB())
	--print(" --text_color: "..text_color.r..","..text_color.g..","..text_color.b)
	--print(" --return_color: "..return_color.r..","..return_color.g..","..return_color.b)

	if getDebug() then print(" ---applyVolumetric: "..player:getFullName()," (vol:",vol,") : ",text) end

	ConditionalSpeech.playerJustSpoke[player] = 3
	if isClient() then
		sendClientCommand(player, "cndSpeech", "addLineChatElement", {text=text, return_color=return_color, vol=vol}) -- to server
	else
		player:addLineChatElement(text, return_color.r, return_color.g, return_color.b, UIFont.Dialogue, vol, "default", true, true, true, true, true, true)
	end
end


--- Apply filters to process say
local original_processSayMessage = processSayMessage
function processSayMessage(text, ...)
	text = ConditionalSpeech.ProcessSpeech(getPlayer(), text, nil, nil, metaValues.volumeMax/2)
	return original_processSayMessage(text, ...)
end

ConditionalSpeech.playerJustSpoke = {}

--- Tracks moodle levels overtime, runs generate speech.
---@param player IsoGameCharacter|IsoPlayer|IsoMovingObject|IsoObject
function ConditionalSpeech.check_PlayerStatus(player)
	if (not player) then--or (not player:getModData().moodleTable) then
		return
	end

	if ConditionalSpeech.playerJustSpoke[player] then
		local pSpeaking = player:isSpeaking() and player:getCurrentSquare():isInARoom()
		if pSpeaking then
			player:getBodyDamage():setBoredomLevel( player:getBodyDamage():getBoredomLevel() + (ZomboidGlobals.BoredomDecrease * getGameTime():getMultiplier()) )
		end
		if (not pSpeaking) then
			ConditionalSpeech.playerJustSpoke[player] = ConditionalSpeech.playerJustSpoke[player] - 1
			if ConditionalSpeech.playerJustSpoke[player] <= 0 then
				ConditionalSpeech.playerJustSpoke[player] = nil
			end
		end
	end

	local pModData = player:getModData()
	if not pModData then
		return
	end

	if (not pModData.moodleTable) then
		ConditionalSpeech.load_n_set_Moodles(player)
	end
	if (not pModData.moodleTable) then
		return
	end

	local playerStats = player:getStats()
	--panic is a troublesome moodle and can't be treated like the rest
	local panicLevel = player:getMoodles():getMoodleLevel(MoodleType.Panic)

	-- on fire condition
	if player:isOnFire() then
		playerStats:setPanic(playerStats:getPanic()+100)
		ConditionalSpeech.generateSpeechFrom(player,"Panic",panicLevel,4, false, true)
		return
	end

	local zombiesNearBy = (playerStats:getNumVisibleZombies() > 0) or (player:getLastSeenZomboidTime() < 1)

	--prevent vocalization if any zombies are visible or chasing
	local volumeBlock = (cndSpeechUtil.prob(100-(panicLevel^2)) and zombiesNearBy)
	--check if agoraphobic is actively inducing panic
	local agora = (player:isOutside() and player:HasTrait("Agoraphobic"))
	local claustro = ((not player:isOutside()) and player:HasTrait("Claustophobic"))

	local impactedByPanic = (panicLevel>0 and zombiesNearBy)
	if impactedByPanic then
		pModData.cs_lastPanicTime = getTimestamp()+5
	end

	local spoke = false
	for MoodleID,lvl in pairs(pModData.moodleTable) do
		local storedmoodleLevel = lvl
		local currentMoodleLevel = player:getMoodles():getMoodleLevel(MoodleType[MoodleID])
		--currentMoodleLevel(current mood level) is not equal to stored mood level then
		if currentMoodleLevel ~= storedmoodleLevel then
			--if moodlevel has increased
			if currentMoodleLevel > storedmoodleLevel then
				local phraseSet = MoodleID

				if (impactedByPanic) and (MoodleID~="Panic") and (MoodleID~="Pain") and (getTimestamp() < pModData.cs_lastPanicTime) then
				else
					--space-phobic conditions met, set MoodleID\Phraset
					if MoodleID=="Panic" then
						if agora then
							phraseSet = "Agoraphobic"
						elseif claustro then
							phraseSet = "Claustrophobic"
						end
					end
					--pain overrides volumeBlock
					if MoodleID == "Pain" then
						volumeBlock = false
					end
					--generate speech
					ConditionalSpeech.generateSpeechFrom(player, phraseSet, currentMoodleLevel,4, volumeBlock, zombiesNearBy)
				end
				spoke = true
			end
			--match stored mood level to current regardless of above outcome
			pModData.moodleTable[MoodleID] = currentMoodleLevel
		end
	end

	if not spoke then
		local tellTime = pModData.CndSpeech_tellTime
		local validTime = ((getGameTime():getHour() == ConditionalSpeech.DUSK_TIME) or (getGameTime():getHour() == metaValues.DAWN_TIME))

		if tellTime and validTime then
			ConditionalSpeech.generateSpeechFrom(player,tellTime)
			pModData.CndSpeech_tellTime = false
		end
	end
end


--- Weapon Status Check
---@param player IsoGameCharacter
---@param weapon InventoryItem
function ConditionalSpeech.check_WeaponStatus(player,weapon)
	if player and weapon and weapon:getCategory() == "Weapon" and weapon:isRanged() then
		if (player.isShoving and not player:isShoving()) or (player.isDoShove and not player:isDoShove()) then
			if weapon:isJammed() then
				ConditionalSpeech.generateSpeechFrom(player,"GunJammed")
			elseif (weapon:haveChamber() and not weapon:isRoundChambered()) or (not weapon:haveChamber() and weapon:getCurrentAmmoCount() <= 0) then
				ConditionalSpeech.generateSpeechFrom(player,"OutOfAmmo")
			elseif weapon:getMaxAmmo()>0 then
				if player:getPerkLevel(Perks.Reloading)>=5 then
					if cndSpeechConfig.config["LowAmmo"] ~= false then
						local dialogue, vocal_volume = ConditionalSpeech.ProcessSpeech(player,weapon:getCurrentAmmoCount().." "..getText("UI_shotsLeft"))
						if dialogue and vocal_volume then ConditionalSpeech.Say(player, dialogue, vocal_volume) end
					end
				elseif player:getPerkLevel(Perks.Reloading)>=2 then
					if weapon:getCurrentAmmoCount()<(weapon:getMaxAmmo()/4) then
						ConditionalSpeech.generateSpeechFrom(player,"LowAmmo")
					end
				end
			end
		end
	end
end


--- Have players react to specific times throughout the day.
function ConditionalSpeech.check_Time()
	local TIME = getGameTime():getHour()

	for playerObject,_ in pairs(ConditionalSpeech.Speakers) do
		---@type IsoGameCharacter | IsoPlayer
		local player = playerObject

		if player and not player:isDead() then
			if player:isOutside() and cndSpeechUtil.prob(75) then
				if TIME==ConditionalSpeech.DAWN_TIME then
					player:getModData().CndSpeech_tellTime = "OnDawn"
				elseif TIME==ConditionalSpeech.DUSK_TIME then
					player:getModData().CndSpeech_tellTime = "OnDusk"
				end
			end
		end
	end
end

return ConditionalSpeech
