<#
    .SYNOPSIS
        Create local.settings.json for a local Azure Function based on app settings of a deployed version of the function within Azure.

    .DESCRIPTION
        App settings are being downloaded from the provided Azure Function App resource name.
        They are then decrypted to make them parseable.
        Key Vault references are being exchanged with their actual secret value.
        Depending on the parameters the settings are encrypted again.

    .EXAMPLE
        Create-AzureFunctionLocalSettings -FunctionAppName {functionAppResourceName}

    .EXAMPLE
        Create-AzureFunctionLocalSettings -FunctionAppName {functionAppResourceName} -TargetFolder {targetFolder}

    .EXAMPLE
        Create-AzureFunctionLocalSettings -FunctionAppName {functionAppResourceName} -TargetFolder {targetFolder} -UseDevelopmentStorage -Decrypted -Force
#>
param (
    [Parameter(Mandatory = $true, HelpMessage = "Existing Azure Function App resource name from where the app settings should be pulled from.")]
    [string]
    $FunctionAppName,

    [Parameter(Mandatory = $false, HelpMessage = "Target folder where the local.settings.json will be stored.")]
    [string]
    $TargetFolder = (Get-Location).Path,

    [Parameter(Mandatory = $false, HelpMessage = "Replaces Storage Account connection strings with local development storage.")]
    [string]
    $UseDevelopmentStorage = $true,

    [Parameter(Mandatory = $false, HelpMessage = "Defines whether or not the settings should be encrypted at tSettings won't be encrypted anymore if the flag is provided.")]
    [switch]
    $Decrypted = $false,

    [Parameter(Mandatory = $false, HelpMessage = "Force overwrites of existing local.settings.json.")]
    [switch]
    $Force = $false
)

$ErrorActionPreference = "Stop"

$localSettingsJsonFilePath = "$TargetFolder\local.settings.json"

Write-Host -ForegroundColor Green "Start building $localSettingsJsonFilePath..."

if ((Test-Path $localSettingsJsonFilePath) -and !$Force) {
    Write-Error "Settings file already exists. Aborting. You can use -Force to enforce overwrites."
}

Write-Host -ForegroundColor Gray "Fetching app settings from $FunctionAppName..."
func azure functionapp fetch-app-settings $FunctionAppName --output-file $localSettingsJsonFilePath | Out-Null

if ($LastExitCode -ne 0) {
    return
}

Write-Host -ForegroundColor Gray "Decrypting..."
func settings decrypt

if ($LastExitCode -ne 0) {
    return
}

$localSettingsJsonContent = Get-Content $localSettingsJsonFilePath

Write-Host -ForegroundColor Gray "Replacing Key Vault references with secret values..."
$keyVaultReferenceRegex = "@Microsoft.KeyVault\(VaultName=(?<vaultName>[^;]+);SecretName=(?<secretName>[^\)]+)\)"
$keyVaultReferenceMatches = $localSettingsJsonContent | Select-String -Pattern $keyVaultReferenceRegex -AllMatches | ForEach-Object {$_.Matches}

foreach ($match in $keyVaultReferenceMatches) {
    $vaultName = $match.Groups["vaultName"].Value
    $secretName = $match.Groups["secretName"].Value
    $secretValue = az keyvault secret show --name $secretName --vault-name $vaultName --query value -o tsv

    if ($LastExitCode -ne 0) {
        return
    }

    $localSettingsJsonContent = $localSettingsJsonContent.Replace($match.Value, "$secretValue")
}

if ($UseDevelopmentStorage) {
    Write-Host -ForegroundColor Gray "Replacing Storage Account connection strings with local development storage..."
    $storageAccountConnectionStringRegex = "DefaultEndpointsProtocol=(http|https);AccountName=[a-zA-Z0-9]+;AccountKey=[a-zA-Z0-9+\/=]+(;EndpointSuffix=[a-z.]+)?"
    $storageAccountConnectionStringMatches = $localSettingsJsonContent | Select-String -Pattern $storageAccountConnectionStringRegex -AllMatches | ForEach-Object {$_.Matches}
    
    foreach ($match in $storageAccountConnectionStringMatches) {
        $localSettingsJsonContent = $localSettingsJsonContent.Replace($match.Value, "UseDevelopmentStorage=true")
    }
}

Set-Content -Path $localSettingsJsonFilePath -Value $localSettingsJsonContent

if (!$Decrypted) {
    Write-Host -ForegroundColor Gray "Encrypting..."
    func settings encrypt

    if ($LastExitCode -ne 0) {
        return
    }
}

Write-Host -ForegroundColor Green "Finished building $localSettingsJsonFilePath."
