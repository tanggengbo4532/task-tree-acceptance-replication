# R112 已拿糯米后商铺街(scene51) HUD 仍“回村找糯米”修复

## 现场（只读用户槽1）
- 用户最新档 **B5A2CEE…**（12:52:40）：scene53 (896,896)，背包 **item76=2**，
  vars a24=1、a25=1、a26_clue=1、a26_item=1、a26_stage 未设。
- 之前截图在 **scene51 商铺街**（evt845 商店提示）时右上/中央仍出现「回白河村找糯米」：因为
  `_c3_scene_step(51)` 当时没有 case（返回空），`_build_merged_guide` 文案场景列表也不含 51；
  `_update_floor_label` 的 scene 分支也没有 51（顶栏沿用旧文案/空）。

## 修复（world.gd）
1) `_c3_scene_step(51)` 新增：
   - a26_stage>=1 → 回白河村（出村前往将军冢）；
   - **`_c3_has_rice()`（a26_clue/物品76）→ evt844「韩医仙家：回白河村经此交药引（第3章）」**；
   - a25_stage>=1 → 回白河村找糯米；否则 回白河村。
   evt844 = scene51 (768,944) mode5 SPACE → scene50 落点 (896,848)。
2) `_build_merged_guide` 场景列表加入 **51**（中央任务条显示目标+方向+N）。
3) `_update_floor_label` 增加 scene51 顶栏分支，并用 `_c3_has_rice()` 修正 scene50/53/54 顶栏：
   拿米后不再显示“正在取糯米/回村找糯米”，改为“回韩医仙家交药引/回白河村”等。
4) `_c3_has_rice()`（R111）继续作为唯一“已拿糯米”判定（真实物品 item76 兜底）。

## 验证（headless，槽1 只读）
- **scene51 (816,920)**（拿米后）：HUD「目标 韩医仙家：回白河村经此交药引（第3章）｜↓ 剩4格」，
  目标 evt844 (768,944)；真实按键 `D2,L2` 4步 N4→0 到 (784,936)，SPACE → scene50 (896,848)。
- **scene53 用户当前位置 (896,896)**：HUD「目标 韩医仙家：进门交药引（第3章）｜↑ 剩10格」，
  目标 evt886；真实按键 `U×9,L×1` 10步 N10→0 到 (880,824)，SPACE → scene54。
- scene54 带糯米：约1.2s 自动交药引 → a26_stage=1，HUD「回白河村（出村前往将军冢）」↓2 → evt904。
- 之后：evt904→scene53；scene53 a26_stage=1 → evt885 回白河村；白河村 → evt802 出村将军冢。
- boot exit0；槽1/2 未写。

## 路线文件（headless 真实按键逐步校验）
- `round82/keys_r112_19_scene51_evt844.txt`（scene51 (816,920)→evt844，4步 N4→0）
  SHA256 `861482207FBB73ECDDA75CB32C57FA3532777C1E32CD408888BFADA080E6ED3E`
- `round82/keys_r112_20_scene53_evt886_userpos.txt`（scene53 用户当前 (896,896)→evt886，10步 N10→0）
  SHA256 `662EDF9001A67929886E93AAD436C7A43610D4E6EFBC6764F27655ABAA2230DA`
- `round82/keys_r112_21_scene54_rice_delivery.txt`（scene54 带糯米自动交药引→evt904）
  SHA256 `3FCDE10FF6B5D87C552F5034A7F981BD3F8BFC1E8E553404D72457DBB5882EA9`
- 完整链：scene51 evt844→scene50 (896,848) → `keys_r109_15` 90步 → evt803→scene53 (416,1264)
  → `keys_r109_14` 84步 → evt886→scene54；或用户当前在 scene53 直接 `keys_r112_20` 10步。
