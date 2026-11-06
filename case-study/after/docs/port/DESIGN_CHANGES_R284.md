# R284 修复 scene139 战后“飞位/HUD 消失”

## 用户档解析（最新槽1 14F29F88…）
- scene139，绝对位置 **(1360,672)**（native 可走，但不是战斗前位置）
- HUD target evt2342 **N109**；事件2342 state=2；vars `a36_route=1, a36_stage=0, battle_team=42`；HP 李114/林0
- 战斗前/剧情门位置应为 **(1552,1432)**（scene139 入口；HUD evt2342 N16）

## 根因
- `script_vm._do_viewport` 的 `0x007F a2==0xFFFF`（瞬移视口）旧实现把 `party[0]` 屏幕坐标重置(160,112)，
  绝对坐标 = 新 viewport + (160,112) → **队伍被瞬间带到新区域**。
- scene139 六脚蜘蛛战后脚本21692 有 `0x007F(42,32,0xFFFF)`（+后续 pan）→ 队伍从战斗前(1552,1432)
  被写到(1360,672)，即用户看到的“飞到不可走位置”；HUD/剧情状态未推进，提示异常。

## 修复
1. **script_vm.gd `_do_viewport`**：a2==0xFFFF 只移动镜头，保存原绝对坐标，重算 party 屏幕坐标，
   **绝对位置不变**（与 pan/复位分支同语义）。
2. **world.gd**：
   - `_rescue_party_if_unwalkable()`：读档/战斗结束后若绝对位置不可走，就近救援到可走格（不跨场景）。
   - `R284-S139POST`：读档 scene139 且 `a36_route>=1/a36_stage<1/battle_team==42/evt2342 state>=2`
     且离战斗前位置>240 时，恢复到 **(1552,1432)**（战斗前剧情门锚点），不改 a36 进度。
   - 读档清 HUD 寻路缓存，确保 c3 提示重建。

## headless 证据（q2090，用户最新档只读副本→槽2）
```
[save] R284-S139POST restore pre-battle door pos (1360,672) -> (1552,1432)
[qa] scene=139 pos=(1552,1432) HUD=…进入蜀山…target_evt=2342 N=16 obstacle=false
[qb] viewport42,32 before=(1552,1432) after=(1552,1432) same=true
```
- 位置可走、HUD target evt2342 N16、无 GameOver；viewpoint 瞬移不再改绝对位置。

## 状态
- boot exit0；槽1只读；未开窗/未做实机；槽2=14F29F88副本
- 说明：旧存档已经写飞的位置在加载时按安全锚点恢复；新战斗不再产生飞位。
