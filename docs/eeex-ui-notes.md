# EEex 自定义 UI 面板 · 实践笔记

> 整理日期：2026-11-28
> 来源：`bg-eeex-buffbot/docs/ui-menu-patterns.md`、`docs/weidu-packaging.md`（下称 BB-UI / BB-PKG）
> 加上本项目实际踩过的坑。标 **[实测]** 的是我们在混元武僧面板里跑通过的，标 **[BB]** 的是照抄参考实现、尚未在本项目单独验证。
> 目标读者：以后给 c4Monk 加面板（或别的 EEex mod）的人/agent。

---

## 1 加载链：面板出不出现由这条链决定

```
游戏启动
  └ includes.lua 逐个 Infinity_DoFile 加载 override 里的 M_*.lua   ← 顶层只能放纯 Lua
      └ 我们注册 EEex_Menu_AddAfterMainFileLoadedListener(回调)
          └ 回调里 EEex_Menu_LoadFile("<resref>")                 ← 菜单交给引擎
              └ 运行时 Infinity_PushMenu("<.menu 里的 name>")     ← 真正显示
```

四条铁律（都吃过亏）：**[实测]**

1. **`.menu` 拷进 override 不会自动加载**，必须 `EEex_Menu_LoadFile("resref")`（不带扩展名）。
2. 调用时机必须在 `EEex_Menu_AddAfterMainFileLoadedListener` 回调里；`M_*.lua` 顶层调引擎函数会原生崩溃
   （`Infinity_DisplayString` → `0xC0000005`，`pcall` 挡不住）。
3. `Infinity_PushMenu` 的参数是 `.menu` 里的 `name` 字段，不是文件名。
4. `Infinity_PushMenu` 对**未注册**的菜单也返回成功，不能用返回值判断；要判断用
   `Infinity_IsMenuOnStack("<name>")`，或给元素加 `name` 后用 `pcall(Infinity_SetArea, ...)` 探针。

骨架（本项目 `M_C4MK.lua` 的写法）：

```lua
if EEex_Active == false then return end          -- 没用 InfinityLoader 启动就别跑

C4MK_MenuLoaded = false
if EEex_Menu_LoadFile and EEex_Menu_AddAfterMainFileLoadedListener then
	EEex_Menu_AddAfterMainFileLoadedListener(function()
		if C4MK_MenuLoaded then return end        -- 幂等，防重复注册
		C4MK_MenuLoaded = pcall(EEex_Menu_LoadFile, "c4mksp")
	end)
end
```

---

## 2 `.menu` 语法速查（只列本项目用到的）

### 2.1 元素类型

| 类型 | 用途 | 备注 |
|---|---|---|
| `label` | 背景、图标、纯文本 | 不参与交互；`rectangle` / `bam` / `text` 都在这里 |
| `text` | 文本、可点行、**纯悬停块** | 可以带 `action`（UI.MENU 里有 49 处），也可以只有 `tooltip` 当透明悬停区 |
| `button` | 标准按钮 | 需要 `bam` 才有外观；`clickable` 的"灰显"语义在文档里主要写给 button |
| `list` | 滚动列表 | 数据用 `table`+`var`，行内可用 `rowNumber`/`cellNumber` |
| `template` | 原型，配合 `EEex_Menu_InjectTemplate` 实例化 | 复杂/动态网格才需要 |
| `handle` / `edit` / `slider` | 拖拽 / 输入 / 滑条 | 本面板暂未用 |

### 2.2 关键属性（含取值范围）

| 属性 | 取值 | 说明 |
|---|---|---|
| `enabled` | Lua 表达式 / `true` | **false = 整个元素不画**，不能当"置灰"用 |
| `clickable lua` | Lua 表达式 | false = 可见但灰、不可点；**这才是置灰** |
| `area` | `x y w h` | `-1` 表示填满可用空间 |
| `rectangle` | 0–7（BB-UI 说法） | **[实测]** UI.MENU 只用 0–4；写 5 时矩形**没画出来**，所以本项目统一用 `0`/`1` |
| `rectangle opacity` | 0–1000 | 1000 = 全不透明；800 = 80%，会透出背景 |
| `text` / `text lua` | 静态串 / Lua 表达式 | 静态串按 strref 或字面量解析 |
| `text align` | `<水平> <垂直>` | 如 `left center`、`center center` |
| `text color` | `255 255 255 255` 或单字符色码 | 深色底必须显式给白色，否则字看不见 |
| `text style` | `"normal"` 等 | 引用 BGEE.lua 里的样式 |
| `tooltip lua` | Lua 表达式 | 中文**不会自动折行**，见 §5 |
| `action` / `actionAlt` | Lua 语句 | 左键 / 右键回调 |
| `modal` / `modal lua` | 标志 / 表达式 | 模态时阻挡面板外点击 |
| `ignoreesc` | 标志 | ESC 不关闭（配合"只留关闭按钮"） |
| `onopen` / `onclose` | Lua 表达式 | 菜单入栈/出栈时回调，可用于复位状态 |

### 2.3 状态查询

`Infinity_IsMenuOnStack("<name>")` 返回菜单是否在栈上。**优先用它**，自己维护的布尔值容易与引擎脱节
（引擎可能在别处 pop 掉菜单）。本项目 `C4MK_IsPanelOpen()` 就是先问引擎、失败才回退到本地标志。

---

## 3 面板生命周期

```
PushMenu → onopen → 元素按 enabled 求值渲染
PopMenu  → onclose → 元素从显示栈移除
```

- 多个菜单可同时在栈上，后 push 的在上层、先收输入。
- 关闭方式：面板内按钮调 `Infinity_PopMenu("<name>")`；`ignoreesc` 时 ESC 无效。
- **防止"关了又弹回来"**：如果打开动作是脚本/效果触发（如 opcode 402），关闭后加一段**时间窗口**抑制
  （本项目：关闭后 2 秒内的触发忽略）；另外"已经开着就直接返回"。
  **不要用"忽略接下来 N 次触发"的计数**：计数没人清零，会把之后真实的一次施法吃掉——
  表现就是"第一次用技能没反应，按几次才行"。

---

## 4 交互与置灰

- 可点行用 `text` + `action`（`text` 支持 action，UI.MENU 有先例）。
- 置灰用 `clickable lua "<expr>"`；**不要**用 `enabled`，否则整行消失。
- 注意：BB-UI 的 `clickable` 只明确写在 `button` 上。`text` 上是否生效还没在本项目确认过；
  因此 action 回调里必须再校验一次（`C4MK_Buy` 会检查点数/前置并给出原因），不能只靠灰显挡人。

---

## 5 排版：中文与悬停提示

- **中文不自动折行**：引擎按空格断行，中文没有空格。长说明要在 Lua 里按显示宽度手工插 `\n`
  （ASCII 记 1、中文记 2，每行约 24 单位）。不要用 `utf8` 库——LuaJIT 运行时没有。
- **图标不出 tooltip**：`label { bam ... }` 本身不触发悬停。在同样的 `area` 上叠一个只含
  `enabled true` + `tooltip lua` 的**透明 `text` 元素**（UI.MENU 里就是这种"纯悬停块"），
  悬停块上不要加 `action`。
- **字号**：`text point <n>` 在小节里对 `label` / `text` / `button` 都合法（UI.MENU 里有 45 处写在 `text`
  元素内，不是只给 `label`）。它只改元素自己的文字，**tooltip 不受影响**——想让页面字大、悬停提示不变大，
  加 `text point` 就够，不要去动全局字体。
- **底色**：`rectangle` 只能用引擎预置样式（0–4），颜色/纹理不可控，`opacity 1000` 也未必真的全不透明。
  要确定的深色底板就生成一张同尺寸的不透明 BAM，`bam` + `scaleToClip` 铺满，`rectangle` 留在下面兜底。
- **关闭按钮放右上，别放右下**：消息栏/文字框被玩家拉大后会盖住面板底部，右下角的按钮看着在、点不到。
  右上角放进标题条里最稳（顺带把右对齐的汇总行收窄让位）。
- `bam` 引用的 resref 不存在时**不报错**，只是那块空白；"某个图标没显示"先核对 menu 里的 resref 与
  `c4Monk/bam/` 里的文件名。

---

## 6 调试通道

| 通道 | 现象 | 适用时机 |
|---|---|---|
| `print(...)` | EEex 控制台 `INFO: LPRINT: ...` | 任何运行时回调；**加载期也可用** |
| `Infinity_DisplayString(...)` | 消息栏 | 仅运行时（UI 起来之后）；加载期调用会崩 |
| `pcall(Infinity_SetArea, "<元素名>", ...)` | 元素不存在 → 返回 false + 错误串 | 判断菜单是否真被注册 |
| `ni`（NearInfinity CLI） | 不认识 MENU，只对 SPL/BCS/2DA/TLK 有用 | 验证法术与脚本，不验证 .menu |

Lua 两个运行时都要跑：`lua52.exe`（5.2.4）与 `tools/luajit_run.py`（EEex 的 LuaJIT 2.1）。

---

## 7 安装与依赖

- `.menu` 只需 `COPY ... ~override~`；注册由 Lua 完成（BB-PKG §2.3 明确不 patch UI.MENU）。
- 安装期依赖检查推荐 `REQUIRE_PREDICATE (MOD_IS_INSTALLED ~EEex.tp2~ (ID_OF_LABEL ~EEex.tp2~ ~B3-EEex-Main~))`，
  用 label 而不是组件号，EEex 改编号也不会失效。本项目目前是 `REQUIRE_PREDICATE ((FILE_EXISTS_IN_GAME
  ~M___EEex.lua~) OR (FILE_EXISTS_IN_GAME ~EEex_Sprite.lua~)) @-10001`（组件 1 直接不可装，`sp_ui.tph`
  不再做 `ACTION_IF`/`WARN`）。
- 运行期守卫：`if EEex_Active == false then return end`（没用 InfinityLoader 启动时直接退出）。
- 探测 EEex 是否安装：看 `override/M___EEex.lua`（128 字节标记文件），**不是** `EEex_Sprite.lua`。

---

## 8 本项目踩过的坑（速查）

1. `rectangle 5` → 矩形不画，面板"全透明"。
2. `opacity 800` → 只有 80%，文字被背景吃掉。
3. `enabled "不可加"` → 整行消失（用户看不到"需 16 级"）。
4. 402 写成 `timing=1` 永久效果 → 引擎反复 decode，每秒触发一对，面板关不掉。
5. `M_*.lua` 顶层调 `Infinity_DisplayString` → 启动即 `0xC0000005`。
6. `Infinity_PushMenu` 假成功 → 以为菜单坏了，其实是没注册。
7. 用 `EEex_Sprite.lua` 探测 EEex → 永远探测不到。
8. `ni` 不校验 `.menu` → 菜单问题只能游戏内观察。
9. 用"忽略接下来 N 次 402"做关闭守卫 → 计数残留，之后真实施法被吃掉，表现成"技能点了没反应、按几次才行"。
   改成时间窗口（关闭后 2 秒）+ "已开着就返回"。

---

## 9 与 buffbot 文档的对应关系

| 我们用到/验证的 | BB 文档出处 |
|---|---|
| 加载链、`EEex_Menu_LoadFile` 注册 | BB-PKG §2.3、BB-UI §3.2–3.3 |
| `enabled` vs `clickable lua` | BB-UI §2.4、§1.4 属性表 |
| `rectangle` / `rectangle opacity` | BB-UI §1.2 label 一节 |
| `text` 的 action / 纯悬停块 | BB-UI §1.2 `text` 一节（Role 1 / Role 2）、§1.4 |
| `Infinity_IsMenuOnStack` | BB-UI §3.4 |
| `onopen` / `onclose` / `modal` | BB-UI §1.1 属性表 |
| 安装期 EEex 依赖检查 | BB-PKG §3.1、§3.2 |

BB 文档没有覆盖、本项目自己验证补充的：中文折行、图标悬停区、`rectangle` 越界不画、
402 永久效果反复触发、`M_*.lua` 加载期崩溃。