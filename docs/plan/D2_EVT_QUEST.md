# D2b — 逆向 evt VM，導入原版任務（新 session 用）

## 目標
由原版 evt 腳本 bytecode 抽出任務（名/接取 NPC/條件/步驟/對白/獎勵），出**候選清單 + `data/orig_quests.json`**（生成檔，唔手改）。
**只導入資料，唔實裝落地圖**（唔接 quest_npcs/地圖）。用家逐條揀先實裝。

## 已知
- `quests.json` 已有 `src` 欄：`custom` = remake 自寫（86 條，全部）；導入嘅原版任務用 `src:"orig"`，可按來源篩選對照。**唔好刪／收埋 custom。**
- 原版任務無結構化表；邏輯喺 evt bytecode：`D:\Download\sanguo\extracted\text\evt_evt1|evt2` (`ok_k1..k10.bin`)、`evt_evt1_disasm|evt2_disasm`（2769 檔，只有 hex + 字串）。
- 已有表：`evt_k2/k3/k4/k5/k2k3/chain_*.tsv`（觸發/條件/對白索引）、`evt_dialog_evt1/2.tsv`（對白文字，無 NPC 綁定）、`evt_all_strings.tsv`。
- 參考：`D:\Download\sanguo\docs\HANDOFF_evt.md`、`evt_腳本_PhaseA10.md`（`ok_k1` 觸發表，`ok_k7` 對話 87k 字串）。
- 探路失敗：用武將名關鍵字配對率低（`tools/evt_match.py`，22/86），任務名唔喺原版字串入面。

## 步驟建議
1. 讀 HANDOFF，確認 VM opcode 語義（trigger/cond/act/dialog/give item/set flag）。
2. 寫 `tools/evt_quest_dump.py`：以 chain 為單位輸出（觸發 NPC id → 條件 → 動作 → 對白 → 給/收道具/經驗）。NPC id 對 `Npc_table.tsv`、道具 id 對 `items.json`。
3. 分類：識別出「任務」（有 flag/多步）對「純店員/閒聊」，出 `docs/uat/orig_quests_candidates.md`。
4. 生成 `data/orig_quests.json` + `--check`，格式盡量貼 `quests.json`（加 `src:"orig"`、`evt` 來源 id）。
5. 對照現有 custom：標邊啲重複（同 NPC/獎勵）；報告畀用家揀。
## 驗收
`--check` OK；候選報告有 NPC 名/地圖/步驟/獎勵；`sh tools/run_tests.sh` ALL OK（新檔唔可令現有 leg fail）。
