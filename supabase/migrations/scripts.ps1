$outputFile = "all-migrations.txt"

# Clear file if exists
if (Test-Path $outputFile) {
    Remove-Item $outputFile
}

# Loop through all .sql files
Get-ChildItem -Filter *.sql | Sort-Object Name | ForEach-Object {
    $fileName = $_.Name
    $filePath = $_.FullName

    Add-Content $outputFile "this is supabase/migrations/$fileName"
    Add-Content $outputFile (Get-Content $filePath -Raw)
    Add-Content $outputFile "`n`n"
}

Write-Host "Done! Output saved to $outputFile"