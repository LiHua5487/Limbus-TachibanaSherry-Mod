local SELF = "Self"
local TARGET = "MainTarget"

local WITCH_FACTOR = "WitchFactor"
local WITCHIZATION = "Witchization-TachibanaSherry"
local MIGHT = "Might"
local MONSTROUS_MIGHT = "MonstrousMight"
local PAIN_INHIBITION = "PainInhibition"
local REBUTTAL = "Rebuttal"
local HANNA_ID = 109972

local NORMAL_S1 = 9760101
local NORMAL_S2 = 9760102
local NORMAL_S3 = 9760103
local NORMAL_COUNTER = 9760104
local WITCH_S1 = 9760111
local WITCH_S2 = 9760112
local WITCH_S3 = 9760113
local WITCH_COUNTER = 9760114
local WITCH_S1_INDISCRIMINATE = 9760121
local WITCH_S2_INDISCRIMINATE = 9760122
local WITCH_S3_INDISCRIMINATE = 9760123
local NORMAL_COUNTER_S3 = 9760133
local WITCH_COUNTER_S3 = 9760143

local NORMAL_APPEARANCE = "!custom_91020_MiddleFinger_MiddleBroAppearance"
local WITCH_APPEARANCE = "!custom_SherryWitchAppearance"

local D_WITCHIZED = 6103
local D_CONSUMED_CHARGE = 6104
local D_WAS_STAGGERED = 6105
local D_COUNTER_CHANGED = 6106
local D_FATAL_TRIGGERED = 6107
local D_SKILL_CONSUMED = 6108
local D_COUNTER_SELF_DAMAGE = 6109
local D_S1_NEXT_PARALYSIS = 6110
local D_S2_NEXT_VULNERABLE = 6111
local D_COUNTER_FORCE_FIELD = 6112
local D_SUPPRESS_MP_FACTOR = 6113
local D_S3_EXCISION_USED = 6114
local D_HANNA_COVER_USED = 6115
local D_HANNA_REVENGE_USED = 6116
local D_APPEARANCE = 6117 -- 0=needs sync, 1=witch, 2=normal
local D_FIRST_WITCH_VOICE_PENDING = 6118

local function clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function stack(unit, keyword)
    return getbuff(unit, keyword, "stack") or 0
end

local function count(unit, keyword)
    return getbuff(unit, keyword, "turn") or 0
end

local function data(key)
    return getdata(SELF, key) or 0
end

local function skill_id()
    if getskillid == nil then return 0 end
    if pcall == nil then return getskillid() end
    local ok, value = pcall(getskillid)
    if ok and type(value) == "number" then return value end
    return 0
end

local function play_sherry_voice(stat)
    if playcustomsound == nil then return end
    if pcall ~= nil then
        pcall(playcustomsound, stat, 100)
    else
        playcustomsound(stat, 100)
    end
end

local function is_witchized()
    return stack(SELF, WITCHIZATION) > 0
end

local function set_sherry_appearance(witchized, force)
    if appearance == nil then return end
    if gethp(SELF, "normal") <= 0 then return end
    if witchized then
        if not force and data(D_APPEARANCE) == 1 then return end
        appearance(SELF, WITCH_APPEARANCE)
        setdata(SELF, D_APPEARANCE, 1)
    else
        if not force and data(D_APPEARANCE) == 2 then return end
        appearance(SELF, NORMAL_APPEARANCE)
        setdata(SELF, D_APPEARANCE, 2)
    end
end

local function refresh_slot_visuals()
    if refreshallslotvisual ~= nil then
        if pcall ~= nil then pcall(refreshallslotvisual) else refreshallslotvisual() end
    end
end

local function current_might()
    if is_witchized() then return MONSTROUS_MIGHT end
    return MIGHT
end

local function gain_factor(amount)
    if amount > 0 then buff(SELF, WITCH_FACTOR, amount, 0, 0) end
end

local function gain_might(potency, charge_count)
    local keyword = current_might()
    if potency ~= 0 or charge_count ~= 0 then
        buff(SELF, keyword, potency, charge_count, 0)
    end
end

local function record_consumption(amount)
    if amount <= 0 then return end
    setdata(SELF, D_SKILL_CONSUMED, data(D_SKILL_CONSUMED) + amount)
    local accumulated = data(D_CONSUMED_CHARGE) + amount
    local potency_gain = math.floor(accumulated / 10)
    accumulated = accumulated % 10
    setdata(SELF, D_CONSUMED_CHARGE, accumulated)
    if potency_gain > 0 then
        buff(SELF, current_might(), potency_gain, 0, 0)
    end
end

local function consume_might(maximum, require_full)
    local keyword = current_might()
    local available = count(SELF, keyword)
    local spent = math.min(available, maximum)
    if require_full and available < maximum then spent = 0 end
    if spent > 0 then
        buff(SELF, keyword, 0, -spent, 0)
        record_consumption(spent)
    end
    return spent
end

local function preview_might_spend(keyword, require_full)
    local available = math.max(count(SELF, keyword), 0)
    if require_full and available < 10 and stack(SELF, keyword) < 5
        and data(D_COUNTER_SELF_DAMAGE) == 0 then
        available = 10
    end
    if require_full then return available >= 10 and 10 or 0 end
    return math.min(available, 10)
end

local function preview_might_potency(keyword, spent)
    local potency = math.max(stack(SELF, keyword), 0)
    local remainder = math.max(data(D_CONSUMED_CHARGE), 0)
    return potency + math.floor((remainder + math.max(spent, 0)) / 10)
end

local function excision_ready()
    return data(D_S3_EXCISION_USED) == 0
        and is_witchized()
        and count(SELF, MONSTROUS_MIGHT) >= 15
        and stack(SELF, MONSTROUS_MIGHT) >= 10
end

local function clear_stagger()
    deactivebreak(SELF, -1, true)
    breakrecover(SELF)
end

local function first_witchization()
    if data(D_WITCHIZED) == 1 then return end
    setdata(SELF, D_WITCHIZED, 1)

    local current_sp = getsp(SELF)
    if current_sp > -20 then
        setdata(SELF, D_SUPPRESS_MP_FACTOR, 1)
        healsp(SELF, -20 - current_sp)
    end

    clear_stagger()

    local might_potency = stack(SELF, MIGHT)
    local might_count = count(SELF, MIGHT)
    if might_potency ~= 0 or might_count ~= 0 then
        buff(SELF, MIGHT, -might_potency, -might_count, 0)
        buff(SELF, MONSTROUS_MIGHT, might_potency, might_count, 0)
    end

    setdata(SELF, D_FIRST_WITCH_VOICE_PENDING, 1)
end

local function enter_witchization()
    if data(D_WITCHIZED) == 1 then return end
    buff(SELF, WITCHIZATION, 1, 0, 0)
    first_witchization()
    set_sherry_appearance(true, true)
end

local function should_enter_witchization()
    if data(D_WITCHIZED) ~= 0 then return false end
    return getsp(SELF) <= -35
        or stack(SELF, WITCH_FACTOR) >= 100
        or data(D_WAS_STAGGERED) == 1
end

local function lose_sp(amount)
    if amount <= 0 then return end
    local actual = amount
    local current_sp = getsp(SELF)
    if current_sp - actual < -40 then actual = current_sp + 40 end
    if actual > 0 then healsp(SELF, -actual) end
end

local function fixed_damage(target, amount)
    if amount > 0 then sherryfixeddmg(target, math.floor(amount)) end
end

local function fixed_damage_not_below_one(target, amount)
    local maximum = math.max(gethp(target, "normal") - 1, 0)
    fixed_damage(target, math.min(amount, maximum))
end

local function is_normal_s3_attack(id)
    return id == NORMAL_S3
end

local function is_normal_s3(id)
    return is_normal_s3_attack(id) or id == NORMAL_COUNTER_S3
end

local function is_witch_s1(id)
    return id == WITCH_S1 or id == WITCH_S1_INDISCRIMINATE
end

local function is_witch_s2(id)
    return id == WITCH_S2 or id == WITCH_S2_INDISCRIMINATE
end

local function is_witch_s3_attack(id)
    return id == WITCH_S3
        or id == WITCH_S3_INDISCRIMINATE
end

local function witch_s3_target(witchization)
    if witchization >= 90 then
        return WITCH_S3_INDISCRIMINATE
    end
    return WITCH_S3
end

local function is_witch_s3(id)
    return is_witch_s3_attack(id)
        or id == WITCH_COUNTER_S3
end

function sherry_encounter_start()
    setdata(SELF, D_WITCHIZED, 0)
    setdata(SELF, D_APPEARANCE, 0)
    setdata(SELF, D_FIRST_WITCH_VOICE_PENDING, 0)
    setdata(SELF, D_CONSUMED_CHARGE, 0)
    setdata(SELF, D_WAS_STAGGERED, 0)
    setdata(SELF, D_COUNTER_CHANGED, 0)
    setdata(SELF, D_FATAL_TRIGGERED, 0)
    setdata(SELF, D_SKILL_CONSUMED, 0)
    setdata(SELF, D_COUNTER_SELF_DAMAGE, 0)
    setdata(SELF, D_S1_NEXT_PARALYSIS, 0)
    setdata(SELF, D_S2_NEXT_VULNERABLE, 0)
    setdata(SELF, D_COUNTER_FORCE_FIELD, 0)
    setdata(SELF, D_SUPPRESS_MP_FACTOR, 0)
    setdata(SELF, D_S3_EXCISION_USED, 0)
    setdata(SELF, D_HANNA_COVER_USED, 0)
    setdata(SELF, D_HANNA_REVENGE_USED, 0)
    setimmortal(1)
end

function sherry_on_hit()
    gain_factor(3)
end

function sherry_on_kill()
    gain_factor(5)
end

function sherry_on_break()
    setdata(SELF, D_WAS_STAGGERED, 1)
end

function sherry_round_start()
    setdata(SELF, D_COUNTER_CHANGED, 0)
    setdata(SELF, D_COUNTER_SELF_DAMAGE, 0)
    setdata(SELF, D_S1_NEXT_PARALYSIS, 0)
    setdata(SELF, D_S2_NEXT_VULNERABLE, 0)
    setdata(SELF, D_COUNTER_FORCE_FIELD, 0)

    local entering_from_first_stagger = data(D_WITCHIZED) == 0
        and data(D_WAS_STAGGERED) == 1
    if should_enter_witchization() then enter_witchization() end
    set_sherry_appearance(is_witchized(), false)

    if entering_from_first_stagger
        or (data(D_WAS_STAGGERED) == 1 and getunitstate(SELF) ~= 2) then
        gain_factor(10)
        setdata(SELF, D_WAS_STAGGERED, 0)
    end

    local has_might = stack(SELF, MIGHT) > 0
        or count(SELF, MIGHT) > 0
        or stack(SELF, MONSTROUS_MIGHT) > 0
        or count(SELF, MONSTROUS_MIGHT) > 0
    if has_might then buff(SELF, "ParryingResultUp", 1, 0, 0) end

    if is_witchized() then
        local witchization = stack(SELF, WITCHIZATION)
        lose_sp(clamp(math.floor(witchization / 5), 0, 10))
        local power = clamp(math.floor(witchization / 10), 0, 3)
        if power > 0 then
            buff(SELF, "Enhancement", power, 0, 0)
            buff(SELF, "Endurance", power, 0, 0)
        end

        local offense = clamp(math.floor(stack(SELF, WITCH_FACTOR) / 15), 0, 4)
        if offense > 0 then buff(SELF, "AttackUp", offense, 0, 0) end
    end

    if data(D_FATAL_TRIGGERED) == 0 or stack(SELF, PAIN_INHIBITION) > 0 then
        setimmortal(1)
    else
        setimmortal(0)
    end
end

function sherry_after_slots()
    local witchization = stack(SELF, WITCHIZATION)
    set_sherry_appearance(witchization > 0, false)
    if witchization > 0 then
        local s1 = WITCH_S1
        local s2 = WITCH_S2
        local s3 = witch_s3_target(witchization)
        if witchization >= 90 then
            s1 = WITCH_S1_INDISCRIMINATE
            s2 = WITCH_S2_INDISCRIMINATE
        end
        skillslotreplace("All", NORMAL_S1, s1)
        skillslotreplace("All", WITCH_S1, s1)
        skillslotreplace("All", WITCH_S1_INDISCRIMINATE, s1)
        skillslotreplace("All", NORMAL_S2, s2)
        skillslotreplace("All", WITCH_S2, s2)
        skillslotreplace("All", WITCH_S2_INDISCRIMINATE, s2)
        skillslotreplace("All", NORMAL_S3, s3)
        skillslotreplace("All", WITCH_S3, s3)
        skillslotreplace("All", WITCH_S3_INDISCRIMINATE, s3)
    else
        skillslotreplace("All", WITCH_S1, NORMAL_S1)
        skillslotreplace("All", WITCH_S1_INDISCRIMINATE, NORMAL_S1)
        skillslotreplace("All", WITCH_S2, NORMAL_S2)
        skillslotreplace("All", WITCH_S2_INDISCRIMINATE, NORMAL_S2)
        skillslotreplace("All", WITCH_S3, NORMAL_S3)
        skillslotreplace("All", WITCH_S3_INDISCRIMINATE, NORMAL_S3)
    end
    refresh_slot_visuals()
    if data(D_FIRST_WITCH_VOICE_PENDING) == 1 then
        setdata(SELF, D_FIRST_WITCH_VOICE_PENDING, 0)
        play_sherry_voice("SherryPlayVoiceFirstWitch")
    end
end

function sherry_end_round()
    if is_witchized() then
        local gain = 1 + math.floor(stack(SELF, WITCH_FACTOR) / 10)
        buff(SELF, WITCHIZATION, gain, 0, 0)
    end

    local pain = stack(SELF, PAIN_INHIBITION)
    if pain > 0 then
        buff(SELF, PAIN_INHIBITION, -1, 0, 0)
        if pain <= 1 then
            setimmortal(0)
            instantdeath(SELF, true, "FORCED")
        end
    end
end

function sherry_immortal()
    if data(D_FATAL_TRIGGERED) == 0 or stack(SELF, PAIN_INHIBITION) > 0 then setimmortal(1) else setimmortal(0) end
end

function sherry_before_use()
    setdata(SELF, D_SKILL_CONSUMED, 0)

    local id = skill_id()
    local witchization = stack(SELF, WITCHIZATION)
    if witchization <= 0 then
        if is_witch_s1(id) then changeskill(NORMAL_S1)
        elseif is_witch_s2(id) then changeskill(NORMAL_S2)
        elseif is_witch_s3_attack(id) then
            changeskill(NORMAL_S3)
        elseif id == WITCH_COUNTER_S3 then changeskill(NORMAL_COUNTER_S3)
        elseif id == WITCH_COUNTER then changeskill(NORMAL_COUNTER)
        end
        return
    end

    local s1 = witchization >= 90 and WITCH_S1_INDISCRIMINATE or WITCH_S1
    local s2 = witchization >= 90 and WITCH_S2_INDISCRIMINATE or WITCH_S2
    local s3 = witch_s3_target(witchization)
    if id == NORMAL_S1 or is_witch_s1(id) then
        if id ~= s1 then changeskill(s1) end
    elseif id == NORMAL_S2 or is_witch_s2(id) then
        if id ~= s2 then changeskill(s2) end
    elseif is_normal_s3_attack(id) or is_witch_s3_attack(id) then
        if id ~= s3 then changeskill(s3) end
    elseif id == NORMAL_COUNTER then
        changeskill(WITCH_COUNTER)
    elseif id == NORMAL_COUNTER_S3 then
        changeskill(WITCH_COUNTER_S3)
    end
end

function sherry_skill_use()
    local id = skill_id()

    if id == NORMAL_S1 then
        base(clamp(math.floor(stack(SELF, WITCH_FACTOR) / 20), 0, 2))
        scale(clamp(stack(SELF, MIGHT), 0, 2))
        gain_might(0, 8)
    elseif id == NORMAL_S2 then
        base(clamp(math.floor(stack(SELF, WITCH_FACTOR) / 20), 0, 2))
        scale(clamp(stack(SELF, MIGHT), 0, 2))
        gain_might(0, 7)
    elseif is_normal_s3(id) then
        local spent = consume_might(10, false)
        local factor_power = clamp(math.floor(stack(SELF, WITCH_FACTOR) / 15), 0, 3)
        local spend_power = clamp(math.floor(spent / 5), 0, 2)
        base(factor_power + spend_power)
        scale(clamp(stack(SELF, MIGHT), 0, 3))
    elseif id == NORMAL_COUNTER then
        local available = count(SELF, MIGHT)
        if available < 10 and stack(SELF, MIGHT) < 5
            and data(D_COUNTER_SELF_DAMAGE) == 0 then
            setdata(SELF, D_COUNTER_SELF_DAMAGE, 1)
            fixed_damage(SELF, gethp(SELF, "max") * 0.01 * (10 - available))
            gain_might(0, 10 - available)
        end
        local spent = consume_might(10, true)
        if spent == 10 then scale(1) end
        base(clamp(stack(SELF, MIGHT), 0, 3))
    elseif is_witch_s1(id) then
        final(clamp(math.floor(stack(SELF, WITCH_FACTOR) / 20), 0, 3))
        base(clamp(stack(SELF, MONSTROUS_MIGHT), 0, 5))
        gain_might(0, 8)
        lose_sp(5)
        buff(SELF, "Paralysis", 3, 0, 0)
    elseif is_witch_s2(id) then
        final(clamp(math.floor(stack(SELF, WITCH_FACTOR) / 20), 0, 3))
        base(clamp(stack(SELF, MONSTROUS_MIGHT), 0, 6))
        gain_might(0, 7)
        lose_sp(5)
    elseif is_witch_s3(id) then
        if excision_ready() then
            makeextractcoin()
            setdata(SELF, D_S3_EXCISION_USED, 1)
        end
        final(clamp(math.floor(stack(SELF, WITCH_FACTOR) / 20), 0, 4))
        local spent = consume_might(10, false)
        local spend_power = clamp(math.floor(spent / 5), 0, 2)
        local might_power = clamp(stack(SELF, MONSTROUS_MIGHT), 0, 10)
        base(spend_power + might_power)
        lose_sp(7)
    elseif id == WITCH_COUNTER then
        local available = count(SELF, MONSTROUS_MIGHT)
        if available < 10 and stack(SELF, MONSTROUS_MIGHT) < 5
            and data(D_COUNTER_SELF_DAMAGE) == 0 then
            setdata(SELF, D_COUNTER_SELF_DAMAGE, 1)
            fixed_damage_not_below_one(SELF, gethp(SELF, "max") * 0.01 * (10 - available))
            gain_might(0, 10 - available)
        end
        local spent = consume_might(10, true)
        local spend_power = spent == 10 and 3 or 0
        local might_power = clamp(stack(SELF, MONSTROUS_MIGHT), 0, 5)
        base(spend_power + might_power)
        lose_sp(7)
    end
end

function sherry_fake_power()
    local id = skill_id()
    local factor = math.max(stack(SELF, WITCH_FACTOR), 0)
    base(0)
    scale(0)
    final(0)

    if id == NORMAL_S1 or id == NORMAL_S2 then
        base(clamp(math.floor(factor / 20), 0, 2))
        scale(clamp(stack(SELF, MIGHT), 0, 2))
    elseif is_normal_s3(id) then
        local spent = preview_might_spend(MIGHT, false)
        local factor_power = clamp(math.floor(factor / 15), 0, 3)
        local spend_power = clamp(math.floor(spent / 5), 0, 2)
        base(factor_power + spend_power)
        scale(clamp(preview_might_potency(MIGHT, spent), 0, 3))
    elseif id == NORMAL_COUNTER then
        local spent = preview_might_spend(MIGHT, true)
        base(clamp(preview_might_potency(MIGHT, spent), 0, 3))
        if spent == 10 then scale(1) end
    elseif id == WITCH_S1 or id == WITCH_S1_INDISCRIMINATE then
        base(clamp(stack(SELF, MONSTROUS_MIGHT), 0, 5))
        final(clamp(math.floor(factor / 20), 0, 3))
    elseif id == WITCH_S2 or id == WITCH_S2_INDISCRIMINATE then
        base(clamp(stack(SELF, MONSTROUS_MIGHT), 0, 6))
        final(clamp(math.floor(factor / 20), 0, 3))
    elseif id == WITCH_S3
        or id == WITCH_S3_INDISCRIMINATE
        or id == WITCH_COUNTER_S3 then
        local spent = preview_might_spend(MONSTROUS_MIGHT, false)
        local spend_power = clamp(math.floor(spent / 5), 0, 2)
        local might_power = clamp(preview_might_potency(MONSTROUS_MIGHT, spent), 0, 10)
        base(spend_power + might_power)
        final(clamp(math.floor(factor / 20), 0, 4))
    elseif id == WITCH_COUNTER then
        local spent = preview_might_spend(MONSTROUS_MIGHT, true)
        local spend_power = spent == 10 and 3 or 0
        local might_power = clamp(preview_might_potency(MONSTROUS_MIGHT, spent), 0, 5)
        base(spend_power + might_power)
    end
end

function sherry_end_skill() end

function sherry_voice_skill_start()
    local id = skill_id()
    if id == NORMAL_S1 then
        play_sherry_voice("SherryPlayVoiceNormalS1")
    elseif id == NORMAL_S2 then
        play_sherry_voice("SherryPlayVoiceNormalS2")
    elseif id == NORMAL_COUNTER then
        play_sherry_voice("SherryPlayVoiceNormalCounter")
    end
end

function sherry_voice_final_coin()
    local id = skill_id()
    if id == WITCH_S3 or id == WITCH_S3_INDISCRIMINATE or id == WITCH_COUNTER_S3 then
        play_sherry_voice("SherryPlayVoiceWitchS3Final")
    elseif id == WITCH_COUNTER then
        play_sherry_voice("SherryPlayVoiceWitchCounterFinal")
    end
end

function sherry_counter_start()
    if data(D_COUNTER_FORCE_FIELD) == 1 then return end
    local barrier = clamp(math.floor(stack(SELF, WITCH_FACTOR) / 15), 0, 5)
    if barrier > 0 then
        setdata(SELF, D_COUNTER_FORCE_FIELD, 1)
        buff(SELF, "ChargeForceField", barrier, 0, 0)
    end
end

function sherry_counter_when_use()
    if data(D_COUNTER_CHANGED) == 1 then return end
    local keyword = current_might()
    if stack(SELF, keyword) < 5 or count(SELF, keyword) < 10 then return end

    setdata(SELF, D_COUNTER_CHANGED, 1)
    if is_witchized() then
        changeskill(WITCH_COUNTER_S3)
    else
        changeskill(NORMAL_COUNTER_S3)
    end
end

function sherry_stagger_threshold()
    local id = skill_id()
    if id == NORMAL_COUNTER then
        breakdmg(SELF, math.floor(gethp(SELF, "max") * 0.04), 1)
    elseif is_normal_s3(id) then
        breakdmg(TARGET, 10, 1)
    elseif id == WITCH_S3
        or id == WITCH_S3_INDISCRIMINATE
        or id == WITCH_COUNTER_S3 then
        breakdmg(TARGET, 20, 1)
    end
end

function sherry_skill3_coin_start()
    local spent = consume_might(10, false)
    if is_witchized() then
        final(spent)
    else
        final(math.floor(spent / 2))
    end
end

function sherry_skill3_fixed_damage()
    local consumed = data(D_SKILL_CONSUMED)
    if is_witch_s3(skill_id()) then
        fixed_damage(TARGET, clamp(5 + consumed, 0, 25))
    else
        fixed_damage(TARGET, clamp(5 + consumed, 0, 25))
    end
end

function sherry_gain_five_might()
    gain_might(0, 5)
end

function sherry_witch_s2_coin3()
    local sinking_potency = stack(SELF, "Sinking")
    if sinking_potency < 10 then
        buff(SELF, "Sinking", 10, 0, 0)
    else
        buff(SELF, "Sinking", 0, 1, 0)
    end
end

function sherry_s1_next_paralysis()
    if data(D_S1_NEXT_PARALYSIS) == 1 then return end
    setdata(SELF, D_S1_NEXT_PARALYSIS, 1)
    buff(TARGET, "Paralysis", 1, 0, 1)
end

function sherry_s2_next_vulnerable()
    if data(D_S2_NEXT_VULNERABLE) == 1 then return end
    setdata(SELF, D_S2_NEXT_VULNERABLE, 1)
    buff(TARGET, "Vulnerable", 1, 0, 1)
end

function sherry_detective_intuition()
    local enemies = selecttargets("Enemy99")
    if enemies == nil then return end
    local fastest = nil
    local fastest_speed = -1
    for _, enemy in ipairs(enemies) do
        local speed = getspeed(enemy)
        if speed > fastest_speed then
            fastest = enemy
            fastest_speed = speed
        end
    end
    if fastest ~= nil then
        buff(fastest, REBUTTAL, 1, 0, 0)
    end
end

function sherry_hanna_round_start()
    setdata(SELF, D_HANNA_COVER_USED, 0)
    local allies = selecttargets("Ally99")
    if allies == nil then return end
    for _, ally in ipairs(allies) do
        if getid(ally) == HANNA_ID then
            aggro(ally, 500, "this", 0)
            return
        end
    end
end

function sherry_hanna_battle_start()
    linkhannarevenge()
end

function sherry_support_noop() end

function sherry_fixed_10()
    fixed_damage(TARGET, 10)
end

function sherry_fixed_20()
    fixed_damage(TARGET, 20)
end

function sherry_fixed_30()
    fixed_damage(TARGET, 30)
end
