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

# Glossary

### Job

A job is a unit of work in Zonemaster Backend.
It follows a life cycle.

```mermaid
---
title: Job life cycle
---
stateDiagram-v2
direction LR

[*] --> WAITING: request
WAITING --> PROCESSING: claim
PROCESSING --> COMPLETED: complete
PROCESSING --> CRASHED: crash
PROCESSING --> LAPSED: lapse
```

#### State: WAITING

The job is waiting to be processed.

#### State: PROCESSING

The job is being processed.
This means that a Zonemaster Engine test is being performed.

#### State: COMPLETED

This is an end state.
The job has been processed.
The Zonemaster Engine test ran to completion.
A report is available with the full test results.

#### State: CRASHED

This is an end state.
The job has been processed.
A critical error occurred while running.
A report is available with the partial test results.

#### State: LAPSED

This is an end state.
The job has been processed.
The processing was cancelled because it took too long. 
A report is available with the partial test results.

#### Meta-State: DONE

The job is in one of the COMPLETED, CRASHED or LAPSED states.
