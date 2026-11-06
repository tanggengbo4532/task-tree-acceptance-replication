# R274 恢复游戏内存档槽2 + 207/206/247/255/253 锚点

## A) 恢复游戏内存档槽2（R273 禁令调整）
- R273 曾完全禁止菜单存档槽2；tester 需要存进度，恢复。
- 新行为 R274-SLOT2CONFIRM：
  - 槽2允许存档；存档列表标记「（团队测试槽）」
  - 第一次按回车只提示「团队测试槽2：再按一次确认覆盖（槽1只读）」，第二次才写入
  - **保存不改变 current_save_slot**（R273已修，防GameOver读错档）
  - 槽1/3/4/5/9仍按团队纪律不碰
- boot exit0，无 SCRIPT ERROR

## B) 锚点（用户最新槽1 14B5CFBD只读副本，第6章李+阿奴）
- `round78/slot2_scene207_qilin_anchor.sav/.json`：scene207 (1024,1600)，a45=1，HUD evt3461 N238
  - sav SHA **C18606EF2EAF672F02A4E1C1DCA36D012BA42883134D0A47ED76D0CF1FD30725**
- `slot2_scene206_hall_anchor`：scene206 (864,1280)，a45=1，HUD evt3442 N0
  - sav SHA **037E385D44F4FE19B207147B35C0806DBC7294A561A3D26ADE0C248B825D56E9**
- `slot2_scene247_nanzhao_anchor`：scene247 (1568,1696)，a46=1/a47=1，HUD evt4365 N150
  - sav SHA **E3960B60627FB24B492515099111CF7682502C43812E68428B8ABC92C6DF8426**
- `slot2_scene255_palace_anchor`：scene255 (1680,1720)，a48=1，HUD 按空格决战 interact4466
  - sav SHA **C8347DE2440DE7B055B9BE388EAFE8C8B740452A3E785081500E57D6F577B61D**
- `slot2_scene253_finalbattle_anchor`：scene253 (336,376)，a49=1，HUD 按空格决战 interact4441
  - sav SHA **A2856EA48DA1FC1175AB76368D05E954BF9EA7B20F7D6D85FA6E42367461F945**
- README `slot2_scene207_253_anchors_README.md`
- 用户槽1未写；槽2恢复用户最新档

## C) headless 链进展
- 207锚点：HUD evt3461 N238；自动沿HUD走时被207场景白苗女兵交互提示打断（pos560,360 HUD「按空格询问白苗女兵」），未到门
- 207→206→247→255→253 真实门/脚本保留；tester 实机从207沿HUD走、绕开NPC交互到 evt3461 即可
- 188落点 movement 停点后置

## 状态
- boot exit0；槽1只读；槽2用户最新档；未开窗
