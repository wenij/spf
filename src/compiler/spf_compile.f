( ���������� ����� � ����� � �������.
  ��-����������� �����������.
  Copyright [C] 1992-1999 A.Cherezov ac@forth.org
  �������������� �� 16-���������� � 32-��������� ��� - 1995-96��
  ������� - �������� 1999, ���� 2000
)

HEX

: HERE ( -- addr ) \ 94
\ addr - ��������� ������������ ������.
  DP @ 
  DUP TO :-SET
  DUP TO J-SET
;

: _COMPILE,  \ 94 CORE EXT
\ �������������: ��������� �� ����������.
\ ����������: ( xt -- )
\ �������� ��������� ���������� �����������, �������������� xt, �
\ ��������� ���������� �������� �����������.
  SetOP
  0E8 C,              \ �������� ������� CALL
  DP @ CELL+ - ,
  DP @ TO LAST-HERE
;

: COMPILE,  \ 94 CORE EXT
\ �������������: ��������� �� ����������.
\ ����������: ( xt -- )
\ �������� ��������� ���������� �����������, �������������� xt, �
\ ��������� ���������� �������� �����������.
    CON>LIT 
    IF  INLINE?
      IF     INLINE,
      ELSE   _COMPILE,
      THEN
    THEN
;

: BRANCH, ( ADDR -> ) \ �������������� ���������� ADDR JMP
  ?SET SetOP SetJP E9 C,
  DUP IF DP @ CELL+ - THEN ,    DP @ TO LAST-HERE
;

: RET, ( -> ) \ �������������� ���������� RET
  ?SET SetOP 0xC3 C, OPT OPT_CLOSE 
;

: LIT, ( W -> )
  ['] DUP  INLINE,
  OPT_INIT
  SetOP 0B8 C,  , OPT  \ MOV EAX, #
  OPT_CLOSE
;

: DLIT, ( D -> )
  SWAP LIT, LIT,
;

: RLIT, ( u -- )
\ �������������� ��������� ���������:
\ �������� �� ���� ��������� ������� u
   68 C, ,  \ push dword #
;

: ?BRANCH, ( ADDR -> ) \ �������������� ���������� ADDR ?BRANCH
  ?SET
  084 TO J_COD
  ['] DROP
  0xC00B W,    \ OR EAX, EAX
  OPT?  IF -2 ALLOT   \ ���������� OR EAX, EAX
           OPT_INIT DP @ TO LAST-HERE
           ?BR-OPT
           DP @ TO LAST-HERE
       THEN
  INLINE, SetJP  SetOP
  J_COD    \  JX ��� 0x0F
  0x0F     \  ����� �� JX
  C, C,
  DUP IF DP @ CELL+ - THEN , DP @ TO LAST-HERE
;

DECIMAL

: ", ( A -> ) \ ���������� ������ �� ���������, �������� ������� A
  DP @ OVER C@ 1+ DUP ALLOT QCMOVE
;

: S", ( addr u -- ) \ ���������� ������, �������� addr u, � ���� ������ �� ���������
  DUP C, DP @ SWAP DUP ALLOT QCMOVE
;

\ orig - a, 1 (short) ��� a, 2 (near)
\ dest - a, 3

: >MARK ( -> A )
  DP @ DUP TO :-SET 4 - 
;

: <MARK ( -> A )
  DP @ DUP TO :-SET
;

: >ORESOLVE1 ( A -> )
  DUP
    DP @ DUP TO :-SET
    OVER - 4 -
    SWAP !
  RESOLVE_OPT
;

: >ORESOLVE ( A, N -- )
  DUP 1 = IF   DROP >ORESOLVE1
          ELSE 2 <> IF -2007 THROW THEN \ ABORT" Conditionals not paired"
               >ORESOLVE1
          THEN
;

: >RESOLVE1 ( A -> )
  HERE OVER - 4 -
  SWAP !
;

: >RESOLVE ( A, N -- )
  DUP 1 = IF   DROP >RESOLVE1
          ELSE 2 <> IF -2007 THROW THEN \ ABORT" Conditionals not paired"
               >RESOLVE1
          THEN
;


\ ����� ��� ������������ (ALOGN*) � SPF �� ������������.
\ ��������� ��� ������������ ��������� ANS 94.

USER ALIGN-BYTES

: ALIGNED ( addr -- a-addr ) \ 94
\ a-addr - ������ ����������� �����, ������� ��� ������ addr.
  ALIGN-BYTES @ 2DUP
  MOD DUP IF - + ELSE 2DROP THEN
;
: ALIGN ( -- ) \ 94
\ ���� ��������� ������������ ������ �� �������� -
\ ��������� ���.
  DP @ ALIGNED DP @ - ALLOT
;

: ALIGN-NOP ( n -- )
\ ��������� HERE �� n � ��������� NOP
  HERE DUP ROT 2DUP
  MOD DUP IF - + ELSE 2DROP THEN
  OVER - DUP ALLOT 0x90 FILL
;
