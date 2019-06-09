  ; header - defines number and size of sections
  .inesprg 1   ; 1x 16KB game code
  .ineschr 1   ; 1x  8KB graphics data
  .inesmap 0   ; mapper 0 = NROM, no bank swapping
  .inesmir 1   ; background mirroring
  
; constants
STATE_TITLE     = $00  ; displaying title screen
STATE_PLAYING   = $01  ; move player/enemy/projectiles, check for collisions
STATE_GAMEOVER  = $02  ; displaying game over screen

RIGHT_WALL      = $E8
TOP_WALL        = $04
BOTTOM_WALL     = $E0
LEFT_WALL       = $08

BULLET_SPEED    = $03
BULLET_ON       = %01
BULLET_OFF      = %00
ENEMY_TIME    = $30
ENEMY_HOR_STEP = $04
ENEMY_VERT_STEP= $08
ENEMY_HOR_GAP = $20
ENEMY_VERT_GAP = $10
ENEMY_RIGHT_EDGE = $5 * ENEMY_HOR_GAP + $08
ENEMY_COUNT = $0C

; variables
  .rsset $0000      ;start variables at $0000

gameState .rs 1     ; .rs 1 - reserve 1 byte of space

playerXPos .rs 1
buttonsPressed .rs 1
playerBulletX .rs 1
playerBulletY .rs 1
playerBulletState .rs 1

enemyBulletX .rs 1
enemyBulletY .rs 1
enemyBulletState .rs 1
enemyY .rs 1
enemyX .rs 1
enemyTimeCounter .rs 1
enemyDirection .rs 1
enemyCount .rs 1

; bank 0 - game code section

  .bank 0
  .org $8000

vblankwait:       ; First wait for vblank to make sure PPU is ready
  BIT $2002
  BPL vblankwait
  RTS

RESET:         ; jumps here when processor turns on or is reset
  SEI          ; set Interrupt Disable flag
  CLD          ; clear decimal mode flag
  LDX #$40     ; set registers X value to $40 ($ - hexadecimal)
  STX $4017    ; disable APU frame IRQ
  LDX #$FF
  TXS          ; Set up stack
  INX          ; increment X, now X = 0
  STX $2000    ; disable NMI
  STX $2001    ; disable rendering
  STX $4010    ; disable DMC IRQs

  JSR vblankwait

clrmem:
  LDA #$00
  STA $0000, x    ;  store A in $0000 + X
  STA $0100, x
  STA $0200, x
  STA $0400, x
  STA $0500, x
  STA $0600, x
  STA $0700, x
  LDA #$FE
  STA $0300, x
  INX
  BNE clrmem
   
  JSR vblankwait

LoadPalettes:
  LDA $2002    ; read PPU status to reset the high/low latch
  LDA #$3F
  STA $2006    ; write the high byte of $3F00 address
  LDA #$00
  STA $2006    ; write the low byte of $3F00 address
  LDX #$00
LoadPalettesLoop:
  LDA palette, x        ; load palette byte
  STA $2007             ; write to PPU
  INX                   ; set index to next byte
  CPX #$20            
  BNE LoadPalettesLoop  ; if x = $20, 32 bytes copied, all done


  LDA #%10000000    ; enable NMI, sprites from Pattern Table 0, background from Pattern Table 1
  STA $2000
  LDA #%00010000    ; enable sprites, enable background, no clipping on left side
  STA $2001
  LDA #$00          ; tell the ppu there is no background scrolling
  STA $2005

Start:
LoadSprites:
  LDX #$00              ; start at 0

LoadSpritesLoop:
  LDA sprites, x        ; load data from address (sprites + x)
  STA $0200, x          ; store into RAM address ($0200 + x)
  INX                   ; X = X + 1
  CPX #$40              ; Compare X to hex $40, decimal 64
  BNE LoadSpritesLoop   ; Branch to LoadSpritesLoop if compare was Not Equal to zero
                        ; if compare was equal to 64, continue down

PlayerStart:
  LDA $203
  STA playerXPos
  LDA $20B
  STA playerBulletX
  LDA $208
  STA playerBulletY
  LDA #BULLET_OFF
  STA playerBulletState

EnemyStart:
  LDA $210
  STA enemyY
  LDA $213
  STA enemyX
  LDA $20C
  STA enemyBulletY
  LDA $20F
  STA enemyBulletX
  LDA #BULLET_OFF
  STA enemyBulletState
  LDA #$00
  STA enemyTimeCounter
  STA enemyDirection
  LDA #ENEMY_COUNT
  STA enemyCount
  RTS
  

Forever:
  JMP Forever     ; jump back to Forever, infinite loop
  
NMI:
  LDA #$00
  STA $2003  ; set the low byte (00) of the RAM address
  LDA #$02
  STA $4014  ; set the high byte (02) of the RAM address, start the transfer

  JSR ReadPlayerController
  JSR MoveAll
  JSR DrawSprites

  RTI

MoveAll:
  JSR PlayerMove
  JSR EnemyMove
  JSR BulletMove
  RTS

PlayerMove:
PlayerMoveRight:
  LDA buttonsPressed
  AND #%00000001
  BEQ PlayerMoveRightDone

  LDA playerXPos        ; load player position
  CLC                   ; make sure the carry flag is clear
  ADC #$02              ; A = A + 2

  CMP #RIGHT_WALL
  BCS PlayerMoveRightDone
  STA playerXPos        ; save player position
PlayerMoveRightDone:

PlayerMoveLeft:
  LDA buttonsPressed
  AND #%00000010
  BEQ PlayerMoveLeftDone

  LDA playerXPos        ; load player position
  CLC                   ; make sure the carry flag is clear
  SBC #$01              ; A = A - 1

  CMP #LEFT_WALL
  BCC PlayerMoveLeftDone
  STA playerXPos        ; save player position
PlayerMoveLeftDone:

PlayerShot:
  LDA buttonsPressed
  AND #%10000000
  BEQ PlayerShotDone

  LDA playerBulletState
  EOR #BULLET_ON
  BEQ PlayerShotDone

  LDA playerXPos
  CLC
  ADC #$4
  STA playerBulletX
  LDA #$CF
  STA playerBulletY
  LDA #BULLET_ON
  STA playerBulletState
PlayerShotDone:
  RTS                   ; end of PlayerMove

EnemyMove:
  INC enemyTimeCounter

  LDA enemyTimeCounter
  CLC
  CMP #ENEMY_TIME
  BCC EnemyMoveDone

  LDA #$00
  STA enemyTimeCounter

  LDA enemyDirection
  AND #%01
  BEQ EnemyMoveRight

EnemyMoveLeft:
  LDA enemyX
  CLC
  SBC #ENEMY_HOR_STEP
  CMP #LEFT_WALL
  BCC EnemyMoveDown
  STA enemyX
  JMP EnemyShot

EnemyMoveRight:
  LDA enemyX
  CLC
  ADC #ENEMY_HOR_STEP
  ADC #ENEMY_RIGHT_EDGE
  CMP #RIGHT_WALL
  BCS EnemyMoveDown
  CLC
  SBC #ENEMY_RIGHT_EDGE
  STA enemyX
  JMP EnemyShot

EnemyMoveDown:
  LDA enemyY
  CLC
  ADC #ENEMY_VERT_STEP
  STA enemyY

  LDA enemyDirection
  EOR #%01
  STA enemyDirection

EnemyShot:
  LDA enemyBulletState
  EOR #BULLET_ON
  BEQ EnemyMove
  JSR EnemyShotSub

EnemyMoveDone:
  RTS

EnemyShotSub:
  LDA #$FF
  TAX
EnemyShotLoop:
  TXA
  CLC
  ADC #$04
  CMP #$40
  BCS EnemyShotDone
  TAX
  LDA $0210, x
  CLC
  SBC #$10
  CMP playerXPos           
  BCS EnemyShotLoop       ; if enemyX - 10h > playerXPos
  CLC
  ADC #$20
  CMP playerXPos           
  BCC EnemyShotLoop   ; if enemyX + 10h < playerXPos
  LDA $0210, x
  CMP #$FF
  BEQ EnemyShotLoop
  STA enemyBulletX
  LDA enemyY
  STA enemyBulletY
  LDA #BULLET_ON
  STA enemyBulletState
EnemyShotDone:
  RTS

BulletMove:
  ; player bullet move
  LDA playerBulletState
  AND #BULLET_ON
  BEQ PlayerBulletEnemyCollision     ; PlayerBulletMoveDone too far...

  LDA playerBulletY
  CLC
  SBC #BULLET_SPEED
  STA playerBulletY

  LDX #%00

  CMP enemyBulletY            
  BCS PlayerBulletEnemyCollision   ; if playerBulletY < enemyBulletY

  LDX #%01                      ; bullets collide

  LDA playerBulletX
  CLC
  SBC #$04
  CMP enemyBulletX            
  BCS PlayerBulletEnemyCollision   ; if playerBulletX - 4h < enemyBulletX
  CLC
  ADC #$08
  CMP enemyBulletX            
  BCC PlayerBulletEnemyCollision        ; if playerBulletX + 4h > enemyBulletX
  JMP PlayerSetBulletOff

PlayerBulletEnemyCollision:
;  LDA enemyX
;  CLC
;  SBC #$04
;  CMP playerBulletX
;  BCS PlayerBulletWallCompare     ; if playerBulletX < enemyX
;  CLC
;  ADC #ENEMY_RIGHT_EDGE+$04
;  CMP playerBulletX
;  BCC PlayerBulletWallCompare     ; if playerBulletX > enemyX + A8h
;  LDA enemyY
;  CLC
;  ADC #ENEMY_VERT_GAP+$0A
;  CMP playerBulletY
;  BCC PlayerBulletWallCompare     ; if playerBulletY > enemyY + 18h

  LDA #$FC
  TAX
  TAY
CheckEnemy:
  TYA
  CLC
  ADC #$04
  CMP #$40
  BCS PlayerBulletWallCompare
  TAY
  TAX
  LDA $0210, x
  CLC
  ADC #$08
  CMP playerBulletY
  BCC CheckEnemy              ; if playerBulletY > enemyY + 08h
  INX
  INX
  INX
  LDA $0210, x
  CLC
  SBC #$04
  CMP playerBulletX
  BCS CheckEnemy              ; if playerBulletX < enemyX
  CLC
  ADC #$0A
  CMP playerBulletX
  BCC CheckEnemy              ; if playerBulletX > enemyX + A8h
  LDA #$FF
  CMP $0210, x
  BEQ CheckEnemy
  STA $0210, x
  LDX enemyCount
  DEX
  TXA
  CMP #$00
  BEQ PlayerWon
  STX enemyCount
  JMP PlayerSetBulletOff

PlayerWon:
  JSR Restart

PlayerBulletWallCompare:
  LDX #%00                      ; bullets dont collide
  LDA playerBulletY
  CMP #TOP_WALL
  BCS PlayerBulletMoveDone
  
PlayerSetBulletOff:
  LDA #BULLET_OFF
  STA playerBulletState
  LDA #$FF
  STA playerBulletX
  LDA #$FF
  STA playerBulletY

PlayerBulletMoveDone:
  ; enemy bullet move
  LDA enemyBulletState
  AND #BULLET_ON
  BEQ EnemyBulletMoveDone

  TXA
  EOR #%01
  BEQ EnemyBulletSetOff     ; if bullets collide

  LDA enemyBulletY
  CLC
  ADC #BULLET_SPEED
  STA enemyBulletY

  CMP #$D7         
  BCC EnemyBulletWallCompare   ; if enemyBulletY < playerYPos
  LDA enemyBulletX
  CLC
  SBC #$0C
  CMP playerXPos           
  BCS EnemyBulletWallCompare       ; if enemyBulletX - 0Ch > playerXPos
  CLC
  ADC #$11
  CMP playerXPos           
  BCC EnemyBulletWallCompare   ; if enemyBulletX + 4h < playerXPos
  
  JSR Restart

EnemyBulletWallCompare:
  LDA enemyBulletY
  CMP #BOTTOM_WALL
  BCC EnemyBulletMoveDone

EnemyBulletSetOff:
  LDA #BULLET_OFF
  STA enemyBulletState
  LDA #$00
  STA enemyBulletX
  LDA #$00
  STA enemyBulletY

EnemyBulletMoveDone:
BulletMoveDone:
  RTS

DrawSprites:
  ; draw player
  LDA playerXPos
  STA $0203
  CLC
  ADC #$08
  STA $0207
  ; draw bullet
  LDA playerBulletX
  STA $020B
  LDA playerBulletY
  STA $0208

  ; draw enemy
  CLC

  LDA enemyX
  TAX
  LDA $0213
  CMP #$FF
  BEQ Next1_0           ; if not alive
  TXA
  STA $0213

Next1_0:
  LDA $022B
  CMP #$FF
  BEQ Next0_1 
  TXA
  STA $022B

Next0_1:
  TXA
  ADC #ENEMY_HOR_GAP
  TAX
  LDA $0217
  CMP #$FF
  BEQ Next1_1
  TXA
  STA $0217
Next1_1:
  LDA $022F
  CMP #$FF
  BEQ Next0_2
  TXA
  STA $022F

Next0_2:
  TXA
  ADC #ENEMY_HOR_GAP
  TAX
  LDA $021B
  CMP #$FF
  BEQ Next1_2
  TXA
  STA $021B
Next1_2:
  LDA $0233
  CMP #$FF
  BEQ Next0_3
  TXA
  STA $0233

Next0_3:
  TXA
  ADC #ENEMY_HOR_GAP
  TAX
  LDA $021F
  CMP #$FF
  BEQ Next1_3
  TXA
  STA $021F
Next1_3:
  LDA $0237
  CMP #$FF
  BEQ Next0_4
  TXA
  STA $0237

Next0_4:
  TXA
  ADC #ENEMY_HOR_GAP
  TAX
  LDA $0223
  CMP #$FF
  BEQ Next1_4
  TXA
  STA $0223
Next1_4:
  LDA $023B
  CMP #$FF
  BEQ Next0_5
  TXA
  STA $023B

Next0_5:
  TXA
  ADC #ENEMY_HOR_GAP
  TAX
  LDA $0227
  CMP #$FF
  BEQ Next1_5
  TXA
  STA $0227
Next1_5:
  LDA $023F
  CMP #$FF
  BEQ NextY
  TXA
  STA $023F

NextY:
  LDA enemyY
  STA $0210
  STA $0214
  STA $0218
  STA $021C
  STA $0220
  STA $0224

  CLC
  ADC #ENEMY_VERT_GAP
  STA $0228
  STA $022C
  STA $0230
  STA $0234
  STA $0238
  STA $023C

Next:
  LDA enemyBulletX
  STA $020F
  LDA enemyBulletY
  STA $020C

  RTS

Restart:
  JSR Start
  RTS

ReadPlayerController:
  LDA #$01
  STA $4016
  LDA #$00
  STA $4016
  LDX #$08
ReadPlayerControllerLoop:
  LDA $4016
  LSR A                 ; bit0 -> Carry     bit:       7     6     5     4     3     2     1     0
  ROL buttonsPressed     ; bit0 <- Carry    button:    A     B   select start  up   down  left right
  DEX
  BNE ReadPlayerControllerLoop
  RTS



; bank 1 - vectors section
  
  .bank 1
  .org $E000

palette:
  .db $0F,$31,$32,$33,$0F,$35,$36,$37,$0F,$39,$3A,$3B,$0F,$3D,$3E,$0F
  .db $0F,$1C,$15,$14,$0F,$02,$38,$3C,$0F,$1C,$15,$14,$0F,$02,$38,$3C

sprites:
     ;screen resolution 256 : 240 pixels
     ;vert tile attr horiz                        memory index
  .db $D7, $0, $00, $7C   ;player left sprite    200
  .db $D7, $1, $00, $84   ;player right sprite   204
  .db $FF, $2, $00, $FF   ;player bullet         208

  .db $00, $2, $00, $00   ;enemyBullet           20C

  .db $08, $3, $00, $20   ;enemy0.0              210
  .db $08, $3, $00, $40   ;enemy0.1              214
  .db $08, $3, $00, $60   ;enemy0.2              218
  .db $08, $3, $00, $80   ;enemy0.3              21C
  .db $08, $3, $00, $A0   ;enemy0.4              220
  .db $08, $3, $00, $C0   ;enemy0.5              224

  .db $18, $3, $00, $20   ;enemy1.0              228
  .db $18, $3, $00, $40   ;enemy1.1              22C
  .db $18, $3, $00, $60   ;enemy1.2              230
  .db $18, $3, $00, $80   ;enemy1.3              234
  .db $18, $3, $00, $A0   ;enemy1.4              238
  .db $18, $3, $00, $C0   ;enemy1.5              23C



  .org $FFFA     ;first of the three vectors starts here

  .dw NMI        ;when an NMI happens (once per frame if enabled) the 
                   ;processor will jump to the label NMI:
  .dw RESET      ;when the processor first turns on or is reset, it will jump
                   ;to the label RESET:
  .dw 0          ;external interrupt IRQ is not used in this tutorial
  
  
; bank 2 - data section
  
  .bank 2
  .org $0000
  .incbin "SI.chr"
