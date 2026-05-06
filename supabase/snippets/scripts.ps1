$outputFile = Join-Path $PSScriptRoot "all-migrations.txt"

# Clear file if exists
if (Test-Path $outputFile) {
    Remove-Item $outputFile
}

$files = Get-ChildItem -Path $PSScriptRoot -Filter *.sql

Write-Host "SQL files found:" $files.Count

$files | Sort-Object Name | ForEach-Object {
    $fileName = $_.Name
    $filePath = $_.FullName

    Add-Content $outputFile "this is supabase/migrations/$fileName"
    Add-Content $outputFile (Get-Content $filePath -Raw)
    Add-Content $outputFile "`n`n"
}

Write-Host "Done! Output saved to $outputFile"

if (Test-Path $outputFile) {
    Invoke-Item $outputFile
} else {
    Write-Host "File was not created!"
}