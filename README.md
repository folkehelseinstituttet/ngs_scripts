Neste oppgaver:
1. Lage find fasta process
    - Kjøre på kontormaskinen foreløpig - egen params i profile for lokalt.
    - Kan ha en blob-path i azure profile
2. Lage Frameshift process + clean up
3. Joine og lage felles filer. 
4. Logs. Ikke bare fra BN-parsinga, men også fra nextflow-kjøringa.
    - Inkludere datoer, sample sheet, frameshift results + logs + versions fra nextflow.

Planen er å gjøre om Gisaid-submisjonen til en NextFlow pipeline. 
Viktige premisser:
1. Pipelinen må kunne fungere lokalt
2. Pipelinen bør kunne fungere med Azure Batch
3. Pipelinen må være portable (dvs. docker based).

I bin-mappa ligger Frameshift-scriptene fra Nacho.
Husk å dokumenter versjoner etc. Dato for pull kanskje...
Jeg kunne lagt inn en git pull for hver gang. Dette krever netttilgang, og det kan jo oppstå breaking changes...


Hvordan løser jeg dette med input-filer? De bør helst ligge på N. Kan jeg ikke bare bruke et argument med filepaths?

For å finne fasta-filer så må jeg søke gjennom N-disken.

Det som er fint med å bruke NextFlow er at jeg kan holde alle filbaner til N og slik skjult i en egen config-fil.

Det er flere alternativer:
Alternativ 1:
1. Process som preparerer metadata.
    - I dag gjøres dette per oppsett. Må endres til å gjøres på alle oppsettene i så fall. 
2. Process som finner fasta-filene
    - I dag gjøres dette per oppsett. Må endres til å gjøres på alle oppsettene i så fall. 
3. Process for Frameshift-finder - på alle sekvensene samtidig. 
4. Process som Fjerner BAD sekvenser og lager final datasets. 

Alternativ 2:
Gjøre hele prosessen per oppsett - slik som i dag.
Kan da lage et sample sheet med sampleName som er per oppsett. 
Tenker uansett det er best å benytte et sample sheet ala det vi har i dag som utgangspunkt. Med ulike oppsett. 
Men selve skriptet trenger jo ikke tenke på dette egentlig...
Men sample sheetet bør også være input til Gisaid-scriptet.

gisaid-script.R ${sampleSheet} ${BN}

Problem: Det virker ikke å ta list.files på N-disken...
