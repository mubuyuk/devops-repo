# Azure CLI & Bicep – Kommandosamling

Kommandona för att arbeta med Azure, Bicep och GitHub i det här projektet.

Kommandona är skrivna för **Git Bash** och körs från projektets rotmapp (`devops-repo`).

**Innehåll**

1. [Inloggning och prenumeration](#1-inloggning-och-prenumeration)
2. [Pipelinens identitet (`identity.bicep`)](#2-pipelinens-identitet-identitybicep)
3. [Container registry och image](#3-container-registry-och-image)
4. [Container Apps (`main-container-apps.bicep`)](#4-container-apps-main-container-appsbicep)
5. [Revisioner, trafikdelning och rollback](#5-revisioner-trafikdelning-och-rollback)
6. [Pipelines](#6-pipelines)
7. [App Service (`main.bicep`)](#7-app-service-mainbicep)
8. [Städa efter dig](#8-städa-efter-dig)
9. [Vanliga fel](#9-vanliga-fel)

---

## ⭐ Börja här: varje gång du öppnar ett nytt terminalfönster

Ett nytt fönster minns ingenting från förra gången. Klistra in de här två raderna först:

```bash
source scripts/variables.sh
export MSYS_NO_PATHCONV=1
```

| Rad | Vad den gör |
|---|---|
| `source scripts/variables.sh` | Lägger dina namn (resursgrupp, identitet, registry med flera) i variabler och skriver ut dem. Står något tomt i listan är något fel i `scripts/variables.sh`. |
| `export MSYS_NO_PATHCONV=1` | Hindrar Git Bash på Windows från att ändra sökvägar som börjar med `/`. Annars kan Azure svara med fel som `MissingSubscription`. |

> **Varför `source`?** Utan `source` körs skriptet i en tillfällig terminal som stängs direkt, och variablerna försvinner med den. Med `source` hamnar de i *din* terminal.

> **Viktigt:** en tom variabel ger ofta missvisande fel. Till exempel svarar Azure med `AuthorizationFailed` om `$RESOURCE_GROUP` är tom. Ser ett fel konstigt ut, kör `echo` på variablerna först.

Variabler som du sätter själv senare (`REGISTRY`, `IMAGE_TAG`, `CA_URL` med flera) finns också bara i fönstret där du satte dem.

---

## 1. Inloggning och prenumeration

Inloggningen sparas på datorn. `az login` behövs bara första gången, eller om du har blivit utloggad.

```bash
az login
```

| Vad | Kommando |
|---|---|
| Visa aktiv prenumeration | `az account show --query name --output tsv` |
| Lista alla prenumerationer | `az account list --output table` |
| Byt prenumeration | `az account set --subscription "Molnutveckling med Azure"` |
| Lista resurser i din grupp | `az resource list --resource-group "$RESOURCE_GROUP" --output table` |

I listan är `IsDefault` `True` på den aktiva prenumerationen, alltså den som alla `az`-kommandon körs mot. Ett byte gäller även i nya fönster. En inloggning räcker för alla prenumerationer ditt konto har tillgång till.

---

## 2. Pipelinens identitet (`identity.bicep`)

Identiteten `id-waypoint-pipeline-murat` är pipelinens **passerkort** till Azure. Den har rollen **Contributor** på resursgruppen (via `infra/modules/contributor-role.bicep`).

> **Görs en gång.** Identiteten finns kvar i Azure och kostar ingenting. Gör om stegen bara om den har tagits bort, om du byter prenumeration eller om du byter repo.

### Hämta GitHub-prefixet

Det är början på "adressen" som GitHub använder när pipelinen loggar in:

```bash
SUBJECT_PREFIX=$(gh api "repos/{owner}/{repo}/actions/oidc/customization/sub" --jq .sub_claim_prefix)
echo "$SUBJECT_PREFIX"
```

Det ska se ut ungefär så här: `repo:mubuyuk@179019714/devops-repo@1411913961`.

### Förhandsgranska och skapa

```bash
# Förhandsgranska. Ändrar ingenting.
az deployment group what-if \
  --resource-group "$RESOURCE_GROUP" \
  --template-file infra/identity.bicep \
  --parameters identityName="$IDENTITY_NAME" subjectPrefix="$SUBJECT_PREFIX"

# Skapa på riktigt. Skriver ut identitetens clientId.
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file infra/identity.bicep \
  --parameters identityName="$IDENTITY_NAME" subjectPrefix="$SUBJECT_PREFIX" \
  --query properties.outputs.clientId.value \
  --output tsv
```

Vänta en halv minut innan nästa steg.

### Ge GitHub inloggningsuppgifterna

```bash
CLIENT_ID=$(az deployment group show --resource-group "$RESOURCE_GROUP" --name identity --query properties.outputs.clientId.value --output tsv)
TENANT_ID=$(az account show --query tenantId --output tsv)
SUBSCRIPTION_ID=$(az account show --query id --output tsv)

gh secret set AZURE_CLIENT_ID --body "$CLIENT_ID"
gh secret set AZURE_TENANT_ID --body "$TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID"
```

Varje `gh secret set` ska skriva ut `✓ Set Actions secret ...`.

### Kontrollera

```bash
# Hemligheterna i GitHub (värdena visas aldrig)
gh secret list

# Vilket repo och vilken gren som får använda identiteten.
# Ska vara ditt SUBJECT_PREFIX följt av :ref:refs/heads/main
az identity federated-credential list \
  --identity-name "$IDENTITY_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "[].subject" \
  --output tsv
```

---

## 3. Container registry och image

Ett **registry** är ett lager för images, ungefär som GitHub är för kod. En **image** är appen färdigpackad med Node och alla paket, byggd enligt `Dockerfile`. Taggen är commitens korta id, så att du alltid ser vilken kod en image kommer från.

Registryt `crwaypointmurat` skapas av Bicep, antingen av `main-container-apps.bicep` (avsnitt 4) eller av `main.bicep` (avsnitt 7).

### Roller: vem får göra vad?

| Identitet | Används av | Roll | Scope |
|---|---|---|---|
| `id-waypoint-pipeline-murat` | GitHub Actions | **Contributor** | resursgruppen, skapar resurser |
| `id-waypoint-pipeline-murat` | GitHub Actions | **AcrPush** | registryt, pushar images |
| `id-waypoint-murat` | Container Appen | **AcrPull** | registryt, hämtar images |

AcrPush och AcrPull ges **för hand**, inte i Bicep. Pipelinen har bara Contributor, och Contributor får inte dela ut roller.

> ⚠️ **AcrPush och AcrPull försvinner när registryt tas bort**, eftersom de sitter på just det registryt. När registryt har skapats igen måste rollerna ges på nytt.

### Hitta registryt

```bash
REGISTRY=$(az acr list --resource-group "$RESOURCE_GROUP" --query "[0].loginServer" --output tsv)
echo "$REGISTRY"
```

Det ska skriva ut `crwaypointmurat.azurecr.io`. Är raden tom finns inget registry i gruppen.

### Ge pipelinen AcrPush

```bash
PRINCIPAL_ID=$(az identity show --name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" --query principalId --output tsv)
REGISTRY_ID=$(az acr show --name "$REGISTRY_NAME" --query id --output tsv)

az role assignment create \
  --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role AcrPush \
  --scope "$REGISTRY_ID" \
  --output none
```

AcrPull för Container Appens identitet finns i [avsnitt 4, steg 2](#steg-2-ge-rollerna).

### Visa en identitets roller

```bash
az role assignment list \
  --assignee "$PRINCIPAL_ID" \
  --all \
  --query "[].{role:roleDefinitionName, scope:scope}" \
  --output table
```

Syns inte en ny roll direkt? Vänta en halv minut och kör igen. Skapa den inte en gång till.

### Bygg en image i Azure och lägg den i registryt

Bygget sker i Azure, så du behöver inte ha Docker installerat. Committa först (`git status --short` ska vara tomt), så att taggen stämmer med koden.

```bash
TAG=$(git rev-parse --short HEAD)

az acr build \
  --registry "$REGISTRY_NAME" \
  --image "waypoint:$TAG" \
  --platform linux/amd64 \
  --build-arg COMMIT=$(git rev-parse HEAD) \
  .
```

Glöm inte punkten sist, som betyder "bygg från den här mappen". Bygget tar ungefär en minut och slutar med `Run ID: ... was successful`.

### Visa images i registryt

```bash
az acr repository show-tags --name "$REGISTRY_NAME" --repository waypoint --output table
```

---

## 4. Container Apps (`main-container-apps.bicep`)

Mallen `infra/main-container-apps.bicep` med parameterfilen `infra/container-apps.bicepparam` skapar registryt, pull-identiteten `id-waypoint-murat`, miljön `cae-waypoint-murat` och appen `ca-waypoint-murat`.

> Normalt sköter pipelinen allt detta vid varje push (avsnitt 6). Stegen nedan behövs när allt har städats bort och ska byggas upp igen.

**Ordningen spelar roll:** appen kan inte starta förrän pull-identiteten har AcrPull och det finns en image i registryt. Men rollerna kan inte ges förrän registryt finns. Därför går det till så här:

| Steg | Vad | Resultat |
|---|---|---|
| 1 | Kör mallen | Registry, identitet och miljö skapas. **Appen blir röd**, och det är väntat. |
| 2 | Ge AcrPush och AcrPull | Rollerna finns på det nya registryt. |
| 3 | Starta pipelinen | Den bygger imagen, pushar den och skapar appen. |
| 4 | Hälsokontroll | Appen svarar. |

### Steg 1: Kör mallen (appen blir röd)

```bash
export IMAGE_TAG=$(git rev-parse --short HEAD)
DEPLOYMENT_NAME=main-container-apps

az deployment group create \
  --name "$DEPLOYMENT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --template-file infra/main-container-apps.bicep \
  --parameters infra/container-apps.bicepparam \
  --query properties.provisioningState \
  --output tsv
```

Det väntade felet är ungefär *Failed to provision revision ... unable to pull image using Managed identity*. Registryt är tomt och har ännu inga roller.

### Steg 2: Ge rollerna

**AcrPush** för pipelinen: se [avsnitt 3](#ge-pipelinen-acrpush). **AcrPull** för appens identitet:

```bash
PULL_PRINCIPAL_ID=$(az identity show --name "id-waypoint-$NAME" --resource-group "$RESOURCE_GROUP" --query principalId --output tsv)
REGISTRY_ID=$(az acr show --name "$REGISTRY_NAME" --query id --output tsv)

az role assignment create \
  --assignee-object-id "$PULL_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role AcrPull \
  --scope "$REGISTRY_ID" \
  --output none
```

Kontrollera båda med "Visa en identitets roller" i avsnitt 3. Vänta 2–3 minuter innan nästa steg, så att rollerna hinner börja gälla.

### Steg 3: Låt pipelinen bygga och skapa appen

```bash
gh workflow run deploy-container-app-pipeline.yml
```

Följ körningen enligt avsnitt 6. Byt `--commit ...` mot `--limit 1`, eftersom körningen inte startades av en push.

**Utan pipeline, för hand:** bygg imagen med `az acr build` (avsnitt 3) och kör sedan mallen från steg 1 igen, med `--query properties.outputs.containerAppUrl.value`. `export` behövs eftersom `readEnvironmentVariable('IMAGE_TAG')` bara ser exporterade variabler. Första gången tar det **3–15 minuter**, så avbryt inte.

### Steg 4: Kontrollera att appen svarar med rätt version

```bash
CA_NAME="ca-waypoint-$NAME"
CA_URL=$(az deployment group show \
  --name main-container-apps \
  --resource-group "$RESOURCE_GROUP" \
  --query properties.outputs.containerAppUrl.value \
  --output tsv)

ATTEMPTS=30 ./scripts/health-check.sh "$CA_URL/health" "$(git rev-parse "$IMAGE_TAG")"
```

Det ska sluta med `OK: the app answered 200 on attempt ...`. `ATTEMPTS=30` ger appen tid för en kallstart, eftersom `minReplicas: 0` gör att den stängs av när ingen använder den.

### Felsök: vad hände när appen startade?

```bash
az containerapp logs show \
  --name "ca-waypoint-$NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --type system \
  --tail 20
```

Titta på `Reason` för den nyaste revisionen. `PulledImage` och `ContainerStarted` betyder att allt gick bra. Ett fel om *pull* betyder oftast att AcrPull saknas, eller att imagen inte finns.

---

## 5. Revisioner, trafikdelning och rollback

En **revision** är en ögonblicksbild av appen: en viss image med vissa inställningar. Varje ny image ger en ny revision. Den gamla finns kvar, så du kan skicka trafik till den igen på några sekunder.

**Kräver:** `CA_NAME` och `CA_URL` från avsnitt 4, steg 4.

### Lista revisionerna

```bash
az containerapp revision list \
  --name "$CA_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "[].{name:name, state:properties.runningState, traffic:properties.trafficWeight, image:properties.template.containers[0].image}" \
  --output table
```

`ScaledToZero` betyder att revisionen är aktiv men inte har några kopior igång just nu. Den startar när den får trafik.

### Välj den förra och den nyaste

```bash
OLD_REVISION=$(az containerapp revision list --name "$CA_NAME" --resource-group "$RESOURCE_GROUP" --query "[-2].name" --output tsv)
NEW_REVISION=$(az containerapp revision list --name "$CA_NAME" --resource-group "$RESOURCE_GROUP" --query "[-1].name" --output tsv)
echo "$OLD_REVISION $NEW_REVISION"
```

`[-1]` är den sista revisionen i listan, alltså den nyaste. `[-2]` är den näst sista.

### Dela trafiken (canary)

```bash
az containerapp ingress traffic set \
  --name "$CA_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --revision-weight "$OLD_REVISION=50" "$NEW_REVISION=50" \
  --output table
```

Andelarna måste bli 100 tillsammans.

### Rollback: all trafik till den förra

```bash
az containerapp ingress traffic set \
  --name "$CA_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --revision-weight "$OLD_REVISION=100" "$NEW_REVISION=0" \
  --output table
```

### Räkna vilken version som svarar

```bash
for attempt in $(seq 1 20); do
  curl -s "$CA_URL/health" | grep -o '"version": "[^"]*"'
done | sort | uniq -c
```

Exempel efter 50/50: `9 "version": "1.0.0"` och `11 "version": "1.1.0"`. Efter rollback: `20 "version": "1.0.0"`.

> **Obs:** nästa push återställer trafiken till 100 % på den nyaste revisionen, eftersom mallen har `latestRevision: true`. Rollback är en snabb nödåtgärd. Den riktiga lösningen är att rätta koden och pusha.

---

## 6. Pipelines

| Pipeline | Startar vid push? | Gör |
|---|---|---|
| `build-test-pipeline.yml` | Ja, och vid pull requests | Bygger och testar. Skapar inget i Azure. |
| `deploy-container-app-pipeline.yml` | **Ja** | Bygger en image, pushar den, kör `main-container-apps.bicep` och testar den nya revisionen. |
| `infra-deploy-pipeline.yml` | Nej, `push` är bortkommenterad | Kör `main.bicep` och deployar till App Service. Startas bara för hand. |

Pushar du bara dokumentation (`.md`-filer eller `docs/`) startar ingen av deploy-pipelines.

> ⚠️ Finns inget registry i gruppen (till exempel efter städning) blir `deploy-container-app-pipeline.yml` röd med `No registry found in the resource group`. Det är ofarligt, eftersom ingenting skapas. Bygg upp registryt igen först (avsnitt 4).

### Följ körningen för din senaste commit

Vänta några sekunder efter `git push`, så att GitHub hinner starta körningen:

```bash
RUN_ID=$(gh run list \
  --workflow deploy-container-app-pipeline.yml \
  --commit "$(git rev-parse HEAD)" \
  --limit 1 \
  --json databaseId \
  --jq '.[0].databaseId')

gh run watch "$RUN_ID"
```

Är `RUN_ID` tom har körningen inte startat än. Vänta och kör igen. Byt filnamnet efter `--workflow` för att följa en annan pipeline.

### Övriga kommandon

| Vad | Kommando |
|---|---|
| De senaste körningarna (✓ lyckad, X misslyckad, * pågår) | `gh run list --limit 5` |
| Loggen från de steg som misslyckades | `gh run view "$RUN_ID" --log-failed` |
| Kör om bara de misslyckade jobben | `gh run rerun "$RUN_ID" --failed` |
| Öppna körningen i webbläsaren | `gh run view "$RUN_ID" --web` |
| Starta en pipeline utan att pusha | `gh workflow run deploy-container-app-pipeline.yml` |

---

## 7. App Service (`main.bicep`)

Från modulerna 4–8. Mallen `infra/main.bicep` med `infra/dev.bicepparam` skapar registry, App Service-plan (P0v3), webbapp, Log Analytics-workspace och larm. Den körs inte längre vid push, bara för hand.

**Kräver** att `ALERT_EMAIL` är satt, eftersom parameterfilen läser den med `readEnvironmentVariable`:

```bash
export ALERT_EMAIL="din@epost.se"
```

### Förhandsgranska och skapa

```bash
# Kontrollera syntaxen
az bicep build --file infra/main.bicep

# Förhandsgranska. Ändrar ingenting.
az deployment group what-if \
  --resource-group "$RESOURCE_GROUP" \
  --template-file infra/main.bicep \
  --parameters infra/dev.bicepparam

# Skapa på riktigt. Skriver ut appens adress.
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file infra/main.bicep \
  --parameters infra/dev.bicepparam \
  --query properties.outputs.appServiceUrl.value \
  --output tsv
```

Du kan också köra pipelinen i stället: `gh workflow run infra-deploy-pipeline.yml`. Den hämtar `ALERT_EMAIL` från GitHub-variabeln med samma namn.

### Kontrollera att appen svarar

```bash
./scripts/health-check.sh "https://$APP_NAME.azurewebsites.net/health"
```

---

## 8. Städa efter dig

Registryt och App Service-planen kostar pengar så länge de finns, även när ingen använder dem. Container Appen kostar nästan ingenting när den är nedskalad till noll. Ta bort allt när du är klar för dagen, eftersom allt kan byggas upp igen från koden.

> 🛑 **Det här tar du INTE bort:**
> - **Resursgruppen** `MuratBuyuksal`. Skolan har skapat den, och den ska stå kvar hela kursen.
> - **Identiteterna** `id-waypoint-pipeline-murat` och `id-waypoint-murat`. De kostar ingenting.
> - **Hemligheterna och variablerna i GitHub.**

### Container Apps

```bash
az containerapp delete --name "ca-waypoint-$NAME" --resource-group "$RESOURCE_GROUP" --yes
az containerapp env delete --name "cae-waypoint-$NAME" --resource-group "$RESOURCE_GROUP" --yes
```

Ta bort appen före miljön. Miljön är långsammast: det kan ta **20 minuter eller mer** medan den står som `ScheduledForDelete`. Avbryt inte. Följ förloppet i ett annat fönster:

```bash
az containerapp env show --name "cae-waypoint-$NAME" --resource-group "$RESOURCE_GROUP" --query properties.provisioningState --output tsv
```

`ResourceNotFound` betyder att miljön är borta. I portalen ser du förloppet under resursgruppen → **Activity log**.

### Registryt

Images, AcrPush och AcrPull försvinner tillsammans med registryt. Registryt behöver inte vänta på miljön.

```bash
az acr delete --name "$REGISTRY_NAME" --resource-group "$RESOURCE_GROUP" --yes
```

### App Service (om den finns)

```bash
az webapp delete --name "$APP_NAME" --resource-group "$RESOURCE_GROUP"

# Står planen kvar efter en minut:
az appservice plan delete --name "$PLAN_NAME" --resource-group "$RESOURCE_GROUP" --yes
```

Workspace och larm från modul 8 tar du bort i portalen, eller med `az resource delete`.

### Kontrollera

```bash
az resource list --resource-group "$RESOURCE_GROUP" --output table
```

Bara de två identiteterna ska stå kvar.

---

## 9. Vanliga fel

| Felmeddelande | Orsak | Lösning |
|---|---|---|
| `AuthorizationFailed` med `.../resourcegroups/providers/...` i scope | `$RESOURCE_GROUP` är tom, eftersom du har öppnat ett nytt fönster. Den långa `Traceback`-texten är en bugg i Azure CLI. | Kör raderna i "Börja här". |
| `The name property cannot be null or empty` | En variabel är tom, oftast `IDENTITY_NAME`. | Kör `source scripts/variables.sh`. |
| `MissingSubscription` | Git Bash har ändrat en sökväg. | Kör `export MSYS_NO_PATHCONV=1`. |
| Bicep klagar på `IMAGE_TAG` eller `ALERT_EMAIL` | Variabeln är inte satt, eller inte `export`-ad. | `export IMAGE_TAG=...` respektive `export ALERT_EMAIL=...`. |
| `BCP258 ... missing an assignment in the params file` | Mallen har en parameter som parameterfilen saknar, eller filen är inte sparad. | Lägg till raden i `.bicepparam` och spara. |
| `No registry found in the resource group` i pipelinen | Registryt är borttaget. | Bygg upp det igen (avsnitt 4) och ge AcrPush och AcrPull. |
| Appen startar inte: *unable to pull image* | AcrPull saknas, eller imagen med den taggen finns inte. | Avsnitt 4, steg 2, och `az acr repository show-tags`. |
| `ManagedEnvironmentCapacityHeavyUsageError` | Container Apps är fullt i regionen. | Ta bort miljön, lägg till `param containerAppsLocation = 'northeurope'` sist i `container-apps.bicepparam` och kör igen. |
| Miljön står som `ScheduledForDelete` länge | Borttagningen pågår, och miljön är långsam. | Vänta. Kontrollera **Activity log**. Kör inte `delete` igen. |
| `ResourceNotFound` på `az acr show` | Registryt finns inte. | Skapa det (avsnitt 4 eller 7). |
| `AADSTS700016: Application ... was not found` | `AZURE_CLIENT_ID` i GitHub pekar på en identitet som inte finns längre. | Avsnitt 2: skapa identiteten och ge GitHub uppgifterna. |
| `AuthorizationFailed` / `No subscriptions found` i pipelinen | En ny roll har inte hunnit börja gälla. | Vänta 2–3 minuter, sedan `gh run rerun "$RUN_ID" --failed`. |
| `RoleAssignmentExists` | Rollen finns redan, kanske under ett annat namn. | Visa rollerna (avsnitt 3). Ta bort den gamla med `az role assignment delete --ids <id>`, där id:t hämtas med `--query "[].id"`. |
| `No available instances` (App Service) | Ingen kapacitet för planens nivå i regionen. | Byt `planSku` i `dev.bicepparam`, till exempel till `P0v3`. |
