Pipeline to prepare and create files for submitting SARS-CoV-2 consensus sequences to GISAID. The pipeline only requires Nextflow and Docker installed in order to run. However, there are several features of the various scripts that will only work on the internal databases of NIPH. 

Example run:
```
nextflow run main.nf --LW /mnt/N/Virologi/Influensa/2223/LabwareUttrekk/ -profile local --submitter jonbra
```

Tanker rundt ny versjon:

1. Parse BN.RData-objektet, sjekke om en sekvens er submittet tidligere eller ikke.
2. Hvis ikke MIK, sjekke om prøven er svart ut. 
3. Sjekke coverage og innsender og alt slikt. 
4. Deretter lage metadata som før. 
5. Så det å lage metadata er vel ganske rett frem? Det eneste jeg må gjøre er å lage en lookup-funksjon som henter authors etc.?
6. Dvs. at vi dropper å skrive et samplesheet faktisk...
7. En annen ting, kanskje gå over til å bruke LW "daily dump" med en gang?
