module(..., package.seeall) -- 使得文件中的函数在何处都可调用
require "pins" -- 用到了pin库，该库为luatask专用库，需要进行引用
require "sys"
require "getLbsLoc"
require "rtos"
require "uartTask"
require "utils"
require "mqtt"
require "misc"
require "audio"
local ttsStr = "预警系统演练"
local slen = string.len
TTS = 1
-- 地震预警系统
-- 两个功能：1.预警系统演练（tts语音播报3遍同时报警音触发）
-- 入参：mqttData接收的预警信息
local setGpio9Fnc = pins.setup(pio.P0_9, 1) -- 静音设置（高电平静音）
function EarthquakeWarningDrillSystem(mqttData)
    log.info("jsonDataDrill", mqttData)
    local tjsondata, result, errinfo = json.decode(mqttData)
    if result and type(tjsondata) == "table" then
        local focal_longitude, focal_latitude, countDownSDrill, warningColor,
              quake_intensity, equipment_clients, early_warning_system_drill =
            tjsondata["8"], tjsondata["9"], tjsondata["1"], tjsondata["3"],
            tjsondata["2"], tjsondata["clients"], tjsondata["todo"]
        log.info("warningColor", warningColor)
        if containClientsOrNot(equipment_clients) then
            if early_warning_system_drill == "exercise" then
                sys.taskInit(signalRF433SerialCommunication, warningColor,
                             quake_intensity, countDownSDrill)
                if quake_intensity >= 5 then
                    sys.taskInit(earlyWarningDrill, countDownSDrill)
                end
            end
        end
    else
        print("json.decode error", errinfo)
    end
end
-- 地震预警主逻辑
function EarthquakeWarning(mqttData)
    log.info("jsonData", mqttData)
    local tjsondata, result, errinfo = json.decode(mqttData)
    if result and type(tjsondata) == "table" then
        -- magnitude:震级
        local focal_longitude, focal_latitude, quake_intensity, quakeTimeStr,
              magnitude, placeName, unitID = tjsondata["7"], tjsondata["8"],
                                             tjsondata["11"], tjsondata["5"],
                                             tjsondata["10"], tjsondata["13"],
                                             tjsondata["17"]
        log.info("Equipment_latitude", getLbsLoc.Lat, "Equipment_longitude",
                 getLbsLoc.Lng)
        if unitID == 8 then
            local setGpio04Fnc = pins.setup(pio.P0_04, 0) -- TEL-LED正常低电平，有信号时高电平，一秒一次
            local setGpio10Fnc = pins.setup(pio.P0_10, 0) -- 预警指示
            local setGpio11Fnc = pins.setup(pio.P0_11, 0) -- Buzzer正常低电平，预警高电平
            local sysTime = os.time()
            -- local sysTime = 1647005775
            log.info("sysTime", sysTime)
            local quakeTime = string2time(quakeTimeStr)
            log.info("quakeTime", quakeTime)
            -- 计算距离
            local distance = Algorithm(getLbsLoc.Lng, getLbsLoc.Lat,
                                       focal_longitude, focal_latitude) / 1000
            log.info("distance", distance)
            -- 计算S波到达时间 减1秒网络延时
            local countDownS = math.floor((distance / 3.5) -
                                              ((sysTime - quakeTime) / 1000))
            countDownS = countDownS < 0 and 0 or countDownS
            log.info("countDownS", countDownS)
            -- 烈度计算
            local intensity = math.floor(Round(
                                             quake_intensity - 4 *
                                                 math.log((distance / 10 + 1.0),
                                                          10)))
            log.info("intensity", intensity)
            if intensity <= 0 then intensity = 1 end
            -- 地震烈度大于等于设定预警临界值则执行报警
            local warningColor = getWarningColor(intensity)
            if intensity >= 5 then
                if countDownS > 0 then
                    setGpio9Fnc(0)
                    local count = 0
                    setGpio10Fnc(1)
                    setGpio11Fnc(1)
                    sys.taskInit(mqttQuakAlarmSendTask, intensity, warningColor,
                                 countDownS)
                    sys.taskInit(signalRF433SerialCommunication, warningColor,
                                 quake_intensity, countDownS)
                    sys.taskInit(solenoidValveOperationTask)
                    sys.taskInit(alarmLampOperationTask, countDownS)
                    while countDownS > 0 do
                        if countDownS <= 10 then
                            ttsStr = tostring(countDownS)
                            audio.play(TTS, "TTS", ttsStr, 7)
                        end
                        if math.fmod(count, 12) == 0 then
                            uartTask.write(0x0C)
                        end
                        --[[ if math.fmod(countDownS, 2) == 0 then -- 报警灯闪烁，偶数时灯灭
                            setGpio12Fnc(0)
                        else
                            setGpio12Fnc(1)
                        end ]]
                        sys.wait(1000)
                        countDownS = countDownS - 1
                        count = count + 1
                    end
                    setGpio9Fnc(1) -- 报警结束设置静音
                end
            end
            setGpio10Fnc(0)
            setGpio11Fnc(0)
        end
    else
        print("json.decode error", errinfo)
    end
end
-- 报警灯操作任务
function alarmLampOperationTask(countDownS)
    local count = 0
    local setGpio12Fnc = pins.setup(pio.P0_12, 0) -- 报警灯
    while countDownS > 0 do
        while count ~= 4 do
            setGpio12Fnc(1)
            count = count + 1
            sys.wait(250)
        end
        count = 0
        countDownS = countDownS - 1
        sys.wait(1000)
        countDownS = countDownS - 1
    end
    setGpio12Fnc(0)
end
-- 电磁阀操作任务
function solenoidValveOperationTask()
    local count1 = 0
    local setGpio23Fnc = pins.setup(pio.P0_23, 0) -- 电磁阀阀门控制端口设为低电平
    while count1 ~= 3 do
        setGpio23Fnc(1)
        count1 = count1 + 1
        sys.wait(1000)
    end
    setGpio23Fnc(0)
end
-- 获取震级颜色
function getWarningColor(intensity)
    local warningColor = 0
    if intensity >= 1 and intensity <= 3 then
        warningColor = 1
    elseif intensity >= 4 and intensity <= 5 then
        warningColor = 2
    elseif intensity >= 6 and intensity <= 7 then
        warningColor = 3
    elseif intensity >= 8 then
        warningColor = 4
    end
    return warningColor
end
-- string转time
function string2time(str)
    local Y = string.sub(str, 1, 4)
    local m = string.sub(str, 6, 7)
    local d = string.sub(str, 9, 10)
    local H = string.sub(str, 12, 13)
    local M = string.sub(str, 15, 16)
    local S = string.sub(str, 18, 23)
    return os.time({day = d, month = m, year = Y, hour = H, min = M, sec = S})
end
-- 预警演练设备身份判别
function containClientsOrNot(equipment_clients)
    do
        local containResult = false
        for i = 1, #equipment_clients do
            if equipment_clients[i] == "KS000807" then
                containResult = true
            end
        end
        log.info("containResult", containResult)
        return containResult
    end
end
-- 预警演练报警音
function earlyWarningDrill(countDownSDrill)
    log.info("tts voice")
    setGpio9Fnc(0)
    local countTTSDrill, countAlarmDrill = 0, 0
    uartTask.write(0x0C)
    while countTTSDrill ~= 3 do
        audio.play(TTS, "TTS", ttsStr, 7)
        countTTSDrill = countTTSDrill + 1
        sys.wait(1500)
    end
    sys.wait(500)
    countDownSDrill = countDownSDrill - 4
    countAlarmDrill = countAlarmDrill + 4
    while countDownSDrill >= 0 do
        if countDownSDrill < 10 then
            ttsStr = tostring(countDownSDrill)
            audio.play(TTS, "TTS", ttsStr, 7)
        end
        if math.fmod(countAlarmDrill, 12) == 0 then uartTask.write(0x0C) end
        countDownSDrill = countDownSDrill - 1
        sys.wait(1000)
    end
    setGpio9Fnc(1) -- 报警结束设置静音
end
-- 433射频信号串口通讯
function signalRF433SerialCommunication(warningColor, quake_intensity,
                                        countDownSDrill)
    uartTask.write(1, warningColor, quake_intensity, countDownSDrill)
end
-- 发送地震预警信息到后端系统
function mqttQuakAlarmSendTask(intensity, warningColor, countDownS)
    local topic = "tweeter/quake/" .. tostring(misc.getImei())
    local sendMsg = "{" .. "intensity:" .. tostring(intensity) ..
                        ",warningColor:" .. tostring(warningColor) ..
                        ",countDownS:" .. tostring(countDownS) .. "sysTime:" ..
                        os.time() .. "}"
    sendMsg = crypto.aes_encrypt("ECB", "PKCS5", sendMsg, "keson-123abcdefg")
    sendMsg = crypto.base64_encode(sendMsg, slen(sendMsg))
    local mqttClient = mqtt.client(misc.getImei(), nil, "admin", "keson-123",
                                   nil, nil, "3.1")
    if mqttClient:connect("47.94.80.3", 61613, "tcp") then
        mqttClient:publish(topic, sendMsg, 0)
    end
    mqttClient:disconnect()
end
function Algorithm(equipment_longitude, equipment_latitude, focal_longitude,
                   focal_latitude)
    local Lat1 = math.rad(equipment_latitude)
    log.info("focal_latitude:", focal_latitude)
    local Lat2 = math.rad(focal_latitude)
    local a = Lat1 - Lat2
    local b = math.rad(equipment_longitude) - math.rad(focal_longitude)
    local s = 2 *
                  math.asin(
                      math.sqrt(math.pow(math.sin(a / 2), 2) + math.cos(Lat1) *
                                    math.cos(Lat2) *
                                    math.pow(math.sin(b / 2), 2)))
    s = s * 6378137.0
    s = Round(s * 10000) / 10000; -- 精确距离的数值
    return s
end
function Round(x) return x >= 0 and math.floor(x + 0.5) or math.ceil(x - 0.5) end
