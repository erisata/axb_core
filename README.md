Overview
================================================================================

Goals:

  * Stable and performing;
  * Explicit;
  * Manageable.


Main Principles
----------------------------------------

  * One message = one process.
  * EIP implementation.


Alternatives
----------------------------------------

  * [ClaudI](http://cloudi.org/).



Design
================================================================================

The ESB consists of adapters and routers.


Supervision
----------------------------------------

  * Each adapter has its own supervision tree.
  * Each router (flow) has its own supervisor.
  * Related flows are linked with each other.



Pagalvot
-----------------

  * ESB turėtų leisti paskirstyti flow'us per serverius, gal pagal tipą.
  * Naujų integracijų kūrimas turi būti nesudėtingas.


Naudoti `Riak Core` dėl:

  * Clusterio valdymas.
  * Apkrovos paskirstymas (tik ar reikia tą daryt, nes yra išoriniai balanseriai)?

Aplikacija embedded vs separate:

  * Stabdant konkrečią aplikaciją sustoti turi tik jos procesai.
  * Crash'inantis vienos aplikacijos flow'ų super supervizoriui kitos aplikacijos turbūt neturi nukentėti.
  * Pagalvoti per upgrade'ų prizmę.
  * Pergalvoti per adresacijos prizmę.


