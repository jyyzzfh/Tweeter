--- 模块功能：MQTT客户端处理框架
-- @author openLuat
-- @module mqtt.mqttTask
-- @license MIT
-- @copyright openLuat
-- @release 2018.03.28

module(...,package.seeall)

require"misc"
require"mqtt"
require"mqttOutMsg"
require"mqttInMsg"
local ready = false
local slen = string.len
MqttClient  = {}
--- MQTT连接是否处于激活状态
-- @return 激活状态返回true，非激活状态返回false
-- @usage mqttTask.isReady()
function isReady()
    return ready
end

--启动MQTT客户端任务
sys.taskInit(
    function()
        local retryConnectCnt = 0
        while true do
            if not socket.isReady() then
                retryConnectCnt = 0
                --等待网络环境准备就绪，超时时间是5分钟
                sys.waitUntil("IP_READY_IND",300000)
            end
            
            if socket.isReady() then
                local imei = misc.getImei()
                --创建一个MQTT客户端
                local will = "{".."clientNo:'KS000807',msg:'0'".."}"
                will = crypto.aes_encrypt("ECB","PKCS5",will,"keson-123abcdefg")
                will = crypto.base64_encode(will,slen(will))
                local mqttClient = mqtt.client(imei,240,"admin","keson-123",nil,{qos=0,retain=0,
                topic="online",payload=will},"3.1")
                --阻塞执行MQTT CONNECT动作，直至成功
                --如果使用ssl连接，打开mqttClient:connect("lbsmqtt.airm2m.com",1884,"tcp_ssl",{caCert="ca.crt"})，根据自己的需求配置
                --mqttClient:connect("lbsmqtt.airm2m.com",1884,"tcp_ssl",{caCert="ca.crt"})
                if mqttClient:connect("47.94.80.3",61613,"tcp") then
                    retryConnectCnt = 0
                    ready = true
                    --订阅主题
                    if mqttClient:subscribe({["action/16"]=0,["quake/hebei"]=1}) then
                        mqttOutMsg.init()
                        --循环处理接收和发送的数据
                        while true do
                            if not mqttInMsg.proc(mqttClient) then log.error("mqttTask.mqttInMsg.proc error") break end
                            --if not mqttOutMsg.proc(mqttClient) then log.error("mqttTask.mqttOutMsg proc error") break end
                        end
                        mqttOutMsg.unInit()
                    end
                    ready = false
                else
                    retryConnectCnt = retryConnectCnt+1
                end
                --断开MQTT连接
                mqttClient:disconnect()
                if retryConnectCnt>=5 then link.shut() retryConnectCnt=0 end
                sys.wait(5000)
            else
                --进入飞行模式，20秒之后，退出飞行模式
                net.switchFly(true)
                sys.wait(20000)
                net.switchFly(false)
            end
        end
    end
)
