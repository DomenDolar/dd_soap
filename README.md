# dd_soap

Package is prepared to make SOAP calls from PL/SQL. URL in SOAP call must be added to ACL.</br></br>

Sample of SOAP REQUEST generated from WSDL</br>

```
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:java="http://soap.my.com">
   <soapenv:Header/>
   <soapenv:Body>
<java:myFunction>
          <name>John Doe</name>
          <address>nn</address>
          <from>Somewhere</from>
      </java:myFunction>
  </soapenv:Body>
</soapenv:Envelope>
```
Sample of SOAP RESPONSE:
```
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">
   <soapenv:Body>
      <ns2:myFunctionResponse xmlns:ns2="http://soap.my.com">
         <data>Data from John Doe ...</data>
      </ns2:myFunctionResponse>
   </soapenv:Body>
</soapenv:Envelope>
```

Code in PL/SQL - sample

```
declare
   req  dd_soap.request;
   resp dd_soap.response;
begin  
       dd_soap.C_TIMEOUT := 99; //setting of new timeout in seconds
	   //Prepearing REQUEST
       req := dd_soap.new_request('java:myFunction', 'xmlns:java="http://soap.my.com"');
       dd_soap.add_parameter(req, 'name',null,'John Doe');
       dd_soap.add_parameter(req, 'address',null,'nn');
       dd_soap.add_parameter(req, 'from',null,'Somewhere');
	   //Sending REQUEST, by default is send to URL stored in DD_SOAP package. If you start with http.... the URL is overwritten.
       resp := dd_soap.invoke(req,'/SERVICE/SERVICESoapService', 'myFunction');
	   //Parsing RESPONSE
       return decodeXML(dd_soap.get_return_value(resp, 'data', 'xmlns:ns2="http://soap.my.com"')) ;                  
end;
```	 
	 
	 


