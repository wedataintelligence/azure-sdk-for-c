. (Join-Path $PSScriptRoot common.ps1)

$PATTERN_REGEX = "^\[\w+(\.(?<SectionName>\w+))?\]:\s#\s\((?<Pattern>.*)\)"
$CsvMetaData = Get-CSVMetadata

function Get-PackagesInfoFromFile ($releaseNotesLocation) 
{
    $releaseNotesContent = Get-Content -Path $releaseNotesLocation
    $checkLine = $False
    $presentPkgInfo = @()

    foreach ($line in $releaseNotesContent)
    {
        if ($line -eq "<!--")
        {
            $checkLine = $True
            continue
        }
        if ($line -eq "-->")
        {
            break
        }
        if ($checkLine)
        {
            $pkgInfo = ($line.Trim()).Split(":")
            $packageName = $pkgInfo[0]
            $packageMetaData = $CsvMetaData | Where-Object { $_.Package -eq $packageName }
            if ($packageMetaData.Count -gt 0)
            {
                $presentPkgInfo += $line.Trim()
            }
        }
    }
    return $presentPkgInfo
}

function Filter-ReleaseHighlights ($releaseHighlights)
{
    $results = @{}

    foreach ($key in $releaseHighlights.Keys)
    {
        $keyInfo = $key.Split(":")
        $packageName = $keyInfo[0]
        $packageVersion = $keyInfo[1]

        $packageMetaData = $CsvMetaData | Where-Object { $_.Package -eq $packageName }

        if ($packageMetaData.ServiceName -eq "template")
        {
            continue
        }

        $existingPackages = GetExistingPackageVersions -PackageName $packageName `
        -GroupId $packageMetaData.GroupId

        $versionExists = $existingPackages | Where-Object { $_ -eq $packageVersion }

        if ($null -eq $versionExists)
        {
            continue
        }

        $results.Add($key, $releaseHighlights[$key])
    }
    return $results
}

function Write-GeneralReleaseNote ($releaseHighlights, $releaseFilePath)
{
    $releaseContent = Get-Content $releaseFilePath
    $newReleaseContent = @()
    $writingPaused = $False

    foreach ($line in $releaseContent)
    {
        if ($line -match $PATTERN_REGEX)
        {
            $sectionName = $matches["SectionName"]
            $pattern = $matches["Pattern"]

            foreach ($key in $releaseHighlights.Keys)
            {
                $pkgInfo = $key.Split(":")
                $packageName = $pkgInfo[0]
                $packageVersion = $pkgInfo[1]
                $packageFriendlyName = ($csvMetaData | Where-Object { $_.Package -eq $PackageName }).DisplayName

                if ($null -eq $packageFriendlyName)
                {
                    $packageFriendlyName = $packageName
                }

                $changelogUrl = $releaseHighlights[$key]["ChangelogUrl"]
                $changelogUrl = "(${changelogUrl})"
                $highlightsBody = $releaseHighlights[$key]["Content"]
                $packageSemVer = [AzureEngSemanticVersion]::ParseVersionString($PackageVersion)
                
                $lineValue = $ExecutionContext.InvokeCommand.ExpandString($pattern)
                if ([System.String]::IsNullOrEmpty($sectionName))
                {
                    $newReleaseContent += $lineValue
                }
                elseif ($packageSemVer.VersionType -eq $sectionName)
                {
                    $newReleaseContent += $lineValue
                }
            }
            $newReleaseContent += ""
            if ($writingPaused)
            {
                $newReleaseContent += "```````n"
                $writingPaused = $False
            }
        }

        if ($line -eq "``````")
        {
            $writingPaused = $True
        }

        if (!$writingPaused)
        {
            $newReleaseContent += $line
        }
    }
    Set-Content -Path $releaseFilePath -Value $newReleaseContent
}