\ http://www.gnu.org/software/libtasn1/manual/libtasn1.html
\ ��������� dll: libtasn1.dll
\ http://josefsson.org/gnutls4win/

REQUIRE SO  ~ac/lib/ns/so-xt.f
REQUIRE {   lib/ext/locals.f

ALSO SO NEW: libtasn1-3.dll
ALSO SO NEW: libtasn1-3.so

USER uAsn1LenOver

: >asn_len { len \ nlen alenx alen -- asnlen u }
\ ����������� ����� len � asn1-����� asnlen � "����� ������"
\ (����� �������������� ����) u.
\ ���� ���������� ����� ������ ��� 0xFFFFFF, ��
\ u=5, � �� ������������� � asnlen ���� ����� � uAsn1LenOver
  ^ nlen ^ alen len 3 asn1_length_der DROP
  alenx uAsn1LenOver !
  alen nlen
;
: >asn_str { a u \ a2 u2 -- a2 u2 }
\ ����������� ������ a u � ������ � asn1-��������� a2 u2
  u 5 + ALLOCATE THROW -> a2
  ^ u2 a2 u a 4 asn1_octet_der DROP
  a2 u2
;
: asn_str> { a u \ u2 -- a2 u2 }
\ ����������� ������ � asn1-��������� (a) � ����-������ a2 u2
\ ��. �� �� ������� AsnStr> � ~ac/lib/list/asn1.f 
  ^ u2 u a 3 asn1_get_length_ber
  u2 a + SWAP
;
PREVIOUS PREVIOUS

\EOF

S" test" >asn_str DUP . DUMP CR
" - Function: void asn1_octet_der (const unsigned char * str, int str_len, unsigned char * der, int * der_len)
    str: OCTET string.
    str_len: STR length (str[0]..str[str_len-1]).
    der: string returned.
    der_len: number of meaningful bytes of DER (der[0]..der[ans_len-1]).
    Creates the DER coding for an OCTET type (length included). 
" STR@  >asn_str DUP . 2DUP DUMP CR asn_str> TYPE

\EOF
10 >asn_len . SP@ 4 DUMP DROP CR
500 >asn_len . SP@ 4 DUMP DROP CR
1000000 >asn_len . SP@ 4 DUMP DROP CR
0xFFFFFF  >asn_len . SP@ 4 DUMP DROP CR
0x1FFFFFF  >asn_len . SP@ 4 DUMP DROP CR
