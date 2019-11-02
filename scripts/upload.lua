-- upload.lua

--==========================================
-- 文件上传
--==========================================

local upload = require "resty.upload"
local cjson = require "cjson"

-- msg : for return
local msg = {
    status = 200,
    msg = "ok"
}

-- chunk 大小需要待确定
local chunk_size = 8190
local form, err = upload:new(chunk_size)
if not form then
    ngx.log(ngx.ERR, "failed to new upload: ", err)
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

form:set_timeout(1000)

-- 字符串 split 分割
string.split = function(s, p)
    local rt= {}
    string.gsub(s, '[^'..p..']+', function(w) table.insert(rt, w) end )
    return rt
end

-- 支持字符串前后 trim
string.trim = function(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- 文件保存的根路径
local saveRootPath = "/home/work/filesystem/upload"

-- 保存的文件对象
local fileToSave

--文件是否成功保存
local ret_save = false

local final_save_path = ""

local function checkFileExist(path)
    local file = io.open(path, "rb")
    if file then file:close() end
    return file ~= nil
end

local save_store_path = saveRootPath .. "/" .. ngx.var.store_path
if not checkFileExist(save_store_path) then
    os.execute("mkdir -p " .. save_store_path)
    if not checkFileExist(save_store_path) then
        msg["status"] = ngx.HTTP_INTERNAL_SERVER_ERROR
        msg["msg"] = "interval error, cannot create directory"
    end
end

while true do
    local typ, res, err = form:read()
    if not typ then
        msg["status"] = ngx.HTTP_INTERNAL_SERVER_ERROR
        msg["msg"] = "failed to read: " .. err
    end

    if typ == "header" then
        -- 开始读取 http header
        -- 解析出本次上传的文件名
        local key = res[1]
        local value = res[2]
        if key == "Content-Disposition" then
            -- 解析出本次上传的文件名
            -- form-data; name="testFileName"; filename="testfile.txt"
            local kvlist = string.split(value, ';')
            for _, kv in ipairs(kvlist) do
                local seg = string.trim(kv)
                if msg["status"] == ngx.HTTP_OK and seg:find("filename") then
                    local kvfile = string.split(seg, "=")
                    local filename = string.sub(kvfile[2], 2, -2)

                    final_save_path = save_store_path .. "/" .. filename
                    if checkFileExist(final_save_path) then
                        msg["status"] = ngx.HTTP_BAD_REQUEST
                        msg["msg"] = "file exists, please check"
                    elseif filename then
                        fileToSave = io.open(final_save_path, "w+")
                        if not fileToSave then
                            msg["status"] = ngx.HTTP_INTERNAL_SERVER_ERROR
                            msg["msg"] = "failed to open file"
                        end
                        break
                    end
                end
            end
        end
    elseif typ == "body" then
        -- 开始读取 http body
        if fileToSave and msg["status"] == ngx.HTTP_OK then
            fileToSave:write(res)
        end
    elseif typ == "part_end" then
        -- 文件写结束，关闭文件
        if fileToSave then
            fileToSave:close()
            fileToSave = nil
        end
        ret_save = true
    elseif typ == "eof" then
        -- 文件读取结束
        break
    end
end

if msg["status"] == ngx.HTTP_OK then
   msg["md5"] = string.split(io.popen("md5sum " .. final_save_path):read("*a"), " ")[1]
end

ngx.say(cjson.encode(msg))