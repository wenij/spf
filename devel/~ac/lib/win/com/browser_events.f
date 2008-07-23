REQUIRE EnumConnectionPoints ~ac/lib/win/com/events.f

\ COM-������� ������� ����� �������� � �������� ����� IID_IWebBrowserEvents2
\ ����, ���� �� ������� ���������� � ��������� ���� IID, �� ��� �������
\ �������������� ������� IID_IDispatch.

IID_IDispatch
Interface: IID_IWebBrowserEvents2 {34A715A0-6587-11D0-924A-0020AFC7AC4D}
\ ������ ����� ���������� �� ����������, �.�. �� "��������" -
\ ��� ����������� ������� ID ���� ������� ���������� ������ IDispatch::Invoke
Interface;

IID_IWebBrowserEvents2
Class: SPF.IWebBrowserEvents2 {C6DFBA32-DF7B-4829-AA3B-EE4F90ED5961} \ ���� clsid �����
Extends SPF.IDispatch

( ����� ����� ��� ������������� �������������� ������ ������, ��������
  : ::Invoke
    ...
  ; METHOD
  �� ������� ���������� � com_server2.f ������� ��� ���������� �� ������������.
)

\ ����������� ������� �������� (����) ���������� �� IDispatch::Invoke �� ��������� ID
\ ��������� ��������� ���������� �� �� variant'�� � ����-���� :)

ID: DISPID_DOCUMENTCOMPLETE     259 ( urla urlu bro -- )
    COM-DEBUG @ IF ." DocumentComplete! doc=" . \ IWebBrowser2 ������������ ������
                   TYPE CR
                ELSE DROP 2DROP THEN
;
ID: DISPID_STATUSTEXTCHANGE   102 ( addr u -- )
    COM-DEBUG @ IF ." StatusTextChange:" TYPE CR ELSE 2DROP THEN
;
ID: DISPID_PROGRESSCHANGE     108  ( ProgressMax Progress -- )
    \ sent when download progress is updated
    COM-DEBUG @ IF ." ProgressChange:" . ." from " . CR ELSE 2DROP THEN
;
ID: DISPID_FILEDOWNLOAD         270 ( bool bool -- )
    \ Fired to indicate the File Download dialog is opening
    COM-DEBUG @ IF ." FileDownload:" . . CR ELSE 2DROP THEN
;
ID: DISPID_NAVIGATECOMPLETE2    252 ( urla urlu bro_win -- )
    \ UIActivate new document
    COM-DEBUG @ IF ." NavigateComplete2! win/frame=" . TYPE CR ELSE DROP 2DROP THEN
;
ID: DISPID_COMMANDSTATECHANGE 105 ( bool command -- )
    COM-DEBUG @ IF ." CommandStateChange:" . . CR ELSE 2DROP THEN
;
ID: DISPID_DOWNLOADBEGIN      106 ( -- )
    COM-DEBUG @ IF ." DownloadBegin..." CR THEN
;
ID: DISPID_DOWNLOADCOMPLETE   104 ( -- )
    COM-DEBUG @ IF ." DownloadComplete!" CR THEN
;
ID: DISPID_SETSECURELOCKICON    269 ( icon -- )
    \ sent to suggest the appropriate security icon to show
    COM-DEBUG @ IF ." SetSecureLockIcon:" . CR ELSE DROP THEN
;
ID: DISPID_SETPHISHINGFILTERSTATUS 282 ( ... )
    \ ��������� ��� � ����������, ����� �� ������������� ������ :
    \ http://hatayquelua.wordpress.com/2008/07/03/bho-programming/
    \ Deprecated. Fires to indicate the progress and status of Microsoft Phishing Filter analysis of the current webpage.
    \ Deprecated? �� IE8 ��� ����� ���� ��� �������.
    COM-DEBUG @ IF ." SetPhishingFilterStatus:" . CR ELSE DROP THEN
;
ID: DISPID_TITLECHANGE    113  ( addr u -- )
    \ sent when the document title changes
    COM-DEBUG @ IF ." Title:" TYPE CR ELSE 2DROP THEN
;
ID: DISPID_BEFORENAVIGATE2      250   \ hyperlink clicked on
(      
    IDispatch *pDisp,
    VARIANT *url,
    VARIANT *Flags,
    VARIANT *TargetFrameName,
    VARIANT *PostData,
    VARIANT *Headers,
    VARIANT_BOOL *Cancel
)
   COM-DEBUG @ IF 
  ." BeforeNavigate2: bro_win=" .
   ."  url=" TYPE ."  flags=" . ." target_frame=" TYPE CR
  ." post=" DUP IF DUP 3 CELLS + @ SWAP 4 CELLS + @ TYPE CR ELSE . THEN
  ."  headers=" TYPE ."  cancel=" .
  ." depth=" DEPTH . DropXtParams CR
   ELSE DropXtParams THEN
;
ID: DISPID_NAVIGATEERROR 271 \ Fires when an error occurs during navigation.
(      
    IDispatch *pDisp,
    VARIANT *URL,
    VARIANT *TargetFrameName,
    VARIANT *StatusCode,
    VARIANT_BOOL *Cancel
)
   COM-DEBUG @ IF ." NavigateError." CR THEN DropXtParams
;
ID: DISPID_PROPERTYCHANGE     112 ( addr u -- )
    \ sent when the PutProperty method is called
    COM-DEBUG @ IF ." PropertyChange:" TYPE CR ELSE 2DROP THEN
;
ID: DISPID_NEWWINDOW3           273 \ new window is to be created
(      
    IDispatch **ppDisp,
    VARIANT_BOOL *Cancel,
    DWORD dwFlags,
    BSTR bstrUrlContext,
    BSTR bstrUrl
)
   COM-DEBUG @ IF 
   ." NewWindow3: idisp=" . ." cancel=" . ." flags:" . CR
   ." referer=" TYPE ."  url=" TYPE CR
   ELSE DropXtParams THEN
;

Class;

: {34A715A0-6587-11D0-924A-0020AFC7AC4D} ( ppvObject iid oid -- hresult )
\ ������������ ����������. ��. ::QueryInterface � com_server2.f
  COM-DEBUG @ IF ." SPF.IWebBrowserEvents2 - OK!" THEN
  2DROP SPF.IWebBrowserEvents2 SWAP ! 0
;

\ � ��� ���������� ����������� � �������� (connection points) ������������ IE7

\ uuid(34A715A0-6587-11D0-924A-0020AFC7AC4D), // IID_DWebBrowserEvents2
\ helpstring("Web Browser Control events interface"),

\ uuid(EAB22AC2-30C1-11CF-A7EB-0000C05BAE0B), // DIID_DWebBrowserEvents
\ helpstring("Web Browser Control Events (old)"),

\ uuid(9BFBBC02-EFF1-101A-84ED-00AA00341D07),
\ interface IPropertyNotifySink : IUnknown
