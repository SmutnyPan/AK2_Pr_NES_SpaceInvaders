  ; header - defines number and size of sections
  .inesprg 1   ; 1x 16KB game code
  .ineschr 1   ; 1x  8KB graphics data
  .inesmap 0   ; mapper 0 = NROM, no bank swapping
  .inesmir 1   ; background mirroring
  
; constants
STATE_TITLE     = $00  ; displaying title screen
STATE_PLAYING   = $01  ; move player/enemies/projectiles, check for collisions
STATE_GAMEOVER  = $02  ; displaying game over screen

RIGHT_WALL      = $E8
TOP_WALL        = $04
BOTTOM_WALL     = $E0
LEFT_WALL       = $08

BULLET_SPEED    = $03
BULLET_ON       = %01
BULLET_OFF      = %00
ENEMIES_TIME    = $40
ENEMIES_HOR_STEP = $08
ENEMIES_VERT_STEP= $08
ENEMIES_HOR_GAP = $20
ENEMIES_VERT_GAP = $10
ENEMIES_RIGHT_EDGE = $5 * ENEMIES_HOR_GAP - $08

; variables
  .rsset $0000      ;start variables at $0000

gameState .rs 1     ; .rs 1 - reserve 1 byte of space

playerXPos .rs 1
buttonsPressed .rs 1
playerBulletX .rs 1
playerBulletY .rs 1
playerBulletState .rs 1

enemiesBulletX .rs 1
enemiesBulletY .rs 1
enemiesBulletState .rs 1
enemiesY .rs 1
enemiesX .rs 1
enemiesTimeCounter .rs 1
enemiesDirection .rs 1


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

LoadSprites:
  LDX #$00              ; start at 0

LoadSpritesLoop:
  LDA sprites, x        ; load data from address (sprites + x)
  STA $0200, x          ; store into RAM address ($0200 + x)
  INX                   ; X = X + 1
  CPX #$40              ; Compare X to hex $40, decimal 64
  BNE LoadSpritesLoop   ; Branch to LoadSpritesLoop if compare was Not Equal to zero
                        ; if compare was equal to 64, continue down

PlayerStartPosition:
  LDA $203
  STA playerXPos
  LDA $20B
  STA playerBulletX
  LDA $208
  STA playerBulletY
  LDA #BULLET_OFF
  STA playerBulletState

EnemiesStart:
  LDA $210
  STA enemiesY
  LDA $213
  STA enemiesX
  LDA $20C
  STA enemiesBulletY
  LDA $20F
  STA enemiesBulletX
  LDA #BULLET_OFF
  STA enemiesBulletState
  LDA #$00
  STA enemiesTimeCounter
  STA enemiesDirection
  

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
  INC enemiesTimeCounter

  LDA enemiesTimeCounter
  CLC
  CMP #ENEMIES_TIME
  BCC EnemyMoveDone

  LDA #$00
  STA enemiesTimeCounter

  LDA enemiesDirection
  AND #%01
  BEQ EnemyMoveRight

EnemyMoveLeft:
  LDA enemiesX
  CLC
  SBC #ENEMIES_HOR_STEP
  CMP #LEFT_WALL
  BCC EnemyMoveDown
  STA enemiesX
  JMP EnemyShot

EnemyMoveRight:
  LDA enemiesX
  CLC
  ADC #ENEMIES_HOR_STEP
  ADC #ENEMIES_RIGHT_EDGE
  CMP #RIGHT_WALL
  BCS EnemyMoveDown
  CLC
  SBC #ENEMIES_RIGHT_EDGE
  STA enemiesX
  JMP EnemyShot

EnemyMoveDown:
  LDA enemiesY
  CLC
  ADC #ENEMIES_VERT_STEP
  STA enemiesY

  LDA enemiesDirection
  EOR #%01
  STA enemiesDirection

EnemyShot:
  LDA enemiesBulletState
  EOR #BULLET_ON
  BEQ EnemyShotDone

  LDA playerXPos
  CLC
  ADC #$4
  STA enemiesBulletX
  LDA enemiesY
  STA enemiesBulletY
  LDA #BULLET_ON
  STA enemiesBulletState
EnemyShotDone: 
EnemyMoveDone:
  RTS

BulletMove:
  ; player bullet move
  LDA playerBulletState
  AND #BULLET_ON
  BEQ PlayerBulletWallCompare

  LDA playerBulletY
  CLC
  SBC #BULLET_SPEED
  STA playerBulletY

  LDX #%00

  CMP enemiesBulletY            
  BCS PlayerBulletEnemyCollision   ; if playerBulletY < enemiesBulletY

  LDX #%01                      ; bullets collide

  LDA playerBulletX
  CLC
  SBC #$04
  CMP enemiesBulletX            
  BCS PlayerBulletEnemyCollision   ; if playerBulletX - 4h < enemiesBulletX
  CLC
  ADC #$08
  CMP enemiesBulletX            
  BCS PlayerSetBulletOff        ; if playerBulletX + 4h > enemiesBulletX

PlayerBulletEnemyCollision:
  LDX #%00                      ; bullets dont collide
  LDA enemiesX
  CMP playerBulletX
  BCS PlayerBulletWallCompare     ; if playerBulletX < enemiesX
  CLC
  ADC #ENEMIES_RIGHT_EDGE
  CMP playerBulletX
  BCC PlayerBulletWallCompare     ; if playerBulletX > enemiesX + A8h
  LDA enemiesY
  CLC
  ADC #$18
  CMP playerBulletY
  BCC PlayerBulletWallCompare     ; if playerBulletY > enemiesY + 18h
  
  ; vector translation
  ; (playerBulletX, playerBulletY) - (enemiesX, enemiesY)
  LDA playerBulletX
  PHA                             ; push playerBulletX
  CLC
  SBC enemiesX
  STA playerBulletX
  LDA playerBulletY
  PHA                             ; push playerBulletY
  CLC
  SBC enemiesY
  STA playerBulletY

  LDY #%00

div_vert:
  CLC
  SBC #ENEMIES_VERT_STEP
  INY
  BCC div_vert
  TAY
  PHA                             ; push floor(playerBulletY/ENEMIES_VERT_STEP)

  LDY #%00
  LDA enemiesBulletX
div_hor:
  CLC
  SBC #ENEMIES_HOR_STEP
  INY
  BCC div_hor
  TAY
  PHA                             ; push floor(playerBulletX/ENEMIES_HOR_STEP)

  PLA                             ; pull floor(playerBulletX/ENEMIES_HOR_STEP)
  PLA                             ; pull floor(playerBulletY/ENEMIES_VERT_STEP)
 
  PLA                             ; pull playerBulletY
  STA playerBulletY
  PLA                             ; pull playerBulletX
  STA playerBulletX

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
  LDA enemiesBulletState
  AND #BULLET_ON
  BEQ EnemyBulletMoveDone

  TXA
  EOR #%01
  BEQ EnemyBulletSetOff     ; if bullets collide

  LDA enemiesBulletY
  CLC
  ADC #BULLET_SPEED
  STA enemiesBulletY

  CMP #BOTTOM_WALL
  BCC EnemyBulletMoveDone
  
EnemyBulletSetOff:
  LDA #BULLET_OFF
  STA enemiesBulletState
  LDA #$00
  STA enemiesBulletX
  LDA #$00
  STA enemiesBulletY

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

  ; draw enemies
  CLC

  LDA enemiesX
  STA $0213
  STA $022B

  ADC #ENEMIES_HOR_GAP
  STA $0217
  STA $022F

  ADC #ENEMIES_HOR_GAP
  STA $021B
  STA $0233

  ADC #ENEMIES_HOR_GAP
  STA $021F
  STA $0237

  ADC #ENEMIES_HOR_GAP
  STA $0223
  STA $023B

  ADC #ENEMIES_HOR_GAP
  STA $0227
  STA $023F

  LDA enemiesY
  STA $0210
  STA $0214
  STA $0218
  STA $021C
  STA $0220
  STA $0224

  CLC
  ADC #ENEMIES_VERT_GAP
  STA $0228
  STA $022C
  STA $0230
  STA $0234
  STA $0238
  STA $023C

  LDA enemiesBulletX
  STA $020F
  LDA enemiesBulletY
  STA $020C

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

  .db $08, $3, $00, $20   ;enemy1.1              210
  .db $08, $3, $00, $40   ;enemy1.2              214
  .db $08, $3, $00, $60   ;enemy1.3              218
  .db $08, $3, $00, $80   ;enemy1.4              21C
  .db $08, $3, $00, $A0   ;enemy1.5              220
  .db $08, $3, $00, $C0   ;enemy1.6              224

  .db $18, $3, $00, $20   ;enemy2.1              228
  .db $18, $3, $00, $40   ;enemy2.2              22C
  .db $18, $3, $00, $60   ;enemy2.3              230
  .db $18, $3, $00, $80   ;enemy2.4              234
  .db $18, $3, $00, $A0   ;enemy2.5              238
  .db $18, $3, $00, $C0   ;enemy2.6              23C



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
