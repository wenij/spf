0x00000002 CONSTANT MAPI_NEW_SESSION          \ Don't use shared session     */
0x00000010 CONSTANT MAPI_EXPLICIT_PROFILE     \ Don't use default profile		*/
0x00000020 CONSTANT MAPI_EXTENDED             \ Extended MAPI Logon				*/
0x00000040 CONSTANT MAPI_USE_DEFAULT          \ Use default profile in logon */
0x00001000 CONSTANT MAPI_FORCE_DOWNLOAD       \ Get new mail before return		*/
0x00002000 CONSTANT MAPI_SERVICE_UI_ALWAYS    \ Do logon UI in all providers		*/

0x00000001 CONSTANT MAPI_MODIFY
0x00000010 CONSTANT MAPI_BEST_ACCESS

0x00000001 CONSTANT MDB_NO_DIALOG
0x00000004 CONSTANT MDB_WRITE

        30 CONSTANT PT_STRING8	\ Null terminated 8-bit character string

0x0FFF0102 CONSTANT PR_ENTRYID
0x3006001E CONSTANT PR_PROVIDER_DISPLAY \ MAPILab Group Folders ��� ������ �����
0x3001001E CONSTANT PR_DISPLAY_NAME \ RAINBOW:������ �����
0x30090003 CONSTANT PR_RESOURCE_FLAGS \ 860 ��� 2

0x00000002 CONSTANT MODRECIP_ADD

\ 0x00000040 CONSTANT MSGFLAG_ASSOCIATED
\ 0x00000040 CONSTANT MAPI_ASSOCIATED
1 CONSTANT MSGFLAG_READ
8 CONSTANT MSGFLAG_UNSENT

 0xE1D001E CONSTANT PR_NORMALIZED_SUBJECT
 0x037001E CONSTANT PR_SUBJECT
0x003D001E CONSTANT PR_SUBJECT_PREFIX

 0x042001E CONSTANT PR_SENT_REPRESENTING_NAME
0x0C1A001E CONSTANT PR_SENDER_NAME

0x0064001E CONSTANT PR_PR_SENT_REPRESENTING_ADDRTYPE \ SMTP
0x0C1E001E CONSTANT PR_SENDER_ADDRTYPE

0x0065001E CONSTANT PR_SENT_REPRESENTING_EMAIL_ADDRESS
0x0C1F001E CONSTANT PR_SENDER_EMAIL_ADDRESS

0x00410102 CONSTANT PR_SENT_REPRESENTING_ENTRYID
0x0C190102 CONSTANT PR_SENDER_ENTRYID

0x1000001E CONSTANT PR_BODY
0x1035001E CONSTANT PR_INTERNET_MESSAGE_ID
0x1042001E CONSTANT PR_IN_REPLY_TO_ID
0x1037001E CONSTANT PR_INTERNET_ORGANIZATION
0x1039001E CONSTANT PR_INTERNET_REFERENCES

0x0C150003 CONSTANT PR_RECIPIENT_TYPE
0x3003001E CONSTANT PR_EMAIL_ADDRESS
0x3002001E CONSTANT PR_ADDRTYPE
0x001A001E CONSTANT PR_MESSAGE_CLASS

0x0E02001E CONSTANT PR_DISPLAY_BCC
0x0E03001E CONSTANT PR_DISPLAY_CC
0x0E04001E CONSTANT PR_DISPLAY_TO

0x0E060040 CONSTANT PR_MESSAGE_DELIVERY_TIME
0x0E070003 CONSTANT PR_MESSAGE_FLAGS
0x0E080003 CONSTANT PR_MESSAGE_SIZE

1 CONSTANT MAPI_TO  \ Recipient is a primary recipient         */
2 CONSTANT MAPI_CC  \ Recipient is a copy recipient            */
3 CONSTANT MAPI_BCC \ Recipient is blind copy recipient        */


0x00000004 CONSTANT CLEAR_READ_FLAG

\ 8 CONSTANT MAPI_DIALOG

0x35E00102 CONSTANT PR_IPM_SUBTREE_ENTRYID

\ �������� �����
0x36020003 CONSTANT PR_CONTENT_COUNT
0x36030003 CONSTANT PR_CONTENT_UNREAD
0x3613001E CONSTANT PR_CONTAINER_CLASS \ ����. IPF.Appointment

\ ���� ������
0x40380 CONSTANT MAPI_W_ERRORS_RETURNED \ ��� ::GetProps �������� "�� ������� ���� �� �������"

\ �������� �������
\ 3001001E PR_DISPLAY_NAME -- �����
0x3704001E CONSTANT PR_ATTACH_FILENAME \ 8.3
0x3707001E CONSTANT PR_ATTACH_LONG_FILENAME
0x370E001E CONSTANT PR_ATTACH_MIME_TAG \ ����. application/octet-stream
0x3713001E CONSTANT PR_ATTACH_CONTENT_LOCATION \ ������ �������� URL ����������� ��������, � *.h ��� ����
0x37050003 CONSTANT PR_ATTACH_METHOD
0x37010102 CONSTANT PR_ATTACH_DATA_BIN
0x00000001 CONSTANT ATTACH_BY_VALUE

0x0E1B000B CONSTANT PR_HASATTACH
0x0E200003 CONSTANT PR_ATTACH_SIZE
0x0E210003 CONSTANT PR_ATTACH_NUM

\ �������� IPM
0x00170003 CONSTANT PR_IMPORTANCE
\ PR_MESSAGE_CLASS=IPM.Task
0x00360003 CONSTANT PR_SENSITIVITY
\ PR_SUBJECT=��������� ������
\ PR_MESSAGE_DELIVERY_TIME=51426DC0 
0x30070040 CONSTANT PR_CREATION_TIME
0x30080040 CONSTANT PR_LAST_MODIFICATION_TIME \ ����. 4A8915B0
0x00390040 CONSTANT PR_CLIENT_SUBMIT_TIME

\ ��� �������� ������:
\ 8059000B 57570000->57570001 
\ 81250003 0->2 
\ 80580040 �� ���� ->9C1C8800 

\ HTML
0x3FDE0003 CONSTANT PR_INTERNET_CPID 
0x10090102 CONSTANT PR_RTF_COMPRESSED
0x1013001E CONSTANT PR_HTML_BODY

0x007D001E CONSTANT PR_TRANSPORT_MESSAGE_HEADERS

0x59020003 CONSTANT PR_INETMAIL_OVERRIDE_FORMAT
\ Value	Outlook Setting	Message Format	Attachment Encoding
\ 0	Unknown	Depends on default IMS settings	Depends on default IMS settings
\ 1	MIME	MIME	Base64
\ 2	UUEncode	Text	UUEncode
\ 3	BINHEX	Text	BinHex
\ #define ENCODEDONTKNOW 0
\ #define ENCODEMIME 1
\ #define ENCODEUUENCODE 2
\ #define ENCODEBINHEX 3

0x10810003 CONSTANT PR_LAST_VERB_EXECUTED \ 102 = EXCHIVERB_REPLYTOSENDER
0x10820040 CONSTANT PR_LAST_VERB_EXECUTION_TIME

\ ���������� (���������) ���������
0x0077001E CONSTANT PR_RCVD_REPRESENTING_ADDRTYPE \ SMTP
0x0075001E CONSTANT PR_RECEIVED_BY_ADDRTYPE \ SMTP

0x0078001E CONSTANT PR_RCVD_REPRESENTING_EMAIL_ADDRESS \ ac@forth.org.ru
0x0076001E CONSTANT PR_RECEIVED_BY_EMAIL_ADDRESS

0x00430102 CONSTANT PR_RCVD_REPRESENTING_ENTRYID
0x003F0102 CONSTANT PR_RECEIVED_BY_ENTRYID

0x0044001E CONSTANT PR_RCVD_REPRESENTING_NAME \ Andrey Cherezov
0x0040001E CONSTANT PR_RECEIVED_BY_NAME

0x0070001E CONSTANT PR_CONVERSATION_TOPIC \ Re[4]: cvs   eserv
0x80C5000B CONSTANT PR_UseTNEF

0x30000003 CONSTANT PR_ROWID \ ����. ����� Rcpt � ������

0x0002 CONSTANT CCSF_SMTP		
0x0004 CONSTANT CCSF_NOHEADERS		
0x0020 CONSTANT CCSF_INCLUDE_BCC	
0x0080 CONSTANT CCSF_USE_RTF		
0x4000 CONSTANT CCSF_NO_MSGID		

0x00000002 CONSTANT STGM_READWRITE
0x00001000 CONSTANT STGM_CREATE

1 CONSTANT STATFLAG_NONAME

\ ������ � Outbox
\ PR_IPM_OUTBOX_ENTRYID
\ PR_DELETE_AFTER_SUBMIT
