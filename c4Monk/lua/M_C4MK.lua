-- 混元武僧 v5.0 · 技能点面板
-- 版面在 c4mksp.menu；本文件负责账本、加点规则、页面开关。
-- 依赖：EEex v1.3.1（Infinity_PushMenu / EEex_Sprite_*LocalInt / EEex_Action_* / EEex_Key_*）
-- 语法约束：必须同时能在 Lua 5.2.4 与 LuaJIT 2.1(5.1) 下运行 —— 不用 goto / 整除 / 位运算 / table.unpack。

C4MK_MenuName = "C4MonkSp_Menu"
C4MK_IsOpen   = false
C4MK_Sprite   = nil      -- 页面锁定的角色（开页时定格，避免串号）
C4MK_Summary  = ""

-- v5.0 记账模型（只有一个点数变量）：
--   c4mkspg = 已发放总数的高水位，由 CLAB 在偶数级 Set 成 i/2（只增不减 → 漏发的级会被下一级补齐）
--   剩余点数 = c4mkspg - 已花费，纯派生值，不落盘 → 不存在"点数记错"
C4MK_GRANTED_VAR = "c4mkspg"

local function loc(sprite, name)
	if not sprite then return 0 end
	return EEex_Sprite_GetLocalInt(sprite, name)
end

local function repeat_str(s, n)
	local out = ""
	for i = 1, n do out = out .. s end
	return out
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
		return head .. "\n" .. body .. "\n\n" .. desc
	end
	return head .. "\n" .. body
end

function C4MK_Refresh()
	local sp = C4MK_Sprite
	C4MK_Summary = "剩余 " .. C4MK_Left(sp) ..
		" 点 · 已加 " .. C4MK_Spent(sp) .. " / 共 " .. C4MK_Granted(sp)
end

----------------------------------------------------------------------
-- 页面开关
----------------------------------------------------------------------

function C4MK_Open(sprite)
	C4MK_Sprite = sprite or EEex_Sprite_GetSelected()
	C4MK_Refresh()
	if not C4MK_IsOpen then
		Infinity_PushMenu(C4MK_MenuName)
		C4MK_IsOpen = true
	end
end

function C4MK_Close()
	if C4MK_IsOpen then
		Infinity_PopMenu(C4MK_MenuName)
		C4MK_IsOpen = false
	end
end

function C4MK_Toggle(sprite)
	if C4MK_IsOpen then
		C4MK_Close()
	else
		C4MK_Open(sprite)
	end
end

-- opcode 402 回调（函数名必须 ≤8 字符且全大写）
-- 由先天能力「技能学习」c4mkski1.spl 触发 → 打开技能点面板
function C4MKUI(op402, sprite)
	C4MK_Toggle(sprite)
end

-- 调试热键（保留，方便排查；不影响玩家）
if EEex_Key_GetFromName and EEex_Key_AddPressedListener then
	C4MK_DebugKey = EEex_Key_GetFromName("k")
	EEex_Key_AddPressedListener(function(key)
		if key == C4MK_DebugKey then
			C4MK_Toggle()
		end
	end)
end

-- 先填一遍默认值，避免菜单在首次刷新前渲染空表报错
C4MK_Refresh()