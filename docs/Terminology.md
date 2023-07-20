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

## C4 Component diagram - Database
A data store for persistent business objects.

{{ insert diagram here }}

## C4 Component diagram - RPCAPI

{{ insert diagram here }}

### Clerk
A server that responds to *job requests* and *questions* from users.  

**Job request**
* A synchronous request.
  Expresses the desire to have a [job] performed asynchronously.

  A *clerk* responds to a *job request* by first consulting the [database] for a matching [job] that is available for reuse.
  If there is such a job the *clerk* responds with its [job id].
  Otherwise it triggers the [creation][create] of a new [job] and responds with that [job id] instead.

**Question**
* A synchronous request.
  Expresses the need for some piece of information.

  A *clerk* responds to a *question* using information from the [database] and/or its [rpcapi configuration].
  It may also query the [public DNS] to answer certain questions.

### RPCAPI Configuration
A data store for Zonemaster Backend settings.

## C4 Component diagram - Test Agent

{{ insert diagram here }}

### Dispatcher
A broker that monitors and schedules the performing of [jobs].

A *dispatcher* notices [jobs][job] in the [WAITING] state, [claims][claim] them and delegates their processing to [workers][worker].
It also [expires][expire] [jobs][job] that have been in the [PROCESSING] state for too long.

### Test Agent Configuration
A data store for Zonemaster Backend settings.

### Worker
A thread that performs [jobs][job].

# State

## Job
A class of business objects persisted in the [database].
The principal unit of work in Zonemaster Backend.

Processing a *job* means executing a Zonemaster Engine test and performing associated bookkeeping tasks.

**Job id**
* An identifier.

  Every job has a unique *job id*.

### Job life cycle
```mermaid
stateDiagram-v2
direction LR

[*] --> WAITING: request
WAITING --> PROCESSING: claim
PROCESSING --> COMPLETED: complete
PROCESSING --> CRASHED: crash
PROCESSING --> EXPIRED: expire
```
**WAITING**
* The *job* is waiting to be processed.

**PROCESSING**
* The *job* is currently being processed.

**COMPLETED**
* The *job* was already processed.
  The Zonemaster Engine test terminated normally.
  A report is available with the full test results.

**CRASHED**
* The *job* was already processed.
  A critical error occurred while processing.
  A report is available with the partial test results.

**EXPIRED**
* The *job* was already processed.
  The processing was cancelled because it took too long. 
  A report is available with the partial test results.

**create**
* Triggered by a [clerk] when it receives a [job request] from a user and no matching *job* is available for reuse.

**claim**
* Triggered by a [dispatcher] when it notices that there is a [worker] available to process this *job*.

**complete**
* Triggered by a [worker] when the Zonemaster Engine test returns normally.

**crash**
* Triggered by a [worker] when a critical error occurs in the *PROCESSING* state.

**expire**
* Triggered by a [dispatcher] when a *job* has been in the *PROCESSING* state for too long.

[claim]: #job-life-cycle
[clerk]: #clerk
[create]: #job-life-cycle
[database]: #database
[dispatcher]: #dispatcher
[expire]: #job-life-cycle
[job]: #job
[job id]: #job
[job request]: #clerk
[processing]: #job-life-cycle
[question]: #clerk
[rpcapi configuration]: #rpcapi-configuration
[test agent configuration]: #test-agent-configuration
[waiting]: #job-life-cycle
[worker]: #worker
