\ REQUIRE ���� ~profit/lib/stacks.f
REQUIRE /TEST ~profit/lib/testing.f
REQUIRE ON lib/ext/onoff.f
REQUIRE FOR ~profit/lib/for-next.f
REQUIRE ������ ~profit/lib/collectors.f

\ �������, ����������� ����� ��������. ����� "���������" ������
\ ���� ��������� ����� �������� � 256-� ��������, ��� ������ �����
\ -- ������� �� ���� � ������� �������. �������� ����� ��������
\ � ���� � ������������ �������� � ������ ���������. ��� �����
\ �������� � ��������� ����� ���� ��������� �����-������ �������� ("��-�����:")
\ ����� ��������� �������, ����� ����������-������, ��������� �����-������ ���
\ ��������� ���������, � ������ ����� ��������� ������ "-��������-����������" �
\ ���-��� �������� �� ����� (��. ����� �������-������� � �������).
\ �������� ��� ���������� �������� ������ ����������������.

\ ����� ����, ������������ ����� ����� "�������" ��������� ������ ����
\ ���������, �� � ������������ ���-� �������. ��� ������ ������������
\ ��� ������ CASE.

MODULE: chartable
0 VALUE �������-���������
0 VALUE �������-���������

VARIABLE /������
EXPORT

: ������ ( -- c ) /������ @ ; \ ����� ������� ������

' NOOP CONSTANT ��������

DEFINITIONS

: �����-������� ( n -- addr ) CELLS �������-��������� + ; \ n -- ����� �������, addr -- �����. ��� ������ � ���������
: -�-������ ( xt c -- ) �����-������� ! ;
: ����������-�������� ( xt start end  -- ) 1+ SWAP DO DUP I -�-������ LOOP DROP ;
: ���-������� ( xt -- ) 0 255 ����������-�������� ;
: ��������-���-������� ( -- )  �������� ���-������� ;

0 VALUE ���������-�������
0 VALUE �������������-�������
: :n ( "name" -- xt ) ���������-������� TO �������������-�������  :NONAME  DUP TO ���������-������� ;

EXPORT

: ������:  ( "z" -- ) :n CHAR -�-������ ;
: ���������: ( n -- ) :n SWAP -�-������ ;
: asc: ( n -- ) ���������: ;

: ���: ( -- ) :n   ���-������� ;
: ��������: ( a b -- ) :n -ROT ����������-�������� ;

: ������: ( -- ) :n BL -�-������ ;
: �������-������: ( -- ) �������� 13 -�-������  :n 10 -�-������ ;
: �����������: ( -- ) :n 0 32 ����������-�������� ;
: �����: ( -- ) [CHAR] 0 [CHAR] 9 ��������: ;

: ���������-�����: ( -- ) [CHAR] a [CHAR] z ��������:
���������-������� [CHAR] A [CHAR] Z ����������-�������� ;

: all-asc: ( addr u -- ) :n -ROT OVER + SWAP DO DUP I C@ -�-������ LOOP DROP ;

: �������: ( "ABCZ" -- ) :n ParseWord all-asc: ;

: ����-����� ( -- ) �������������-������� COMPILE, ; IMMEDIATE
: ���� ( -- ) LATEST COUNT SLIT, ; IMMEDIATE

: ������� ( �����-������� "���" -- )
CREATE
DUP 1+ , \ ���-�� ������� ���� ����
HERE TO �������-���������
0 DO �������� , LOOP
�������� , \ �������� ��-���������, ��� ������� ������ ������� ��������� ���-�� ���������
DOES> DUP @ ROT MIN 1+ CELLS + @ EXECUTE ;

: ��������� ( -- )
CREATE
�������� , \ �������� �� �����
�������� , \ ������� �� ��������� ���������� ������
HERE TO �������-���������
255 FOR �������� , NEXT
�������� , \ �������� ��-���������, ��� ������� ������ ������� ��������� ���-�� ���������
DOES> DUP @ EXECUTE  2 CELLS + TO �������-��������� ;


: ��-�����: ( -- ) :n -2 -�-������ ;
: ������-���������: ( -- ) :n -1 -�-������ ;

VECT ����������-�������-�������

: ���-���-������� ( -- xt ) ������ 255 1 + MIN �����-������� @ ;
: ���������-������   ����������-�������-�������  ���-���-������� >R ; \ EXECUTE

: ���������-����-��� ( c -- ) /������ ! ���������-������ ;
: ���������-��������� -1  �����-������� @ EXECUTE ;

: �����-��-������� ( "tbl ) ' >BODY �������-��������� 2 CELLS - 255 1 + 2 + CELLS MOVE ;

5 ������� �����-����� ( -- c )
���: ABORT" �������� ������ �������!" ;
1 ���������: C@ ;
2 ���������: W@ ;
3 ���������: @ 0xFFFFFF AND ;
4 ���������: @ ;

VARIABLE ������-�-������
: ������ ( -- addr ) ������-�-������ @ ;
: ����������-����� ( -- ) ������-������� ������-�-������ +! ;
: ����-����� ( -- c ) ������ ������-������� �����-�����  ����������-����� ;
: �������-����� ( -- ) ������-������� NEGATE ������-�-������ +! ;
: ���������-������ ( ����� -- ) ������-�-������ ! ;

:NONAME CR ������ EMIT ." |" ������ . ; CONSTANT �������-��������
: ��������-�������-��������  �������-�������� TO ����������-�������-������� ;
: ���������-�������-��������  NOOP TO ����������-�������-������� ;

VARIABLE ����������-���������
: ������������-��-������� ( -- ) ����������-��������� ON  BEGIN ����������-��������� @ WHILE ����-����� ���������-����-��� REPEAT ���������-��������� ;

( 
100 CELLS ���� ��������� \ � ����� �� ��?
: ���������-���������  ������ �������-��������� ��������� 2��������  �����-���������� 2@ ��������� 2��������  �������-��������� ������-������� ��������� 2�������� ;
: �������-���������  ��������� �����? IF EXIT THEN  ��������� 2����� TO ������-������� TO �������-���������  ��������� 2����� �����-���������� 2!  ��������� 2�����  TO �������-��������� ���������-������ ;
)

: ����������-�������  ( -- ) ������ 1- TO �������-��������� ;
: ��������� ( end -- )
TO �������-���������          BEGIN
������ �������-��������� U<   WHILE
����-����� ���������-����-��� REPEAT
���������-��������� ;

: -��������-���������� ( n -- ) ?DUP IF ������ + ��������� THEN ;
\ ������� ����� �������� ���������� ������� �� �������� 

;MODULE

/TEST
9 ������� 1-2-3 \ ��� ��������� 
1 ���������: ." I" ; 
2 ���������: ." II" ; 
3 ���������: ." III" ; 
4 9 ��������: ." IV-IX" ; 

$> 5 1-2-3
\ �����: IV-IX

256 ������� c \ ������� ������������ �������� 
���: ." unknown" ; 
�����������: ." delimiter, but not space" ; 
������: ." space" ; 
�������-������: ." carriage return" ; 
CHAR 0 CHAR 9 ��������: ." digit" ; 

CHAR a CHAR z ��������: ." letter" ; 
CHAR A CHAR Z ��������: ����-����� ; 
CHAR � CHAR � ��������: ����-����� ; 
CHAR � CHAR � ��������: ����-����� ; 

$> .( press a key) KEY CR c

VARIABLE ������� 

��������� ��-������� 
��������� ���������� 
��������� �������� 

��-�������
��-�����: CR ." |" ;
\ ���: ;  \ �������������, ��-��������� ��� � ���� 
������: | ��-������� ;
������: +  ���������� ;
������: -  �������� ; 

����������
�����-��-������� ��-������� \ �������� ����������� |+-
��-�����: CR ." +" ;
CHAR 0 CHAR 9 ��������:  ������� 1+! ; 

��������
�����-��-������� ��-������� \ �������� ����������� |+-
��-�����: CR ." -" ;
CHAR 0 CHAR 9 ��������:  -1 ������� +!  ; 

: �������-������� ( a u � ) 
������� 0!
1 TO ������-������� SWAP ���������-������ 
��-������� 
-��������-���������� ; 
��������-�������-��������
$> S" 12+345-67|90" �������-�������  CR ������� @ .
\ �����: 1