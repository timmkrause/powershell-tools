<#
    .SYNOPSIS
        Cleans up template spec versions based on a configurable threshold for a given subscription.
        The script was established to circumvent 800 version resource quota per spec.

    .DESCRIPTION
        Loops through all template spec resources of the given subscription and their versions.
        In case the number of template spec versions exceeds $MaxVersionsToKeepPerTemplateSpec template spec versions are being deleted until $MaxVersionsToKeepPerTemplateSpec is met again.
        Oldest versions are deleted first.

    .EXAMPLE
        Remove-ObsoletetTemplateSpecVersions -SubscriptionName "subscriptionName"

    .EXAMPLE
        Remove-ObsoletetTemplateSpecVersions -SubscriptionName "subscriptionName" -MaxVersionsToKeepPerTemplateSpec 200 -Detailed

    .EXAMPLE
        Remove-ObsoletetTemplateSpecVersions -SubscriptionName "subscriptionName" -MaxVersionsToKeepPerTemplateSpec 200 -Detailed -WhatIf
#>
param (
    [Parameter(Mandatory = $true, HelpMessage = "The Azure subscription name for which the template specs should be analyzed and/or cleaned up.")]
    [string]
    $SubscriptionName,

    [Parameter(Mandatory = $false, HelpMessage = "The maximum number of versions to keep per template spec.")]
    [int]
    $MaxVersionsToKeepPerTemplateSpec = 400,

    [Parameter(Mandatory = $false, HelpMessage = "Defines whether or not a progress bar should be displayed instead of detailed logs.")]
    [switch]
    $Detailed = $false,

    [Parameter(Mandatory = $false)]
    [switch]
    $WhatIf = $false
)

$ErrorActionPreference = "Stop"

Set-AzContext -Subscription $SubscriptionName | Out-Null

# Get all template specs
Write-Host "Retrieving all template specs of subscription ""$((Get-AzContext).Subscription.Name)""..."

$templateSpecs = Get-AzTemplateSpec

# Switch to control whether to render progress bar or detailed logs
$renderProgressBar = !$Detailed

$numSpecCounter = 1
$numSpecs = $templateSpecs.Count

# Loop through each template spec
foreach ($templateSpec in $templateSpecs) {
    Write-Host "Processing template spec $($templateSpec.Name) ($numSpecCounter/$numSpecs)..."
    # Get all versions of the template spec
    $versions = Get-AzTemplateSpec -Name $templateSpec.Name -ResourceGroupName $templateSpec.ResourceGroupName | Select-Object -ExpandProperty Versions

    # Order versions by creation date
    $versions = $versions | Sort-Object -Property CreationTime

    # Log number of versions and how many will be deleted
    $numVersions = $versions.Count

    Write-Host "- Number of versions to keep: $MaxVersionsToKeepPerTemplateSpec"

    if ($numVersions -gt $MaxVersionsToKeepPerTemplateSpec) {
        $numToDelete = $numVersions - $MaxVersionsToKeepPerTemplateSpec
        Write-Host "- Number of versions: $numVersions"
        Write-Host "- Number of versions to delete: $numToDelete"

        # Remove versions until limit is reached
        $numDeleted = 1
        foreach ($version in $versions) {
            if ($MaxVersionsToKeepPerTemplateSpec -lt $numVersions) {
                if ($renderProgressBar) {
                    Write-Progress -Activity "- $(if ($WhatIf) { "What if:" }) Removing versions" -Status "$numDeleted of $numToDelete" -PercentComplete (($numDeleted / $numToDelete) * 100)
                    Start-Sleep -Seconds 0.05
                } else {
                    Write-Host "- $(if ($WhatIf) { "What if:" }) Removing version ($numDeleted/$numToDelete): $($version.Name) from $($version.CreationTime)"
                }

                if (!$WhatIf) {
                    Remove-AzTemplateSpec -Name $templateSpec.Name -ResourceGroupName $templateSpec.ResourceGroupName -Version $version.Name -Force | Out-Null
                }

                $MaxVersionsToKeepPerTemplateSpec++
                $numDeleted++
            } else {
                if ($renderProgressBar) {
                    Write-Progress -Activity "Removing versions" -Completed
                }

                Write-Host "- Limit reached. Stopping removal process."
                
                break
            }
        }
    } else {
        Write-Host "- Number of versions: $numVersions"
        Write-Host "- No versions need to be deleted."
    }

    $numSpecCounter++
}
