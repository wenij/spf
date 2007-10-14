\ $Id$
\ ����� � ���������� ����� �� ������

MODULE: bot_plugin_httpreport

: report-url ( nu tt -- s ) " http://fforum.winglion.ru/irc_out.php?tt={n}&nu={n}" ;

EXPORT

() VALUE names-list

DEFINITIONS

TIME&DATE DateTime>Num VALUE last-message-stamp

: break-string-to-list ( a u -- list ) %[ START{ split-patch DUP ONTRUE 2DUP " {s}" %s }EMERGE ]% ;

: MEMORIZE-NAMES ( -- )
   message-text byWhites break-string-to-list names-list concat-list TO names-list ;

: sHTTP-REQUEST-DROP ( s -- )
\   CR ." Requesting : " DUP STR@ TYPE
   30 CURLOPT_TIMEOUT CURLOPT!
   DUP STR@ GET-FILE STRFREE
       STRFREE ;

EXPORT

VECT GOT-NAMES

DEFINITIONS

: REPORT-NAMES1
   names-list length
   last-message-stamp TIME&DATE DateTime>Num - ABS
   report-url sHTTP-REQUEST-DROP ;

: REPORT-NAMES
    ['] REPORT-NAMES1 CATCH IF S" REPORT-NAMES ERROR" ECHO BYE THEN
    names-list FREE-LIST
    () TO names-list ;

:NONAME { pause }
  BEGIN
   pause PAUSE
   current-channel " NAMES {s}" SCMD
  AGAIN
; TASK: reporter

EXPORT

\ -----------------------------------------------------------------------

MODULE: VOC-IRC-COMMAND

: PRIVMSG
   PRIVMSG
   TIME&DATE DateTime>Num TO last-message-stamp ;
: NAMREPLY MEMORIZE-NAMES ;
: ENDOFNAMES GOT-NAMES REPORT-NAMES ;
: 353 NAMREPLY ;
: 366 ENDOFNAMES ;

;MODULE

\ -----------------------------------------------------------------------

..: AT-CONNECT 4 minutes reporter START DROP ;..

..: AT-CLOSE -1 -1 report-url sHTTP-REQUEST-DROP ;..

;MODULE

$Revision$ " -- HTTP-report plugin {s} loaded." STYPE CR

\ -----------------------------------------------------------------------

\EOF
