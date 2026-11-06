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
| `source scripts/variables.sh` | Lägger in dina namn (resursgrupp, plan, app, identitet) i variabler. |
| `export MSYS_NO_PATHCONV=1` | Hindrar Git Bash på Windows från att ändra sökvägar som börjar med `/`. Annars kan Azure svara med fel som `MissingSubscription`. |

Efter `source` ska du se en lista med dina värden. Står det något tomt där, är något fel i `scripts/variables.sh`.

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

---

## 2. Miljövariabler

### Kontrollera att variablerna är satta

```bash
echo "$RESOURCE_GROUP"
echo "$PLAN_NAME"
echo "$PLAN_SKU"
echo "$APP_NAME"
echo "$IDENTITY_NAME"
```

Är en rad tom? Kör `source scripts/variables.sh` igen.

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

Sista raden ska vara:

```
Resource changes: 2 to create, 1 unsupported.
```

`1 unsupported` är normalt. Det är rollen, som inte kan förhandsgranskas förrän identiteten finns.

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

## 5. Bicep – Plan och webbapp (`main.bicep`)

Använder parameterfilen `infra/dev.bicepparam`, där namnen redan står.

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

## 6. Följ pipelinen

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

### Om något blev rött

Visa bara loggen från stegen som misslyckades:

```bash
gh run view "$LAST_RUN" --log-failed
```

Kör om bara de misslyckade jobben:

```bash
gh run rerun "$LAST_RUN" --failed
```

### Starta pipelinen utan att pusha

```bash
gh workflow run infra-deploy-pipeline.yml
```

### Öppna körningen i webbläsaren

```bash
gh run view "$LAST_RUN" --web
```

---

## 7. Städa efter dig

Planen kostar pengar varje timme den finns, även när ingen använder appen. Ta bort appen när du är klar för dagen. Planen följer med automatiskt.

> 🛑 **Det här tar du INTE bort:**
> - **Resursgruppen** `RG-muratbuyuksal`. Skolan har skapat den, och den ska stå kvar hela kursen.
> - **Identiteten** `id-waypoint-pipeline-murat`. Den kostar ingenting, och utan den kan pipelinen inte logga in.
> - **Hemligheterna i GitHub.**

### Ta bort appen (och planen)

```bash
az webapp delete --name "$APP_NAME" --resource-group "$RESOURCE_GROUP"
```

Ibland skrivs `Note: If this is the last app on the plan, the plan will also be deleted.` ut, ibland ingenting. Båda är okej.

### Kontrollera att det blev rätt

```bash
az resource list --resource-group "$RESOURCE_GROUP" --output table
```

Bara en rad ska stå kvar: `id-waypoint-pipeline-murat`.

> **Bygga upp igen?** Pusha kod till `main`, eller kör `gh workflow run infra-deploy-pipeline.yml`. Pipelinen skapar planen och appen från Bicep-filerna.

---

## 8. Snabbguide: ett vanligt arbetspass

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

# 3. Förhandsgranska plan och app
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
