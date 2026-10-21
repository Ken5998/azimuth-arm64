# Esperimento IR3: controlli ridondanti sui quadrati

## Risultato e obiettivo

L'analisi del dump `azimuth-ir3-01.tar.gz` ha individuato un'ottimizzazione
concreta nel compilatore degli shader. Alcuni programmi calcolano `x*x`,
confrontano `x` con zero e selezionano esplicitamente `+0.0` quando il confronto
è vero. Il prodotto produce già quel risultato.

La patch `patches/0003-nir-remove-redundant-zero-guards-from-squares.patch`
aggiunge una regola NIR per eliminare questo schema in FP32. Conserva i vincoli
su precisione, segno dello zero, infiniti e NaN. La correttezza e l'effetto sul
NIR sono stati verificati localmente; il guadagno in FPS e la nuova allocazione
dei registri su Adreno richiedono ancora una misura sul dispositivo.

L'obiettivo della prova A/B è confrontare due driver costruiti dalla stessa
revisione Mesa e con le stesse opzioni, variando soltanto questa patch. Il driver
installato nella precedente cattura riportava `c05663aea2`, mentre la repository
fissa `c126acd85a645728bcecaa164d7d7c928438e842`: usare direttamente il vecchio
driver come controllo mescolerebbe l'effetto della patch con quello del cambio
di revisione.

## Cosa mostra il dump

Il log completo contiene 982.795.550 byte, 15.510.822 righe e 3.927 blocchi
nativi, ciascuno con un record completo di statistiche. Il suo SHA-256 è
`9f61aa5a68bee7e53110e3bb12e816c25a2ab1735ea8efa195adbb663da7485c`.

Le stampe delle compilazioni parallele si interlacciano. Le statistiche sono
state ricostruite con stadio, ID dello shader, variante e occorrenza. Per
attribuire le istruzioni a un singolo programma sono stati usati soltanto gli
intervalli senza sovrapposizioni tra blocchi nativi.

| Stadio stampato | Blocchi | Istruzioni: mediana | Istruzioni: massimo | `full`: mediana | `max_waves`: mediana |
| --- | ---: | ---: | ---: | ---: | ---: |
| FRAG | 1.283 | 4.943 | 9.295 | 32 | 6 |
| VERT | 1.277 | 646 | 17.421 | 12 | 16 |
| BVERT | 1.273 | 395 | 17.235 | 12 | 16 |
| CL | 90 | 118,5 | 5.880 | 9 | 16 |
| GEOM | 4 | 285 | 525 | 12 | 16 |

Sono istanze di compilazione, comprese varianti e ripetizioni: i BLAKE3 nativi
distinti sono 1.362. Le mediane non sono pesate per le esecuzioni nel gioco.
Il conteggio di istruzioni del compilatore espande repeat e NOP ed esclude il
preambolo; non equivale a un tempo misurato o al costo per pixel. BVERT è la
variante per il binning: la sua compilazione non dimostra che sia stata eseguita
nella precedente cattura in modalità sysmem. L'etichetta CL da sola non
identifica l'API OpenCL usata dall'applicazione.

### Registri

Per Adreno 740 il campo `full` usa gruppi di quattro slot scalari a 32 bit.
I gruppi più numerosi dei fragment shader sono:

| `full` | Slot scalari corrispondenti | Blocchi FRAG | `max_waves` | Thread per wave |
| ---: | ---: | ---: | ---: | ---: |
| 24 | 96 | 187 | 8 | 64 |
| 32 | 128 | 538 | 6 | 64 |
| 48 | 192 | 238 | 4 | 64 |

Tutti questi 963 blocchi usano già wave da 64 thread. Il dump non motiva
un'altra prova generica con `thread64`. Complessivamente, 776 dei 1.283 FRAG
hanno una capacità teorica di 6 o 4 wave per la loro allocazione.

`max_waves` è un limite calcolato, non l'occupazione misurata della GPU.
Una riduzione da `full=32` a un valore non superiore a 24 permetterebbe di
passare da 6 a 8 wave nel modello dei registri; la patch deve essere compilata
con Turnip per sapere se attraversa effettivamente una soglia. La riduzione
del NIR non garantisce una riduzione proporzionale dei registri o degli FPS.

### Memoria privata

Nei 525 intervalli FRAG attribuibili senza ambiguità non compaiono `ldp/stp`.
Esistono invece grossi casi vertex: un VERT da 17.421 istruzioni contiene
780 store e 1.520 load privati, con `full=48` e `max_waves=4`; una variante BVERT
analoga mostra gli stessi accessi. La provenienza degli accessi va distinta tra
spill dei registri e array locali. Questo dato non dimostra uno spilling
diffuso nei fragment shader, né misura il peso di quel vertex shader nel frame.

## Trasformazione

Lo schema matematico osservato è:

```text
prima: risultato = (x == +0.0) ? +0.0 : x * x
dopo:  risultato = x * x
```

Per `+0.0` e `-0.0`, il quadrato è `+0.0`. Per un valore diverso da zero o
infinito il ramo selezionato contiene già la stessa moltiplicazione. Con NaN
il confronto ordinato con zero è falso e resta la stessa moltiplicazione.
Il matcher distingue il valore positivo dello zero nel ramo selezionato.

La regola, vicina alla semplificazione già esistente di `fmulz(a,a)`, è:

```python
(('bcsel', ('feq', a, 0.0), 0.0, ('fmul@32', a, a)), ('fmul', a, a)),
```

Il normale ciclo di ottimizzazione NIR di IR3 la visita prima delle fusioni
tardive delle moltiplicazioni e somme. Il matcher conserva i controlli
floating point delle operazioni sostituite. Il vincolo `@32` limita la nuova
regola al caso FP32 osservato.

La scansione conservativa degli SPIR-V originali trova 5.397 schemi diretti in
612 moduli. Dopo altre semplificazioni NIR possono emergere ulteriori casi:
per esempio, eliminare `1.0 * (x*x)` rende visibile il quadrato al matcher.

Nell'assembly originale sono stati confermati controlli ridondanti in 451 dei
525 blocchi FRAG analizzabili separatamente: 10.434 siti statici includendo le
varianti ripetute, oppure 8.588 dopo deduplicazione per BLAKE3 nativo. I conteggi
del sorgente, del NIR ottimizzato e del nativo descrivono fasi diverse e non
vanno sottratti tra loro come se fossero un benchmark.

## Verifiche locali

Il sorgente Mesa è stato scaricato con `scripts/prepare.sh`, verificando il
SHA-256 fissato in `upstream.json` e applicando le patch ArmadaOS e le patch
0001/0002. La nuova patch si applica senza fuzz e riproduce byte per byte i due
file sorgente usati nei test.

Sono stati compilati `nir_tests` e `spirv2nir` su x86_64 con asserzioni abilitate.
Questo verifica il compilatore e il suo IR; la build ARM64 del driver e la
correttezza visiva sul Retroid appartengono alla successiva prova sul dispositivo.

| Verifica | Esito |
| --- | --- |
| Quattro casi che richiedono la nuova ottimizzazione, prima della patch | Falliscono come previsto: il controllo resta |
| Altri otto casi specifici, prima della patch | Passano |
| Dodici casi specifici e test semantico generato, dopo la patch | 13/13 passano |
| Suite NIR completa dopo la patch | 6.193 test attivi passano; 10 test erano disabilitati nella suite |
| Sintassi degli script e dei blocchi shell del nuovo workflow | Verificata |

I test comprendono scalari, vettori, swizzle, confronto commutato e vincoli
strict. I casi negativi verificano che la regola non scatti su prodotti con
operandi diversi, confronto su un altro valore, ramo `-0.0`, swizzle differenti,
FP16 e FP64. Il test numerico usa 28 pattern di bit, comprese le due forme di
zero, subnormali, infiniti e NaN, con arrotondamento RTE/RTZ e denormal preserve/FTZ.

Per ripetere il controllo mirato in una build con `-Dbuild-tests=true`:

```sh
ninja -C work/mesa/build src/compiler/nir/nir_tests
work/mesa/build/src/compiler/nir/nir_tests \
  --gtest_filter='nir_opt_algebraic_zero_square_test.*:nir_opt_algebraic_pattern_test.bcsel_feq_fmul*'
```

### Confronto sui 1.105 shader originali

Sono stati conservati due eseguibili del convertitore, prima e dopo la sola
regola algebrica, e confrontati i risultati di `spirv2nir --optimize`.

| Misura nell'intero insieme di shader | Prima | Dopo |
| --- | ---: | ---: |
| Moduli convertiti e validati | 1.105 | 1.105 |
| Moduli con lo schema ridondante | 930 | 0 |
| Schemi diretti FP32 dopo le ottimizzazioni NIR | 22.578 | 0 |
| Nuovi errori di conversione/validazione | — | 0 |

Scompaiono 22.578 selezioni `bcsel` e 22.358 confronti `feq`, per un totale di
44.936 definizioni SSA NIR. Alcuni confronti rimangono perché hanno altri
utilizzatori. I conteggi misurati di moltiplicazioni, moltiplicazioni/somme e
minimi rimangono invariati in ciascun modulo. Nessun modulo aumenta il numero
totale di definizioni SSA.

| Shader campione | Schemi prima | Dopo | Definizioni SSA eliminate |
| --- | ---: | ---: | ---: |
| `a138dcff30eecee7` — FRAG | 62 | 0 | 123 |
| `d079c41a33bd1ff8` — FRAG | 46 | 0 | 92 |
| `045ac157484d48ca` — VERT | 18 | 0 | 36 |
| `ebd62f5976f5fab5` — VERT | 80 | 0 | 160 |
| `08a12292216836fd` — FRAG | 69 | 0 | 137 |
| `6ce98310bacd770a` — FRAG | 58 | 0 | 116 |

Dettaglio del metodo: 1.103 moduli passano nel convertitore standard. Gli altri
due richiedono `phys_ssbo_addr_format = nir_address_format_64bit_global`, lo
stesso formato dei puntatori fisici usato da Turnip. Per questi due moduli
sono stati compilati convertitori temporanei con quell'impostazione identica
in entrambe le varianti. Entrambi passano: `2496b0846f7b3a0f` resta invariato,
mentre `e7fb07519533db06` perde 12 selezioni e 12 confronti. La modifica al
convertitore è stata poi rimossa e non appartiene alla patch del driver.

Questi risultati provano che la regola si applica agli shader reali. Sono
conteggi statici nel NIR generico, non istruzioni native risparmiate per frame:
lo scheduling, i registri e il costo effettivo richiedono la prova Turnip.

## Costruire i due driver

Il workflow **IR3 square A/B** usa il runner ARM64 e Fedora 44 già scelti dalla
repository. Si avvia automaticamente con un push al branch
`experiment/ir3-guarded-squares`; è disponibile anche `workflow_dispatch`
quando il file del workflow è sul branch predefinito.

Per applicare il file di modifiche consegnato alla repository, puoi usare una
copia dedicata. I comandi seguenti assumono che il file scaricato sia in
`~/Downloads`:

```sh
git clone https://github.com/Ken5998/azimuth-arm64.git azimuth-arm64-ir3-test
cd azimuth-arm64-ir3-test
git switch -c experiment/ir3-guarded-squares
git apply --check --whitespace=nowarn ~/Downloads/azimuth-ir3-square-experiment.patch
git apply --whitespace=nowarn ~/Downloads/azimuth-ir3-square-experiment.patch
git add README.md docs/ir3-guarded-squares.md patches/0003-nir-remove-redundant-zero-guards-from-squares.patch scripts/install-ir3-variant.sh .github/workflows/ir3-square-ab.yml
git commit -m "nir: optimize guarded FP32 squares and add A/B workflow"
git push -u origin experiment/ir3-guarded-squares
```

Il push avvia il workflow sul branch sperimentale. La soppressione degli
avvisi sugli spazi riguarda i prefissi di contesto del file patch Mesa
contenuto nella modifica; i sorgenti modificati sono stati controllati.

La matrice produce:

| Artifact GitHub | Patch presenti | Directory di installazione |
| --- | --- | --- |
| `azimuth-turnip-ir3-baseline` | 0001, 0002 | `azimuth-ir3-baseline` |
| `azimuth-turnip-ir3-squares` | 0001, 0002, 0003 | `azimuth-ir3-squares` |

Entrambe le varianti applicano anche le stesse patch ArmadaOS fissate in
`upstream.json`. Lo script di build deriva già l'identificativo delle cache
dagli input, quindi le due varianti ottengono identificativi differenti.
Il workflow esegue i 13 test mirati sul runner ARM64 per la variante modificata.
Il driver release viene copiato nel pacchetto prima della riconfigurazione
per i test con asserzioni.

Ogni archivio include `comparison.json`, con variante, commit della repository,
revisioni upstream, elenco delle patch e SHA-256 del driver. Il workflow
genera artifact scaricabili, senza creare una release. Il workflow è stato
revisionato e controllato localmente; la sua esecuzione su GitHub Actions resta
da effettuare nella repository.

### Installazione sul Retroid

Scarica i due artifact dalla stessa esecuzione **IR3 square A/B** e apri i
contenitori ZIP di GitHub per ottenere i due `.tar.gz`. Con la versione
attuale `0.1.0`, dalla directory della repository esegui:

```sh
scripts/install-ir3-variant.sh baseline ~/Downloads/azimuth-turnip-0.1.0-ir3-baseline.tar.gz
scripts/install-ir3-variant.sh squares ~/Downloads/azimuth-turnip-0.1.0-ir3-squares.tar.gz
```

Adatta la cartella di download se necessario. Lo script verifica identità e
hash, poi crea i due manifest Vulkan nelle rispettive directory sotto
`~/.local/share/armada/turnip/`.

### Opzioni Steam: baseline

La riga elimina le variabili della cattura precedente e riabilita il normale
uso delle cache. Mantiene il wrapper già utilizzato; LSFG va lasciato spento
nella sua configurazione.

```text
VK_DRIVER_FILES=/var/home/armada/.local/share/armada/turnip/azimuth-ir3-baseline/icd.json VK_ICD_FILENAMES=/var/home/armada/.local/share/armada/turnip/azimuth-ir3-baseline/icd.json /usr/libexec/armada/armada-game-launch /usr/bin/env -u IR3_SHADER_DEBUG -u MESA_SHADER_CACHE_DISABLE -u VKD3D_CONFIG -u MESA_GPU_TRACES -u MESA_GPU_TRACEFILE -u VKD3D_SHADER_DUMP_PATH -u MESA_LOG_FILE -u MESA_LOG_FILE_AUTO PROTON_LOG=0 WINEDEBUG=-all TU_AUTOTUNE_ALGO=prefer_sysmem /var/home/armada/lsfg %command%
```

### Opzioni Steam: squares

```text
VK_DRIVER_FILES=/var/home/armada/.local/share/armada/turnip/azimuth-ir3-squares/icd.json VK_ICD_FILENAMES=/var/home/armada/.local/share/armada/turnip/azimuth-ir3-squares/icd.json /usr/libexec/armada/armada-game-launch /usr/bin/env -u IR3_SHADER_DEBUG -u MESA_SHADER_CACHE_DISABLE -u VKD3D_CONFIG -u MESA_GPU_TRACES -u MESA_GPU_TRACEFILE -u VKD3D_SHADER_DUMP_PATH -u MESA_LOG_FILE -u MESA_LOG_FILE_AUTO PROTON_LOG=0 WINEDEBUG=-all TU_AUTOTUNE_ALGO=prefer_sysmem /var/home/armada/lsfg %command%
```

## Misura sul dispositivo

Usa Azimuth 0.9.10, lo stesso Proton Experimental ARM64, FEX Fast, modalità
Balanced, risoluzione 1280x720 e gli stessi dettagli grafici. Per la misura
evita un limite a 20/25 FPS che possa nascondere un miglioramento. Usa la stessa
impostazione di frame pacing per entrambe le varianti, preferibilmente
Real-time come indicato nella guida della repository.

Fai completare la preparazione delle pipeline e un passaggio di riscaldamento
per ciascun driver. Poi alterna le varianti sulla stessa scena o sullo stesso
tratto di gara. Tre misure brevi per variante aiutano a distinguere un piccolo
cambiamento dal rumore. Annota gli FPS, la regolarità e gli eventuali difetti
visivi; tempi del frame e statistiche già disponibili nell'overlay sono utili.

| Variante | Prova 1 | Prova 2 | Prova 3 | Regolarità / difetti |
| --- | --- | --- | --- | --- |
| baseline | | | | |
| squares | | | | |

Non serve un'altra cattura completa da quasi 1 GB per questo primo confronto.
Se il miglioramento è ripetibile, il passo successivo è controllare che il
codice nativo modificato abbia effettivamente meno istruzioni o un'allocazione
più favorevole. Se resta nel rumore delle prove, questa piccola ottimizzazione
da sola non spiega il limite complessivo a 20–24 FPS: gli altri schemi numerici
e i costi GPU/CPU devono essere valutati con le misure già raccolte.

## Riferimenti del codice

- [Repository azimuth-arm64](https://github.com/Ken5998/azimuth-arm64), base locale `7625a4a2a1d342ec96b3fd8952880e43a731d768`.
- [Mesa al commit c126: regole NIR](https://gitlab.freedesktop.org/mesa/mesa/-/blob/c126acd85a645728bcecaa164d7d7c928438e842/src/compiler/nir/nir_opt_algebraic.py).
- [Mesa al commit c126: matcher NIR](https://gitlab.freedesktop.org/mesa/mesa/-/blob/c126acd85a645728bcecaa164d7d7c928438e842/src/compiler/nir/nir_search.c).
- [Mesa al commit c126: statistiche IR3](https://gitlab.freedesktop.org/mesa/mesa/-/blob/c126acd85a645728bcecaa164d7d7c928438e842/src/freedreno/ir3/ir3.c).
- [Mesa al commit c126: opzioni SPIR-V di Turnip](https://gitlab.freedesktop.org/mesa/mesa/-/blob/c126acd85a645728bcecaa164d7d7c928438e842/src/freedreno/vulkan/tu_shader.cc).
- [Eventi GitHub Actions](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows).

I risultati numerici derivano dalle catture fornite e dalle verifiche locali
descritte sopra. Le statistiche di compilazione non sono misure di utilizzo
della GPU né previsioni di FPS.
