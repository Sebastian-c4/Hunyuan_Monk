-- 混元武僧 v5.0 · 技能点面板
-- 版面在 c4mksp.menu；本文件负责账本、加点规则、页面开关。
-- 依赖：EEex v1.3.1（Infinity_PushMenu / EEex_Sprite_*LocalInt / EEex_Action_* / EEex_Key_*）
-- 语法约束：必须同时能在 Lua 5.2.4 与 LuaJIT 2.1(5.1) 下运行 —— 不用 goto / 整除 / 位运算 / table.unpack。

-- 没有用 InfinityLoader.exe 启动时 EEex 不活动，直接退出（M___EEex.lua 也会先报错）
if EEex_Active == false then return end

C4MK_MenuName = "C4MonkSp_Menu"
C4MK_IsOpen   = false
C4MK_Sprite   = nil      -- 页面锁定的角色（开页时定格，避免串号）
C4MK_Summary  = ""
C4MK_ClosedAt = nil      -- 关闭时刻（os.time），用于 2 秒内不重复弹回

-- 调试开关（发布版全部关闭）
--   C4MK_DEBUG     = true  消息栏/控制台打 [C4MK] 面包屑，并跑 C4MK_Open 里的 SetArea 探针
--   C4MK_DEBUG_KEY = true  注册 K 键开关面板（正式入口是先天能力「技能学习」）
C4MK_DEBUG = false
C4MK_DEBUG_KEY = false
function C4MK_Dbg(msg)
	if not C4MK_DEBUG then return end
	local line = "[C4MK] " .. tostring(msg)
	if Infinity_DisplayString then pcall(Infinity_DisplayString, line) end
	pcall(print, line)
end

-- v5.0 记账模型（只有一个点数变量）：
--   c4mkspg = 已发放总数的高水位，由 CLAB 在偶数级 Set 成 i/2（只增不减 → 漏发的级会被下一级补齐）
--   剩余点数 = c4mkspg - 已花费，纯派生值，不落盘 → 不存在"点数记错"
C4MK_GRANTED_VAR = "c4mkspg"

-- 当前时间（秒）。没有 os.time 时返回 0，此时不做"刚关闭"抑制
function C4MK_Now()
	if os and os.time then
		local ok, t = pcall(os.time)
		if ok and type(t) == "number" then return t end
	end
	return 0
end

local function loc(sprite, name)
	if not sprite then return 0 end
	return EEex_Sprite_GetLocalInt(sprite, name)
end

local function repeat_str(s, n)
	local out = ""
	for i = 1, n do out = out .. s end
	return out
end

-- 按显示宽度折行：ASCII 记 1，UTF-8 多字节字符（中文）记 2。
-- 不用 utf8 库，LuaJIT(5.1) 没有；也不用 goto。
function C4MK_Wrap(text, maxw)
	local out, linew, i, n = {}, 0, 1, #text
	while i <= n do
		local b = text:byte(i)
		local len = 1
		if b >= 0xF0 then len = 4
		elseif b >= 0xE0 then len = 3
		elseif b >= 0xC0 then len = 2 end
		local ch = text:sub(i, i + len - 1)
		if ch == "\n" then
			out[#out + 1] = "\n"
			linew = 0
		else
			local w = (len == 1) and 1 or 2
			if linew + w > maxw and linew > 0 then
				out[#out + 1] = "\n"
				linew = 0
			end
			out[#out + 1] = ch
			linew = linew + w
		end
		i = i + len
	end
	return table.concat(out)
end

----------------------------------------------------------------------
-- 技能线定义（变量名全部 ≤8 字符，避开 resource 字段的长度限制）
--   name 只是兜底；正常情况下显示 M_C4MKT.lua 里注入的 tra 文本
--   kind: fist    七条拳法，无前置，每条 5 级
--         body    身法，第 n 级需要角色等级 >= 6n（等价于已发放 >= 3n）
--         hla     高等身法，来自 HLA（AP_C4MKBDX），不消耗点数、不可点
--         mental  心法，第 n 条需要角色等级 >= 8(n-1)（等价于已发放 >= 4(n-1)）
----------------------------------------------------------------------

C4MK_LINES = {
	{ id = "body",  name = "混元身法",     var = "c4mkbd",  max = 5, kind = "body" },
	{ id = "bodyx", name = "高等混元身法", var = "c4mkbdx", max = 1, kind = "hla"  },
	{ id = "m1", name = "凌波微步",   var = "c4mkm1", max = 1, kind = "mental", idx = 1 },
	{ id = "m2", name = "仙风云体术", var = "c4mkm2", max = 1, kind = "mental", idx = 2 },
	{ id = "m3", name = "五气朝元",   var = "c4mkm3", max = 1, kind = "mental", idx = 3 },
	{ id = "m4", name = "凝神归元",   var = "c4mkm4", max = 1, kind = "mental", idx = 4 },
	{ id = "f1", name = "冰魄", var = "c4mkf1", max = 5, kind = "fist", idx = 1 },
	{ id = "f2", name = "烈火", var = "c4mkf2", max = 5, kind = "fist", idx = 2 },
	{ id = "f3", name = "雷音", var = "c4mkf3", max = 5, kind = "fist", idx = 3 },
	{ id = "f4", name = "蚀骨", var = "c4mkf4", max = 5, kind = "fist", idx = 4 },
	{ id = "f5", name = "斩铁", var = "c4mkf5", max = 5, kind = "fist", idx = 5 },
	{ id = "f6", name = "穿心", var = "c4mkf6", max = 5, kind = "fist", idx = 6 },
	{ id = "f7", name = "疾风", var = "c4mkf7", max = 5, kind = "fist", idx = 7 },
}

C4MK_BY_ID = {}
for i = 1, #C4MK_LINES do C4MK_BY_ID[C4MK_LINES[i].id] = C4MK_LINES[i] end

function C4MK_Line(id) return C4MK_BY_ID[id] end

----------------------------------------------------------------------
-- 文本（strref 由 WeiDU 注入 M_C4MKT.lua；未注入时退回上面的内置名称）
----------------------------------------------------------------------

local function txt(key)
	local tbl = C4MK_TXT
	if type(tbl) ~= "table" then return nil end
	local ref = tonumber(tbl[key])
	if not ref then return nil end
	return Infinity_FetchString(ref)
end

function C4MK_Name(line)
	return txt("name_" .. line.id) or line.name
end

----------------------------------------------------------------------
-- 账本
----------------------------------------------------------------------

function C4MK_Granted(sprite) return loc(sprite, C4MK_GRANTED_VAR) end

-- 已花费 = 各技能线等级之和；高等身法来自 HLA，不消耗点数
function C4MK_Spent(sprite)
	local n = 0
	for i = 1, #C4MK_LINES do
		local line = C4MK_LINES[i]
		if line.kind ~= "hla" then
			n = n + loc(sprite, line.var)
		end
	end
	return n
end

function C4MK_Left(sprite)
	local left = C4MK_Granted(sprite) - C4MK_Spent(sprite)
	if left < 0 then left = 0 end
	return left
end

----------------------------------------------------------------------
-- 加点规则
----------------------------------------------------------------------

-- 第 nextLvl 级要求的"已发放点数"（= 角色等级门槛 / 2）
function C4MK_GateNeed(line, nextLvl)
	if line.kind == "fist" then return 0 end
	if line.kind == "body" then return 3 * nextLvl end
	-- 心法四条各 1 级，门槛看它是第几条：0 / 8 / 16 / 24 级
	if line.kind == "mental" then return 4 * (line.idx - 1) end
	return 0
end

-- 返回不可加点的原因（nil 表示可以加）
function C4MK_BlockReason(id)
	local line = C4MK_Line(id)
	local sp = C4MK_Sprite
	if not line or not sp then return "没有目标角色" end
	if line.kind == "hla" then return "高等身法由 HLA 提供" end

	local cur = loc(sp, line.var)
	local nextLvl = cur + 1
	if cur >= line.max then return "已满级" end
	if C4MK_Left(sp) < 1 then return "技能点不足" end

	local need = C4MK_GateNeed(line, nextLvl)
	if C4MK_Granted(sp) < need then
		return "需要角色等级 " .. (need * 2)
	end
	return nil
end

function C4MK_CanBuy(id)
	return C4MK_BlockReason(id) == nil
end

-- 第 n 级要施放的法术
function C4MK_BuySpell(line, n)
	if line.kind == "fist" then
		local letter = string.sub("abcde", n, n)
		return "c4mkf" .. line.idx .. letter
	elseif line.kind == "body" then
		return "c4mkgb" .. n
	elseif line.kind == "mental" then
		return "c4mkmt" .. line.idx .. "a"
	end
	return nil
end

function C4MK_Buy(id)
	local line = C4MK_Line(id)
	local sp = C4MK_Sprite
	local reason = C4MK_BlockReason(id)
	if reason then
		Infinity_DisplayString("[" .. (line and C4MK_Name(line) or id) .. "] " .. reason)
		return false
	end

	local n = loc(sp, line.var) + 1
	EEex_Sprite_SetLocalInt(sp, line.var, n)
	EEex_Action_ExecuteResponseStringOnAIBaseInstantly(
		'ReallyForceSpellRES("' .. C4MK_BuySpell(line, n) .. '",Myself)', sp)
	-- 身法满级：c4mkgb5 自带 313，等于已打上 HLA 前置标志，这里只记"发过了"
	if line.kind == "body" and n >= line.max then
		EEex_Sprite_SetLocalInt(sp, "c4mkbdxm", 1)
	end
	C4MK_Refresh()
	return true
end

----------------------------------------------------------------------
-- 显示
----------------------------------------------------------------------

function C4MK_Pips(cur, max)
	return repeat_str("●", cur) .. repeat_str("○", max - cur)
end

-- 每行显示的文字（.menu 里用 text lua "C4MK_Text('f1')"）
function C4MK_Text(id)
	local line = C4MK_Line(id)
	if not line then return "?" end
	local sp = C4MK_Sprite
	local cur = loc(sp, line.var)
	local name = C4MK_Name(line)

	if line.kind == "hla" then
		return name .. "    " .. (cur >= 1 and "已学" or "未学")
	end

	local pips = C4MK_Pips(cur, line.max)
	local tail
	if line.max == 1 then
		tail = cur >= 1 and "已学" or ("需 " .. (C4MK_GateNeed(line, 1) * 2) .. " 级")
	else
		tail = cur .. " / " .. line.max
	end
	return name .. "    " .. pips .. "    " .. tail
end

-- 悬停提示：名称/进度 + 下一级要花什么 + tra 里的技能说明
function C4MK_Tip(id)
	local line = C4MK_Line(id)
	if not line then return "" end
	local sp = C4MK_Sprite
	local cur = loc(sp, line.var)
	local name = C4MK_Name(line)

	local head, body
	if line.kind == "hla" then
		head = name .. "    " .. (cur >= 1 and "已学" or "未学")
		body = cur >= 1 and "由 HLA 提供，不消耗技能点。" or "在 HLA 列表里选择「高等混元身法」，选中即完成修习。"
	elseif cur >= line.max then
		head = name .. "    " .. cur .. " / " .. line.max
		body = "已修满。"
	else
		local nextLvl = cur + 1
		local need = C4MK_GateNeed(line, nextLvl)
		head = name .. "    " .. cur .. " / " .. line.max
		body = "下一级：花 1 点（第 " .. nextLvl .. " 级"
		if C4MK_Granted(sp) < need then
			body = body .. "，需角色等级 " .. (need * 2)
		elseif need > 0 then
			body = body .. "，等级已满足"
		end
		body = body .. "）"
		if C4MK_BlockReason(id) then
			body = body .. "\n现在还不能加：" .. C4MK_BlockReason(id)
		end
	end

	local desc = txt("desc_" .. id)
	if desc and desc ~= "" then
		-- 中文没有空格，引擎不会自动折行，按显示宽度手工插入换行
		return head .. "\n" .. body .. "\n\n" .. C4MK_Wrap(desc, 24)
	end
	return head .. "\n" .. body
end

function C4MK_Refresh()
	local sp = C4MK_Sprite
	C4MK_Summary = "剩余 " .. C4MK_Left(sp) ..
		" 点 · 已加 " .. C4MK_Spent(sp) .. " / 共 " .. C4MK_Granted(sp)
end

-- 身法满 5 级要打 HLA 前置标志 AP_C4MKBDX0（opcode 313），否则高等身法在 HLA
-- 界面根本不出现。新版由 c4mkgb5 自己带标志，这里只补 v5 之前就满级、身上没标志
-- 的老存档；c4mkbdxm 在这里置位，所以只会补一次。
function C4MK_EnsureBodyHLA(sprite)
	if not sprite then return end
	if loc(sprite, "c4mkbd") < 5 then return end
	if loc(sprite, "c4mkbdxm") >= 1 then return end
	EEex_Sprite_SetLocalInt(sprite, "c4mkbdxm", 1)
	EEex_Action_ExecuteResponseStringOnAIBaseInstantly(
		'ReallyForceSpellRES("c4mkbdx0",Myself)', sprite)
	C4MK_Dbg("grant body HLA marker c4mkbdx0")
end

----------------------------------------------------------------------
-- 页面开关
----------------------------------------------------------------------

-- 页面是否真的在屏上：优先问引擎（Infinity_IsMenuOnStack），
-- 自己的 C4MK_IsOpen 只是回退，避免被引擎关掉后状态脱节
function C4MK_IsPanelOpen()
	if Infinity_IsMenuOnStack then
		local ok, on = pcall(Infinity_IsMenuOnStack, C4MK_MenuName)
		if ok then return on == true or on == 1 end
	end
	return C4MK_IsOpen
end

function C4MK_Open(sprite)
	C4MK_Sprite = sprite or EEex_Sprite_GetSelected()
	-- 补标志是附带动作，失败也不能挡住开页
	pcall(C4MK_EnsureBodyHLA, C4MK_Sprite)
	C4MK_Refresh()
	C4MK_Dbg("open: sprite=" .. tostring(C4MK_Sprite ~= nil) .. " onStack=" .. tostring(C4MK_IsPanelOpen())
		.. " menuLoaded=" .. tostring(C4MK_MenuLoaded))
	if C4MK_IsPanelOpen() then return end

	local ok, err = pcall(Infinity_PushMenu, C4MK_MenuName)
	C4MK_Dbg("push " .. C4MK_MenuName .. " -> " .. tostring(ok) .. " " .. tostring(err))
	if C4MK_DEBUG then
		-- 探针：元素找不到时 Infinity_SetArea 会抛 Lua 错，可据此判断菜单是否真被引擎注册
		local ok2, err2 = pcall(Infinity_SetArea, "C4MK_Bg", 100, 120, 820, 344)
		C4MK_Dbg("setarea -> " .. tostring(ok2) .. " " .. tostring(err2))
	end
	C4MK_IsOpen = true
end

function C4MK_Close()
	if not C4MK_IsPanelOpen() then
		C4MK_IsOpen = false
		return
	end

	local ok, err = pcall(Infinity_PopMenu, C4MK_MenuName)
	C4MK_Dbg("pop -> " .. tostring(ok) .. " " .. tostring(err))
	C4MK_IsOpen = false
	-- 只记关闭时刻：同一次施法里多出来的 402 不要立刻把页面顶回来。
	-- 不要用"忽略 N 次"的计数 —— 那个计数没人清零，会把之后真实的一次施法也吃掉。
	C4MK_ClosedAt = C4MK_Now()
end

function C4MK_Toggle(sprite)
	if C4MK_IsPanelOpen() then
		C4MK_Close()
	else
		C4MK_Open(sprite)
	end
end

-- opcode 402 回调（函数名必须 ≤8 字符且全大写）
-- 由先天能力「技能学习」c4mkski1.spl 触发 → 打开技能点面板
function C4MKUI(op402, sprite)
	C4MK_Dbg("402 fired: sprite=" .. tostring(sprite ~= nil))
	-- 只开不关；已经在屏上就直接返回（同一次施法可能 decode 两遍）
	if C4MK_IsPanelOpen() then return end
	local t = C4MK_Now()
	if C4MK_ClosedAt and t > 0 and (t - C4MK_ClosedAt) < 2 then
		C4MK_Dbg("402 ignored (just closed)")
		return
	end
	C4MK_Open(sprite)
end

-- 调试热键（默认关，见文件顶部 C4MK_DEBUG_KEY）
--   正式入口是先天能力「技能学习」（opcode 402）；这个 K 只是排查时的后门
if C4MK_DEBUG_KEY and EEex_Key_GetFromName and EEex_Key_AddPressedListener then
	C4MK_DebugKey = EEex_Key_GetFromName("k")
	EEex_Key_AddPressedListener(function(key)
		if key == C4MK_DebugKey then
			C4MK_Dbg("key K pressed")
			C4MK_Toggle()
		end
	end)
end

-- .menu 放进 override 不会被引擎自动加载：必须调 EEex_Menu_LoadFile 交给引擎，
-- 且时机要在 UI 主文件加载完成之后（EEex_Menu_AddAfterMainFileLoadedListener）。
C4MK_MenuLoaded = false
if EEex_Menu_LoadFile and EEex_Menu_AddAfterMainFileLoadedListener then
	EEex_Menu_AddAfterMainFileLoadedListener(function()
		if C4MK_MenuLoaded then return end
		local ok, err = pcall(EEex_Menu_LoadFile, "c4mksp")
		C4MK_MenuLoaded = ok
		if C4MK_DEBUG then
			pcall(print, "[C4MK] load c4mksp -> " .. tostring(ok) .. " " .. tostring(err))
		end
	end)
end

-- 先填一遍默认值，避免菜单在首次刷新前渲染空表报错
-- 注意：这里不能调用 Infinity_DisplayString —— 本文件由 includes.lua 在 UI 初始化阶段加载，
-- 此时该函数会触发原生访问违例（0xC0000005），pcall 也挡不住。
C4MK_Refresh()