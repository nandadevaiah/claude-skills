# Azure Trusted Signing Requires -kva Flag

**Extracted:** 2026-03-31
**Context:** Windows code signing with AzureSignTool in CI/CD pipelines

## Problem
AzureSignTool sign command fails with 403 Forbidden when using Azure Trusted Signing
(formerly Azure Code Signing). The error message says "Failed to retrieve certificate
from Azure Key Vault" even though you're using Trusted Signing, not Key Vault.

The tool falls back to Key Vault signing mode when the `-kva` (account name) flag is
missing, hitting a completely different API endpoint that rejects the request.

## Solution
Add the `-kva` flag with the Trusted Signing account name:

```bash
# WRONG — missing -kva, falls back to Key Vault mode, gets 403
AzureSignTool sign -kvu "$ENDPOINT" -kvi "$CLIENT_ID" -kvs "$SECRET" -kvt "$TENANT_ID" -kvc "$CERT_PROFILE" ...

# RIGHT — -kva tells AzureSignTool to use Trusted Signing
AzureSignTool sign \
  -kvu "$ENDPOINT" \
  -kva "$ACCOUNT_NAME" \
  -kvc "$CERT_PROFILE_NAME" \
  -kvi "$CLIENT_ID" \
  -kvs "$CLIENT_SECRET" \
  -kvt "$TENANT_ID" \
  -tr http://timestamp.acs.microsoft.com \
  -td sha256 \
  "file.exe"
```

Required GitHub secrets for Trusted Signing:
- `AZURE_ENDPOINT` — `https://<region>.codesigning.azure.net` (eus, weu, etc.)
- `AZURE_CODE_SIGNING_ACCOUNT` — the account name (used with -kva)
- `AZURE_CERT_PROFILE_NAME` — certificate profile name (used with -kvc)
- `AZURE_CLIENT_ID` — app registration client ID
- `AZURE_CLIENT_SECRET` — app registration secret (check expiry!)
- `AZURE_TENANT_ID` — directory tenant ID

Also trim env vars to prevent whitespace issues:
```javascript
`-kvi "${process.env.AZURE_CLIENT_ID.trim()}"`
```

## When to Use
- Setting up Windows code signing with Azure Trusted Signing
- Debugging 403 errors from AzureSignTool
- Migrating from Azure Key Vault signing to Trusted Signing
- Any electron-builder or CI/CD pipeline using AzureSignTool
