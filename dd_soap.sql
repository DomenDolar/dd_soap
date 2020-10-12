create or replace package DD_SOAP is

/*
STATUS
13.10.2020 - Updateing package ....
10.6.2015 - Response is no longer limited ro VARCHAR2 but CLOB
28.11.2006 - First version - Domen Dolar
*/

  C_URL varchar2(100) := 'http://url of target SOAP service...';

  /*Added 29.6.2017 option to add own header ....*/
  type header  IS RECORD (
    name     VARCHAR2(256),
    value    VARCHAR2(256));

  type theader is table of header index by binary_integer;

  /* v.p 04.10.2016 */

  C_TIMEOUT number := 180;
  c_hdr theader;


  /* A type to represent a SOAP RPC request */
  TYPE request IS RECORD (
    method     VARCHAR2(256),
    namespace  VARCHAR2(256),
    body       CLOB);

  /* A type to represent a SOAP RPC response */
  TYPE response IS RECORD (
    doc xmltype);

  function cdata(pXml clob) return clob;

  function ChangeSpecialCode2HTMLUTF(v_text clob) return clob;

  /*
   * Create a new SOAP RPC request.
   */
  FUNCTION new_request(method    IN VARCHAR2,
                       namespace IN VARCHAR2)
                       RETURN request;

  /*
   * Add a simple parameter to the SOAP RPC request.
   */
  PROCEDURE add_parameter(req   IN OUT NOCOPY request,
                          name  IN VARCHAR2,
                          type  IN VARCHAR2,
                          value IN CLOB);

  /*
   * Make the SOAP RPC call.
   */
  FUNCTION invoke(req    IN OUT NOCOPY request,
                  url    IN VARCHAR2,
                  action IN VARCHAR2,
                  hdr theader default c_hdr
                  ) RETURN response;

  /*
   * Retrieve the sipmle return value of the SOAP RPC call.
   */
  FUNCTION get_return_value(resp      IN OUT NOCOPY response,
                            name      IN VARCHAR2,
                            namespace IN VARCHAR2) RETURN clob;

  FUNCTION get_return_value(resp      IN OUT NOCOPY response) RETURN clob;

  PROCEDURE show_envelope(env IN VARCHAR2);

end;
/
create or replace package body DD_SOAP is

function cdata(pXml clob) return clob is
 begin
 return '<![CDATA['||pXml||']]>';
 end;
 
 

function ChangeSpecialCode2HTMLUTF(v_text clob) return clob is
  begin
--https://www.rapidtables.com/code/text/unicode-characters.html    
return replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(v_text,
                                                                                'æ',
                                                                                '&#263;'),
                                                                        'Æ',
                                                                        '&#262;'),
                                                                'ð',
                                                                '&#273;'),
                                                        'Ð',
                                                        '&#272;'),
                                                'ž',
                                                '&#382;'),
                                        'Ž',
                                        '&#381;'),
                                'è',
                                '&#269;'),
                        'È',
                        '&#268;'),
                'š',
                '&#353;'),
        'Š',
        '&#352;');
end;


  FUNCTION new_request(method    IN VARCHAR2,
                       namespace IN VARCHAR2)
                       RETURN request AS
    req request;
  BEGIN
    req.method    := method;
    req.namespace := namespace;
    RETURN req;
  END;

  PROCEDURE add_parameter(req   IN OUT NOCOPY request,
                          name  IN VARCHAR2,
                          type  IN VARCHAR2,
                          value IN CLOB) AS
  BEGIN
       if type is null then
    req.body := req.body || '<'||name||'>'||ChangeSpecialCode2HTMLUTF(value)||'</'||name||'>';
       else  
    req.body := req.body || '<'||name||' xsi:type="'||type||'">'||ChangeSpecialCode2HTMLUTF(value)||'</'||name||'>';
       end if;
  END;

  PROCEDURE generate_envelope(req IN OUT NOCOPY request,
            env IN OUT NOCOPY CLOB) AS
  BEGIN
    env := '<?xml version="1.0"?>
    <SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/"
                       xmlns:xsi="http://www.w3.org/1999/XMLSchema-instance"
                       xmlns:xsd="http://www.w3.org/1999/XMLSchema"
                       xmlns:SOAP-ENC="http://schemas.xmlsoap.org/soap/encoding/">
        <SOAP-ENV:Body SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
           <'||req.method||' '||req.namespace||'>'||
req.body||'</'||req.method||'>
    </SOAP-ENV:Body>
    </SOAP-ENV:Envelope>';
  END;

  PROCEDURE show_envelope(env IN VARCHAR2) AS
    i   pls_integer;
    len pls_integer;
  BEGIN
    i := 1; len := length(env);
    WHILE (i <= len) LOOP
      dbms_output.put_line(substr(env, i, 60));
      i := i + 60;
    END LOOP;
  END;

  PROCEDURE check_fault(req request, resp IN OUT NOCOPY response) AS
    fault_node   xmltype;
    fault_code   VARCHAR2(256);
    fault_string VARCHAR2(32767);
  BEGIN
     fault_node := resp.doc.extract('/soap:Fault',
       'xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/');
     IF (fault_node IS NOT NULL) THEN
       fault_code := fault_node.extract('/soap:Fault/faultcode/child::text()',
   'xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/').getstringval();
       fault_string := fault_node.extract('/soap:Fault/faultstring/child::text()',
   'xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/').getstringval();
       raise_application_error(-20000, req.method ||' '||req.namespace ||' '||fault_code || ' - ' || fault_string);
     END IF;
  END;

  FUNCTION invoke(req    IN OUT NOCOPY request,
                  url    IN VARCHAR2,
                  action IN VARCHAR2, hdr theader default c_hdr) RETURN response AS
  resp      response;
  http_req utl_http.req;
  http_resp utl_http.resp;
  reqlength binary_integer;
  responsebody clob := null;
  resplength binary_integer;
  buffer varchar2(32767);
  amount pls_integer := 2000;
  offset pls_integer := 1;
  reslength binary_integer;
  eob boolean := false;
  requestbody clob;
  v_url varchar2(1000);
  v_t date;
  v_i number;  
begin
    v_t := sysdate;
    generate_envelope(req, requestbody);

  --  show_envelope(requestbody);

--return resp;
  utl_http.set_transfer_timeout(C_TIMEOUT);


  if instr(upper(url),'HTTP') = 0 then v_url :=  C_URL||url; else v_url := url; end if;
  http_req := utl_http.begin_request(v_url, 'POST', 'HTTP/1.1');
  utl_http.set_header(http_req, 'Content-Type', 'text/xml; charset=UTF-8');
  utl_http.set_header(http_req,
                      'SOAPAction',
                      action);
  for i in 1..hdr.count loop
    utl_http.set_header(http_req, hdr(i).name, hdr(i).value );
  end loop;
 -- utl_http.set_header(http_req, 'Transfer-Encoding', 'chunked');
  reqlength := dbms_lob.getlength(requestbody);
  utl_http.set_header(http_req, 'Content-Length', reqlength );
  while (offset < reqlength) loop
    dbms_lob.read(requestbody, amount, offset, buffer);
    utl_http.write_text(http_req, buffer);
    -- dbms_output.put_line('============================================');
    -- dbms_output.put_line(buffer);
    offset := offset + amount;
  end loop;
  DBMS_LOB.CREATETEMPORARY(responsebody, true);
  http_resp := utl_http.get_response(http_req);
--  dbms_output.put_line('After http_resp');
  while not (eob)
   loop
     begin
        utl_http.read_text(http_resp, buffer, 32767);
      if buffer is not null and length(buffer) > 0 then
        dbms_lob.writeappend(responsebody, length(buffer), buffer);
      end if;
    exception
      when UTL_HTTP.END_OF_BODY THEN
        eob := true;
    end;
  end loop;
--  dbms_output.put_line('After resp loop');
    utl_http.end_response(http_resp);

    if http_resp.status_code = 500 then
       v_i := round((sysdate - v_t)*3600*24);
       raise_application_error('-20000','HTTP ERROR: 500 Internal Server Error; EXECUTION TIME(s):'||v_i);
    end if;

    if instr(responsebody,'<?xml') > 0 then
       responsebody := substr(responsebody,instr(upper(responsebody),'<?XML'));
       responsebody := substr(responsebody,1, instr(upper(responsebody),'ENVELOPE>')+9 );
    end if;

--dbms_output.put_line('responsebody: ' || substr(responsebody,1,10000));
--return resp;

    if length(responsebody) > 1 then
       resp.doc := xmltype.createxml(responsebody);
       resp.doc := resp.doc.extract('/soap:Envelope/soap:Body/child::node()',
         'xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"');

        --show_envelope(resp.doc.getstringval());
       check_fault(req,resp);
    end if;

    RETURN resp;
    DBMS_LOB.freetemporary(responsebody);
  END;
/*
  FUNCTION invoke(req    IN OUT NOCOPY request,
                  url    IN VARCHAR2,
                  action IN VARCHAR2) RETURN response AS
    env       VARCHAR2(32767);
    http_req  utl_http.req;
    http_resp utl_http.resp;
    resp      response;
  BEGIN
    generate_envelope(req, env);

  --  show_envelope(env);
--return resp;

    http_req := utl_http.begin_request(url, 'POST','HTTP/1.0');
    utl_http.set_header(http_req, 'Content-Type', 'text/xml');
    utl_http.set_header(http_req, 'Content-Length', length(env));
    utl_http.set_header(http_req, 'SOAPAction', action);
    utl_http.write_text(http_req, env);

    --show_envelope(http_req.method);

    http_resp := utl_http.get_response(http_req);
    utl_http.read_text(http_resp, env);
    utl_http.end_response(http_resp);

   -- htp.p(env);

    resp.doc := xmltype.createxml(env);
    resp.doc := resp.doc.extract('/soap:Envelope/soap:Body/child::node()',
      'xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"');

     --show_envelope(resp.doc.getstringval());
    check_fault(resp);
    RETURN resp;
  END;
*/

  FUNCTION get_return_value(resp      IN OUT NOCOPY response,
                            name      IN VARCHAR2,
                            namespace IN VARCHAR2) RETURN clob AS
  BEGIN
    RETURN resp.doc.extract('//'||name||'/child::text()',
      namespace).getclobval();
  exception when others then
    return '';
  END;

  FUNCTION get_return_value(resp      IN OUT NOCOPY response) RETURN clob AS
  BEGIN
    RETURN resp.doc.getclobval();
  exception when others then
    return '';
  END;




end DD_SOAP;
/
