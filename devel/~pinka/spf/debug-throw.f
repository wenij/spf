\ 26.03.2007

\ ����������, ����� ���������, � ����� ����� ���������� ����������:

: THROW_ORIG THROW ;
: THROW
  DUP 0=      IF THROW EXIT THEN
  DUP 10054 = IF THROW EXIT THEN
  DUP 10053 = IF THROW EXIT THEN

  \ R@ OVER DUMP-EXCEPTION-HEADER
  CR ." THREAD-ID: " THREAD-ID . ." STACK: " OK
  RP@
  BEGIN DUP R0 @ U> 0= WHILE
    STACK-ADDR.
    CELL+
  REPEAT
  DROP

  THROW
;
