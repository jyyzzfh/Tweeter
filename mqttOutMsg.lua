--- 模块功能：MQTT客户端数据发送处理
-- @author openLuat
-- @module mqtt.mqttOutMsg
-- @license MIT
-- @copyright openLuat
-- @release 2018.03.28


module(...,package.seeall)
require "misc"
--数据发送的消息队列
local msgQueue = {}
local topic,sendMsg = "",""
local count = 0

local function insertMsg(topic,payload,qos,user)
    table.insert(msgQueue,{t=topic,p=payload,q=qos,user=user})
    sys.publish("APP_SOCKET_SEND_DATA")
end

--[[ local function pubGasAlarmcb(result)
    log.info("mqttOutMsg.pubGasAlarmcb",result)
    if result then sys.timerStart(pubGasAlarm,10000) end
end
--插入主题为"gas/gas/{clientNo}"的消息到消息队列,震动报警信息发布
function pubGasAlarm()
    topic = "gas/gas/"..tostring(misc.getImei())
    sendMsg ="{".."gas:5"..",".."sysTime"..os.time().."}"
    insertMsg(topic,sendMsg,0,{cb=pubGasAlarmcb})
end

local function pubVibrationAlarmcb(result)
    log.info("mqttOutMsg.pubVibrationAlarmcb",result)
    if result then sys.timerStart(pubVibrationAlarm,10000) end
end
--插入主题为"gas/local/{clientNo}"的消息到消息队列,震动报警信息发布
function pubVibrationAlarm()
    topic = "gas/local/"..tostring(misc.getImei())
    sendMsg ="{".."local:".."5"..",".."sysTime"..os.time().."}"
    insertMsg(topic,sendMsg,0,{cb=pubVibrationAlarmcb})
end

local function pubEarthquakeEarlyWarningcb(result)
    log.info("mqttOutMsg.pubEarthquakeEarlyWarningcb",result)
    if result then sys.timerStart(pubEarthquakeEarlyWarning,20000) end
end
--插入主题为"gas/quake/{clientNo}"的消息到消息队列，地震预警主题发布
function pubEarthquakeEarlyWarning()
    topic = "gas/quake/"..tostring(misc.getImei())
    sendMsg ="{".."quake:"..tostring(earthquakeWaring.Intensity)..",".."sysTime:"..os.time().."}"
    insertMsg(topic,sendMsg,0,{cb=pubEarthquakeEarlyWarningcb})
end

local function pubEquipmentLocationcb(result)
    log.info("mqttOutMsg.pubEquipmentLocationcb",result)
    if result then sys.timerStart(pubEquipmentLocation,10000) end
end


--插入主题为"gas/online/{clientNo}"的消息到消息队列
function pubEquipmentLocation()
    topic = "gas/online/"..misc.getImei()
    log.info("Imei",misc.getImei())
    sendMsg ="{".."longitude:"..tostring(getLbsLoc.Lng)..",".."latitude:"..tostring(getLbsLoc.Lat)..",".."sysTime:"..os.time().."}"
    insertMsg(topic,sendMsg,0,{cb=pubEquipmentLocationcb})
end]]

local function pubQos0TestCb(result)
    log.info("mqttOutMsg.pubQos0TestCb",result)
    if result then sys.timerStart(pubQos0Test,10000) end
end 

function pubQos0Test()
    insertMsg("/qos0topic","qos0data",0,{cb=pubQos0TestCb})
end

local function pubQos1TestCb(result)
    log.info("mqttOutMsg.pubQos1TestCb",result)
    if result then sys.timerStart(pubQos1Test,20000) end
end

function pubQos1Test()
    insertMsg("/中文qos1topic","中文qos1data",1,{cb=pubQos1TestCb})
end

--- 初始化“MQTT客户端数据发送”
-- @return 无
-- @usage mqttOutMsg.init()
function init()
    pubQos0Test()
    pubQos1Test()
end

--- 去初始化“MQTT客户端数据发送”
-- @return 无
-- @usage mqttOutMsg.unInit()
function unInit()
    sys.timerStop(pubQos0Test)
    sys.timerStop(pubQos1Test)
    while #msgQueue>0 do
        local outMsg = table.remove(msgQueue,1)
        if outMsg.user and outMsg.user.cb then outMsg.user.cb(false,outMsg.user.para) end
    end
end


--- MQTT客户端数据发送处理
-- @param mqttClient，MQTT客户端对象
-- @return 处理成功返回true，处理出错返回false
-- @usage mqttOutMsg.proc(mqttClient)
function proc(MqttClient)
    while #msgQueue>0 do
        local outMsg = table.remove(msgQueue,1)
        local result = MqttClient:publish(outMsg.t,outMsg.p,outMsg.q)
        if outMsg.user and outMsg.user.cb then outMsg.user.cb(result,outMsg.user.para) end
        if not result then return end
    end
    return true
end
