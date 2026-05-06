$outputFile = Join-Path $PSScriptRoot "all-functions.txt"

# Clear file if exists
if (Test-Path $outputFile) {
    Remove-Item $outputFile
}

# Get all function folders inside script directory
$folders = Get-ChildItem -Path $PSScriptRoot -Directory

Write-Host "Function folders found:" $folders.Count

foreach ($folder in $folders) {
    $functionName = $folder.Name
    $filePath = Join-Path $folder.FullName "index.ts"

    if (Test-Path $filePath) {
        Add-Content $outputFile "this is supabase/functions/$functionName/index.ts"
        Add-Content $outputFile (Get-Content $filePath -Raw)
        Add-Content $outputFile "`n`n"
    } else {
        Write-Host "Skipped (no index.ts): $functionName"
    }
}

Write-Host "Done! Output saved to $outputFile"

if (Test-Path $outputFile) {
    Invoke-Item $outputFile
} else {
    Write-Host "File was not created!"
}