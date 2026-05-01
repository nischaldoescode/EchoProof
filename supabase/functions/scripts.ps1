$outputFile = "all-functions.txt"

# Clear file if exists
if (Test-Path $outputFile) {
    Remove-Item $outputFile
}

# Loop through each function folder
Get-ChildItem -Directory | ForEach-Object {
    $functionName = $_.Name
    $filePath = Join-Path $_.FullName "index.ts"

    if (Test-Path $filePath) {
        Add-Content $outputFile "this is supabase/functions/$functionName/index.ts"
        Add-Content $outputFile (Get-Content $filePath -Raw)
        Add-Content $outputFile "`n`n"
    }
}

Write-Host "Done! Output saved to $outputFile"