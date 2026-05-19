#Requires -Version 7.0
<#
.SYNOPSIS
    Phase 9 — Functional Testing (Interactive)
.DESCRIPTION
    Verifies the chatbot works end-to-end:
    - Upload test documents
    - Trigger indexing
    - Verify search index
    - Test frontend chat
    - Diagnose common issues
    
    This phase is INTERACTIVE — requires user input at multiple steps.
.PARAMETER GPTRAG_RG
    Resource group for GPT-RAG resources
.PARAMETER Action
    Which sub-step to execute:
    - GetPrefix: Get resource prefix from deployed resources
    - Upload: Upload documents to storage
    - TriggerIndexing: Force restart dataingest
    - VerifyIndex: Check AI Search document count
    - ShowFrontend: Display frontend URL
    - DiagnoseChat: Run diagnostics for chat issues
    - DiagnoseInvalidScope: Fix App Config AZURE_CLIENT_ID collision
.PARAMETER DocumentPath
    Path to documents folder (for Upload action)
#>
param(
    [Parameter(Mandatory)][string]$GPTRAG_RG,
    [Parameter(Mandatory)][ValidateSet(
        "GetPrefix","Upload","TriggerIndexing",
        "VerifyIndex","ShowFrontend","DiagnoseChat","DiagnoseInvalidScope"
    )][string]$Action,
    [string]$DocumentPath
)

Write-Host "`n=== Phase 9: Functional Testing ($Action) ===" -ForegroundColor Cyan

# Get container apps list (used by multiple actions)
$apps = az containerapp list -g $GPTRAG_RG --query "[].{Name:name,FQDN:properties.configuration.ingress.fqdn}" -o json | ConvertFrom-Json

switch ($Action) {
    "GetPrefix" {
        $prefix = ($apps[0].Name) -replace 'ca-|-frontend|-orchestrator|-dataingest',''
        Write-Host "Resource prefix: $prefix" -ForegroundColor Cyan
    }

    "Upload" {
        if (-not $DocumentPath) {
            Write-Host "ERROR — DocumentPath parameter required for Upload action" -ForegroundColor Red
            Write-Host "   Usage: -Action Upload -DocumentPath 'C:\docs\my-files'" -ForegroundColor Gray
            exit 1
        }
        if (-not (Test-Path $DocumentPath)) {
            Write-Host "ERROR — Path not found: $DocumentPath" -ForegroundColor Red
            exit 1
        }

        $storageAccount = az storage account list -g $GPTRAG_RG --query "[?contains(name,'st')].name | [0]" -o tsv
        Write-Host "Uploading to storage account: $storageAccount" -ForegroundColor Cyan
        az storage blob upload-batch --account-name $storageAccount -d "documents" -s $DocumentPath --auth-mode login
        Write-Host "Documents uploaded to container 'documents'" -ForegroundColor Green
        Write-Host "Supported formats: PDF, DOCX, PPTX, XLSX, TXT, MD, JPG, PNG, BMP, TIFF, HTML" -ForegroundColor Gray
    }

    "TriggerIndexing" {
        $ingestApp = ($apps | Where-Object { $_.Name -match "dataingest" }).Name
        if (-not $ingestApp) {
            Write-Host "ERROR — dataingest Container App not found" -ForegroundColor Red
            exit 1
        }
        $ts = Get-Date -Format 'yyyyMMddHHmmss'
        az containerapp update -n $ingestApp -g $GPTRAG_RG --set-env-vars "RESTART_TRIGGER=$ts" -o none
        Write-Host "Dataingest restarted — indexing will begin shortly" -ForegroundColor Green
        Write-Host "Wait 2-5 minutes for documents to be processed..." -ForegroundColor Gray
    }

    "VerifyIndex" {
        $searchService = az search service list -g $GPTRAG_RG --query "[0].name" -o tsv
        if (-not $searchService) {
            Write-Host "ERROR — No AI Search service found in $GPTRAG_RG" -ForegroundColor Red
            exit 1
        }
        $indexName = "ragindex"
        $searchUrl = "https://$searchService.search.windows.net/indexes/$indexName/docs/`$count?api-version=2024-07-01"
        $token = az account get-access-token --resource "https://search.azure.com" --query accessToken -o tsv
        
        try {
            $docCount = Invoke-RestMethod -Uri $searchUrl -Headers @{Authorization="Bearer $token"} -Method Get
            Write-Host "Index: $indexName — Document chunks: $docCount" -ForegroundColor Cyan
            if ($docCount -gt 0) {
                Write-Host "Documents indexed successfully!" -ForegroundColor Green
            } else {
                Write-Host "No documents indexed yet." -ForegroundColor Yellow
                Write-Host "Checking dataingest logs..." -ForegroundColor Gray
                $ingestApp = ($apps | Where-Object { $_.Name -match "dataingest" }).Name
                az containerapp logs show -n $ingestApp -g $GPTRAG_RG --type console --tail 30 --format text
            }
        } catch {
            Write-Host "ERROR querying search index: $_" -ForegroundColor Red
        }
    }

    "ShowFrontend" {
        $frontendApp = $apps | Where-Object { $_.Name -match "frontend" }
        if (-not $frontendApp) {
            Write-Host "ERROR — Frontend Container App not found" -ForegroundColor Red
            exit 1
        }
        Write-Host ""
        Write-Host "  GPT-RAG Chat Frontend" -ForegroundColor Cyan
        Write-Host "  URL: https://$($frontendApp.FQDN)" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Test questions to try:" -ForegroundColor Gray
        Write-Host "  1. 'What is this document about?'" -ForegroundColor Gray
        Write-Host "  2. 'Summarize the key points'" -ForegroundColor Gray
        Write-Host "  3. 'What does the document say about [specific topic]?'" -ForegroundColor Gray
        Write-Host ""
        Write-Host "NOTE: URL is private — access from Jumpbox browser only." -ForegroundColor Yellow
    }

    "DiagnoseChat" {
        Write-Host "Running diagnostics..." -ForegroundColor Cyan

        # Check orchestrator logs
        $orchName = ($apps | Where-Object { $_.Name -match "orchestrator" }).Name
        if ($orchName) {
            Write-Host "`n── Orchestrator Logs (last 30 lines) ──" -ForegroundColor Yellow
            az containerapp logs show -n $orchName -g $GPTRAG_RG --type console --tail 30 --format text
        }

        # Check dataingest logs
        $ingestName = ($apps | Where-Object { $_.Name -match "dataingest" }).Name
        if ($ingestName) {
            Write-Host "`n── Dataingest Logs (last 15 lines) ──" -ForegroundColor Yellow
            az containerapp logs show -n $ingestName -g $GPTRAG_RG --type console --tail 15 --format text
        }
    }

    "DiagnoseInvalidScope" {
        Write-Host "Diagnosing App Config AZURE_CLIENT_ID collision (Fix 8)..." -ForegroundColor Cyan
        $appConfigName = az appconfig list -g $GPTRAG_RG --query "[0].name" -o tsv
        
        Write-Host "`nCurrent AZURE_CLIENT_ID entries:" -ForegroundColor Yellow
        az appconfig kv list --name $appConfigName --key "AZURE_CLIENT_ID" --auth-mode login -o table

        Write-Host "`nTo fix, delete non-dataingest entries:" -ForegroundColor Cyan
        Write-Host "  az appconfig kv delete --name $appConfigName --key 'AZURE_CLIENT_ID' --label 'gpt-rag-orchestrator' --auth-mode login --yes" -ForegroundColor Gray
        Write-Host "  az appconfig kv delete --name $appConfigName --key 'AZURE_CLIENT_ID' --label 'gpt-rag-frontend' --auth-mode login --yes" -ForegroundColor Gray
    }
}

Write-Host "`n=== Phase 9 ($Action) COMPLETE ===" -ForegroundColor Green
