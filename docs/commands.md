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

Skapar identiteten som GitHub Actions loggar in som, och ger den rätt att ändra i resursgruppen.

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

Utskriften är identitetens `clientId` (ett långt id). Vänta en halv minut innan nästa steg.

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

## 6. Snabbguide: ett vanligt arbetspass

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
