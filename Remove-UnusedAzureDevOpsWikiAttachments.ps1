param (
    [Parameter(Mandatory=$false)]
    [string]
    $AttachmentFolderPath = ".\.attachments\",

    [Parameter(Mandatory=$false)]
    [string]
    $MarkdownFolderPath = ".\",

    [Parameter(Mandatory=$false)]
    [switch]
    $WhatIf = $false
)

$ExitCode = 0

# Get all asset files
$AttachmentFiles = Get-ChildItem -Path $AttachmentFolderPath -File

# Loop through each asset file
foreach ($AttachmentFile in $AttachmentFiles) {

    # Encode whitespace to %20
    $EncodedAttachmentFileName = $AttachmentFile.Name -replace ' ', '%20'

    # Search for AttachmentFileReferences in Markdown files
    $AttachmentFileReferences = Get-ChildItem -Path $MarkdownFolderPath -Recurse -Filter *.md | Select-String -Pattern $EncodedAttachmentFileName

    # If no AttachmentFileReferences found, delete the file
    if ($AttachmentFileReferences.Count -eq 0) {
        if (!$WhatIf) {
            Remove-Item -Path $AttachmentFile.FullName -Force
        }
        else {
            # In a pipeline scenario we want a bad exit code to indicate that an actual cleanup without -WhatIf should be done.
            $ExitCode = 1
        }
        
        Write-Host $(if ($WhatIf) { "What if:" }) "Deleted unused/unreferenced attachment file: $($AttachmentFile.Name)"
    }
}

Exit $ExitCode