# Architecture
## C4 Context diagram
```mermaid
C4Context

Person_Ext(termuser, "Terminal user", "A user with network access<br/>to Zonemaster Backend<br/>and zmtest installed")
Person_Ext(netuser, "Web user", "A user with network access<br/>to Zonemaster Backend<br/>and a web browser")
System_Ext(gui, "Zonemaster GUI", "Provides a GUI to<br/>Zonemaster Backend")

Enterprise_Boundary(provider, "Provider") {
  System(backend, "Zonemaster Backend", "Allows users to create jobs<br/>and query their status<br/>and results")
  Component_Ext(dbms, "DBMS", "Stores jobs")
}

Enterprise_Boundary(dependencies, "Network dependencies") {
  SystemDb_Ext(dns, "Public DNS", "Contains zones<br/>to be tested")
  SystemDb_Ext(asn, "ASN server", "Maps IP addresses<br/>to ASNs")
}

Rel(netuser, backend, "Uses", "JSON-RPC")
Rel(netuser, gui, "Uses", "HTTP")
Rel(termuser, backend, "Uses", "zmtest")
Rel(backend, dbms, "Uses", "SQL")
Rel(backend, dns, "Queries", "DNS")
Rel(backend, asn, "Queries", "DNS or WHOIS")

UpdateElementStyle(dependencies, $borderColor="white")
UpdateElementStyle(asn, $borderColor="#888888")
UpdateElementStyle(dns, $borderColor="#888888")
UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="2")
```

## C4 Container diagram
```mermaid
C4Container

System_Boundary(dbms, "DBMS") {
  ComponentDb(db, "Database", "", "Stores jobs")
}

System_Boundary(backend, "Zonemaster Backend") {
  Container(testagent, "Test Agent", "Perl", "Allows users to create jobs<br/>and query their status<br/>and results")
  Container(rpcapi, "RPCAPI", "Perl", "Allows users to create jobs<br/>and query their status<br/>and results")
}

Enterprise_Boundary(dependencies, "Network dependencies") {
  SystemDb_Ext(asn, "ASN server", "Maps IP addresses<br/>to ASNs")
  SystemDb_Ext(dns, "Public DNS", "Contains zones<br/>to be tested")
  System_Ext(gui, "Zonemaster GUI", "Provides a GUI to<br/>Zonemaster Backend")
}

System_Boundary(terminal, "Terminal") {
  Component(zmtest, "zmtest", "sh")
  Person_Ext(termuser, "Terminal user")
}

System_Boundary(desktop, "Desktop") {
  Component_Ext(browser, "Web browser")
  Person_Ext(netuser, "Web user")
}

Rel(netuser, browser, "Uses", "GUI")
Rel(browser, rpcapi, "Uses", "JSON-RPC")
Rel(browser, gui, "Queries", "HTTP")
Rel(termuser, zmtest, "Uses")
Rel(zmtest, rpcapi, "Uses", "JSON-RPC")
Rel(rpcapi, db, "Uses", "SQL")
Rel(testagent, db, "Uses", "SQL")
Rel(rpcapi, dns, "Queries", "DNS")
Rel(testagent, dns, "Queries", "DNS")
Rel(testagent, asn, "Queries", "DNS or WHOIS")

UpdateElementStyle(dependencies, $borderColor="white")
UpdateElementStyle(asn, $borderColor="#888888")
UpdateElementStyle(dns, $borderColor="#888888")
UpdateLayoutConfig($c4ShapeInRow="2", $c4BoundaryInRow="3")
```

# Behavior

Backend is all about performing jobs.
A job is the unit of work.
A job is identified by a job id.

End users create jobs and Test Agent performs them.
End users can list historical jobs and get the status and result of individual jobs.

```mermaid
---
title: Job life cycle
---
stateDiagram-v2

[*] --> waiting: create_new_test
waiting --> running: claim_test
running --> completed: store_results
running --> crashed
running --> lapsed
```
