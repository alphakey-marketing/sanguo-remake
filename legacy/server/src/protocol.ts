// 協議 v0: JSON over WebSocket。以後再換二進制。
// client -> server
export type C2S =
  | { t: 'join'; name: string }
  | { t: 'move'; x: number; y: number }       // click 目標格
  | { t: 'attack'; target: number }
  | { t: 'chat'; text: string }
  | { t: 'rest' }                             // 客棧休息
  | { t: 'buy'; item: number; n: number }
  | { t: 'sell'; item: number; n: number };          // 攻擊意圖 (server 驗證 + 自動追擊)

// server -> client
export type S2C =
  | { t: 'welcome'; id: number; w: number; h: number; walls: number[] }
  | { t: 'snap'; tick: number; ents: EntView[] }   // AOI 內全部單位
  | { t: 'ev'; ev: Ev[] }                          // 戰鬥事件 (AOI 內)
  | { t: 'me'; ch: unknown }
  | { t: 'chat'; id: number; name: string; text: string };                      // 自己角色狀態

export interface EntView {
  id: number; name: string; x: number; y: number; face: number; bot: boolean;
  hp?: number; maxHp?: number; level?: number; mob?: boolean;
}
export type Ev =
  | { k: 'hit'; src: number; dst: number; dmg: number }     // dmg 0 = miss
  | { k: 'kill'; src: number; dst: number; exp: number; gold: number; items: number[]; lvUp: number }
  | { k: 'die'; dst: number; lost?: number }
  | { k: 'msg'; dst: number; text: string };          // 系統訊息(只發俾 dst)
