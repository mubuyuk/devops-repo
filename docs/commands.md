# Azure CLI & Bicep – Kommandosamling

En samling kommandon för att arbeta med Azure och Bicep i det här projektet.

Kommandona är anpassade för **Git Bash** och körs från projektets rotmapp (`devops-repo`).

---

## ⭐ Börja här: varje gång du öppnar ett nytt terminalfönster

Ett nytt fönster minns ingenting från förra gången. Kopiera de här två raderna och klistra in dem först:

```bash
source scripts/variables.sh
export MSYS_NO_PATHCONV=1
```

| Rad | Vad den gör |
|---|---|
| `source scripts/variables.sh` | Lägger in dina namn (namn, resursgrupp, plan, app, identitet, registry, workspace) i variabler. |
| `export MSYS_NO_PATHCONV=1` | Hindrar Git Bash på Windows från att ändra sökvägar som börjar med `/`. Annars kan Azure svara med fel som `MissingSubscription`. |

Efter `source` ska du se en lista med dina värden. Står det något tomt där, är något fel i `scripts/variables.sh`.

> **Viktigt:** en tom variabel ger ofta missvisande fel. Exempel: är `$RESOURCE_GROUP` tom svarar Azure med `AuthorizationFailed`, och i felets *scope* saknas gruppens namn (`.../resourcegroups/providers/...`). Kör `echo` på variablerna om ett fel ser konstigt ut.

> **Varför `source` och inte bara `./scripts/variables.sh`?**
> Utan `source` körs skriptet i en tillfällig terminal som stängs direkt, och variablerna försvinner med den. Med `source` hamnar de i *din* terminal.

---

## 1. Azure – Inloggning

Inloggningen sparas på datorn. Du behöver bara göra detta första gången, eller om du blivit utloggad.

### Logga in i Azure

```bash
az login
```

### Visa aktiv prenumeration

```bash
az account show --output table
```

### Lista alla prenumerationer du har tillgång till

```bash
az account list --output table
```

`IsDefault` är `True` på den som är aktiv, alltså den som alla `az`-kommandon körs mot.

### Byt aktiv prenumeration

```bash
az account set --subscription "<namn eller id>"
```

Exempel: `az account set --subscription "Molnutveckling med Azure"`. Ingen utskrift betyder att det gick bra. Kontrollera med `az account show --query name --output tsv`.

Du behöver inte köra `az login` igen: en inloggning ger tillgång till alla prenumerationer ditt konto har behörighet till. Bytet sparas på datorn och gäller även i nya terminalfönster.

---

## 2. Miljövariabler

### Kontrollera att variablerna är satta

```bash
echo "$NAME"
echo "$RESOURCE_GROUP"
echo "$PLAN_NAME"
echo "$APP_NAME"
echo "$IDENTITY_NAME"
echo "$REGISTRY_NAME"
echo "$WORKSPACE_NAME"
```

Är en rad tom? Kör raderna i "Börja här" igen.

### Hämta GitHub-prefixet (behövs för identity.bicep)

Hämtar början på den "adress" GitHub använder när pipelinen loggar in i Azure.

```bash
SUBJECT_PREFIX=$(gh api "repos/{owner}/{repo}/actions/oidc/customization/sub" --jq .sub_claim_prefix)
echo "$SUBJECT_PREFIX"
```

Det ska se ut ungefär så här (med dina egna nummer):

```
repo:mubuyuk@179019714/devops-repo@1411913961
```

---

## 3. Resource Groups

### Lista alla resursgrupper

```bash
az group list \
  --query "[].{Name:name, Location:location}" \
  --output table
```

### Lista resurser i din resursgrupp

```bash
az resource list \
  --resource-group "$RESOURCE_GROUP" \
  --output table
```

---

## 4. Bicep – Pipelinens identitet (`identity.bicep`)

Skapar identiteten som GitHub Actions loggar in som, och ger den rätt att ändra i resursgruppen. Tänk på den som pipelinens **passerkort** till Azure.

Sedan modul 7 ligger rollen (Contributor) i en egen modul, `infra/modules/contributor-role.bicep`, som `identity.bicep` anropar.

> **Görs en gång.** Identiteten finns kvar i Azure, och pipelinen använder den vid varje körning.
> Gör om stegen nedan bara om identiteten har tagits bort, eller om du byter repo.

**Kräver:** stegen i "Börja här" och `SUBJECT_PREFIX` från avsnitt 2.

### Förhandsgranska (what-if)

Visar vad som skulle skapas. Ändrar ingenting.

```bash
az deployment group what-if \
  --resource-group "$RESOURCE_GROUP" \
  --template-file infra/identity.bicep \
  --parameters identityName="$IDENTITY_NAME" subjectPrefix="$SUBJECT_PREFIX"
```

I modul 6, när identiteten inte fanns, var sista raden `Resource changes: 2 to create, 1 unsupported.` `1 unsupported` är normalt: det är rollen, som inte kan förhandsgranskas förrän identiteten finns. Efter modul 7, när rollen ligger i en modul och identiteten redan finns, kan raden se annorlunda ut.

### Om du får `RoleAssignmentExists`: ta bort den gamla rollen

Rollens namn räknas fram av Bicep. Ändras sättet det räknas på (som i modul 7) finns den gamla rollen kvar under sitt gamla namn, och Azure vägrar skapa en dubblett. Ta då bort pipelinens gamla roller och kör `create` igen:

```bash
for ROLE_ID in $(az role assignment list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?principalType=='ServicePrincipal'].id" \
  --output tsv | tr -d '\r'); do
  az role assignment delete --ids "$ROLE_ID"
done
```

Ingen utskrift betyder att det gick bra. `tr -d '\r'` behövs på Windows.

### Skapa på riktigt

**Observera:** Detta ändrar i Azure.

```bash
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file infra/identity.bicep \
  --parameters identityName="$IDENTITY_NAME" subjectPrefix="$SUBJECT_PREFIX" \
  --query properties.outputs.clientId.value \
  --output tsv
```

Samma kommando på en rad, om inklistringen krånglar:

```bash
az deployment group create --resource-group "$RESOURCE_GROUP" --template-file infra/identity.bicep --parameters identityName="$IDENTITY_NAME" subjectPrefix="$SUBJECT_PREFIX" --query properties.outputs.clientId.value --output tsv
```

Utskriften är identitetens `clientId`, kortets nummer (ett långt id som `b31b166f-...`). Vänta en halv minut innan nästa steg.

### Ge GitHub kortnumret

Hämtar de tre värdena pipelinen behöver för att logga in:

```bash
CLIENT_ID=$(az deployment group show --resource-group "$RESOURCE_GROUP" --name identity --query properties.outputs.clientId.value --output tsv)
TENANT_ID=$(az account show --query tenantId --output tsv)
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
echo "$CLIENT_ID"
```

`echo` ska skriva ut samma id som `create` gav. Spara sedan värdena som hemligheter i GitHub:

```bash
gh secret set AZURE_CLIENT_ID --body "$CLIENT_ID"
gh secret set AZURE_TENANT_ID --body "$TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID"
```

Varje rad ska skriva ut `✓ Set Actions secret ... for mubuyuk/devops-repo`.

### Kontrollera att allt är kopplat

Visar hemligheterna i GitHub och när de senast ändrades (värdena syns aldrig):

```bash
gh secret list
```

Visar vilket repo och vilken gren som får använda identiteten:

```bash
az identity federated-credential list --identity-name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" --query "[].subject" --output tsv
```

Det ska stå ditt `SUBJECT_PREFIX` följt av `:ref:refs/heads/main`.

---

## 5. Bicep – Plan, webbapp och registry (`main.bicep`)

Använder parameterfilen `infra/dev.bicepparam`, där namnen redan står. Sedan modul 7 skapar `main.bicep` även ett container registry (`infra/modules/container-registry.bicep`).

> Normalt behöver du inte köra `create` själv: pipelinen kör `main.bicep` vid varje push. Kommandona här är för att förhandsgranska eller felsöka.

### Kontrollera syntaxen

```bash
az bicep build --file infra/main.bicep
```

### Förhandsgranska (what-if)

```bash
az deployment group what-if \
  --resource-group "$RESOURCE_GROUP" \
  --template-file infra/main.bicep \
  --parameters infra/dev.bicepparam
```

När bara identiteten finns (efter städning) ska sista raden vara:

```
Resource changes: 3 to create, 1 to ignore.
```

De tre är registryt, planen och appen. `1 to ignore` är identiteten, som inte finns i `main.bicep` och därför lämnas orörd.

### Skapa på riktigt

**Observera:** Detta ändrar i Azure.

```bash
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file infra/main.bicep \
  --parameters infra/dev.bicepparam \
  --query properties.outputs.appServiceUrl.value \
  --output tsv
```

Utskriften är appens adress. Vänta en eller två minuter.

### Visa App Service Plan

```bash
az appservice plan show \
  --name "$PLAN_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --output table
```

---

## 6. Container registry och image (modul 7)

Ett **registry** är ett lager för images, som GitHub för kod. En **image** är appen färdigpackad med Node och alla paket, byggd enligt `Dockerfile`. Taggen är commitens korta id, så att du alltid ser vilken kod en image kommer från.

**Ordning:** registryt måste finnas (pipelinen skapar det vid en push), sedan rollen, sedan bygget.

### Kontrollera att registryt finns

```bash
az acr show --name "$REGISTRY_NAME" --query loginServer --output tsv
```

Ska skriva ut `crwaypointmurat.azurecr.io`. `ResourceNotFound` betyder att pipelinen inte har skapat det än, eller blev röd.

### Ge pipelinens identitet rätt att pusha images (AcrPush)

Görs **för hand**, inte i Bicep: pipelinen har bara Contributor, och Contributor får inte dela ut roller. Rollen ges bara på registryt, inte på hela gruppen.

```bash
PRINCIPAL_ID=$(az identity show \
  --name "$IDENTITY_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query principalId \
  --output tsv)
REGISTRY_ID=$(az acr show \
  --name "$REGISTRY_NAME" \
  --query id \
  --output tsv)

az role assignment create \
  --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role AcrPush \
  --scope "$REGISTRY_ID" \
  --output none
```

Ingen utskrift betyder att det gick bra.

### Visa identitetens roller

```bash
az role assignment list \
  --assignee "$PRINCIPAL_ID" \
  --all \
  --query "[].{role:roleDefinitionName, scope:scope}" \
  --output table
```

Två rader: **Contributor** på resursgruppen och **AcrPush** på registryt (scope slutar på `/registries/crwaypointmurat`).

### Bygg imagen och pusha den till registryt

Bygget sker i Azure, så Docker Desktop behövs inte. Kontrollera först att allt är committat (`git status --short` ska vara tomt), så att taggen stämmer med koden.

```bash
TAG=$(git rev-parse --short HEAD)
echo "$TAG"

az acr build \
  --registry "$REGISTRY_NAME" \
  --image "waypoint:$TAG" \
  --build-arg COMMIT=$(git rev-parse HEAD) \
  .
```

Glöm inte punkten sist (= bygg från den här mappen). Tar ungefär en minut och slutar med `Successfully pushed image: crwaypointmurat.azurecr.io/waypoint:<tagg>` och `Run ID: ... was successful`.

### Visa images i registryt

```bash
az acr repository show-tags \
  --name "$REGISTRY_NAME" \
  --repository waypoint \
  --output table
```

Visar taggarna, till exempel `7dbbf4f`.

---

## 7. Följ pipelinen

En push till `main` som ändrar kod startar `Infra and Deploy Pipeline`. Den bygger infrastrukturen och deployar sedan koden. Pushar du bara dokumentation (`.md`-filer eller `docs/`) startar den inte.

### Se de senaste körningarna

```bash
gh run list --limit 5
```

✓ betyder lyckad, X misslyckad och * pågår.

### Följ den senaste körningen live

Vänta ungefär 10 sekunder efter `git push`, annars ser du förra körningen.

```bash
LAST_RUN=$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$LAST_RUN"
```

En grön körning har tre jobb: **Infrastructure**, **Deploy App Service / Build and Test** och **Deploy App Service / Deploy**.

### Följ körningen för just din senaste commit

Säkrare än ovan, eftersom du aldrig råkar titta på en gammal körning:

```bash
gh run watch "$(gh run list \
  --workflow infra-deploy-pipeline.yml \
  --commit "$(git rev-parse HEAD)" \
  --limit 1 \
  --json databaseId \
  --jq '.[0].databaseId')"
```

### Kontrollera att appen svarar

```bash
./scripts/health-check.sh "https://$APP_NAME.azurewebsites.net/health"
```

Ska sluta med `OK: the app answered 200 on attempt ...`.

### Om något blev rött

Visa bara loggen från stegen som misslyckades:

```bash
gh run view "$LAST_RUN" --log-failed
```

Kör om bara de misslyckade jobben:

```bash
gh run rerun "$LAST_RUN" --failed
```

Röd med `AuthorizationFailed` eller `No subscriptions found` strax efter att identitetens roll ändrats? Rollen har inte hunnit börja gälla. Vänta 2–3 minuter och kör om de misslyckade jobben.

### Starta pipelinen utan att pusha

```bash
gh workflow run infra-deploy-pipeline.yml
```

### Öppna körningen i webbläsaren

```bash
gh run view "$LAST_RUN" --web
```

---

## 8. Städa efter dig

Planen (B1, ungefär 4 kr/dag) och registryt (Basic, ungefär 1,66 kr/dag) kostar pengar så länge de finns, även när ingen använder dem. Ta bort dem när du är klar för dagen. Allt kan byggas upp igen från koden.

> 🛑 **Det här tar du INTE bort:**
> - **Resursgruppen** `MuratBuyuksal` (prenumerationen "Molnutveckling med Azure"). Skolan har skapat den, och den ska stå kvar hela kursen.
> - **Identiteten** `id-waypoint-pipeline-murat`. Den kostar ingenting, och utan den kan pipelinen inte logga in.
> - **Hemligheterna i GitHub.**

### Ta bort appen (och planen)

```bash
az webapp delete --name "$APP_NAME" --resource-group "$RESOURCE_GROUP"
```

Ibland skrivs `Note: If this is the last app on the plan, the plan will also be deleted.` ut, ibland ingenting. Båda är okej.

### Ta bort registryt

Imagen i registryt försvinner också. Den kan byggas igen med `az acr build` (avsnitt 6).

```bash
az acr delete --name "$REGISTRY_NAME" --resource-group "$RESOURCE_GROUP" --yes
```

Ingen utskrift betyder att det gick bra.

### Kontrollera att det blev rätt

```bash
az resource list --resource-group "$RESOURCE_GROUP" --output table
```

Bara en rad ska stå kvar: `id-waypoint-pipeline-murat`.

Står planen kvar? Vänta en minut och kontrollera igen. Står den fortfarande kvar, ta bort den själv:

```bash
az appservice plan delete --name "$PLAN_NAME" --resource-group "$RESOURCE_GROUP" --yes
```

> **Bygga upp igen?** Pusha kod till `main`, eller kör `gh workflow run infra-deploy-pipeline.yml`. Pipelinen skapar plan, app och registry från Bicep-filerna. Registryt är då tomt tills du bygger en ny image.

---

## 9. Snabbguide: ett vanligt arbetspass

Kopiera hela blocket när du ska förhandsgranska allt:

```bash
# 1. Förbered fönstret
source scripts/variables.sh
export MSYS_NO_PATHCONV=1
SUBJECT_PREFIX=$(gh api "repos/{owner}/{repo}/actions/oidc/customization/sub" --jq .sub_claim_prefix)

# 2. Förhandsgranska identiteten
az deployment group what-if \
  --resource-group "$RESOURCE_GROUP" \
  --template-file infra/identity.bicep \
  --parameters identityName="$IDENTITY_NAME" subjectPrefix="$SUBJECT_PREFIX"

# 3. Förhandsgranska plan, app och registry
az deployment group what-if \
  --resource-group "$RESOURCE_GROUP" \
  --template-file infra/main.bicep \
  --parameters infra/dev.bicepparam
```

> **Tips:** Kör alltid `what-if` innan `create`. Då ser du vad som händer innan det händer.

---

## Vanliga fel

| Felmeddelande | Orsak | Lösning |
|---|---|---|
| `The name property cannot be null or empty` | En variabel är tom, oftast `IDENTITY_NAME`. | Kör `source scripts/variables.sh`. |
| `MissingSubscription` | Git Bash har ändrat en sökväg. | Kör `export MSYS_NO_PATHCONV=1`. |
| `subjectPrefix` tom eller fel | `SUBJECT_PREFIX` hämtades inte i det här fönstret. | Kör `SUBJECT_PREFIX=$(gh api ...)` från avsnitt 2. |
| `AADSTS700016: Application ... was not found` | `AZURE_CLIENT_ID` i GitHub pekar på en identitet som inte finns längre. | Skapa identiteten och kör "Ge GitHub kortnumret" i avsnitt 4. |
| `AuthorizationFailed` med `.../resourcegroups/providers/...` i scope | `$RESOURCE_GROUP` är tom (nytt fönster). Gruppens namn saknas i adressen. Den långa `Traceback`-texten är en bugg i Azure CLI och kan ignoreras. | Kör raderna i "Börja här" och `echo "$RESOURCE_GROUP"`. |
| `RoleAssignmentExists` | En gammal roll för samma identitet finns kvar under ett annat namn. | Kör loopen "Om du får `RoleAssignmentExists`" i avsnitt 4, sedan `create` igen. |
| `ResourceNotFound` på `az acr show` | Registryt finns inte: pipelinen är inte klar, blev röd, eller du har städat. | Vänta på grön körning, eller pusha / kör `gh workflow run`. |
| `AuthorizationFailed` / `No subscriptions found` i pipelinen | Identitetens roll har inte hunnit börja gälla. | Vänta 2–3 minuter, `gh run rerun "$LAST_RUN" --failed`. |
