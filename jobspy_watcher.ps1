# Script to post new job postings from jobspy
# 1.0
# April 29, 2025

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$scriptPath = Split-path -Parent $PSCommandPath

$storageDirectory = "$scriptPath\jobspy"
$logFileExact = "$storageDirectory\jobspy.log"
$pathExists = Test-Path -LiteralPath "$storageDirectory"
if ($pathExists -eq $false) { mkdir "$storageDirectory" }

$logExists = Test-Path -LiteralPath "$logFileExact"
if ($logExists -eq $false) { Out-File "$logFileExact" }

$logFileData = Get-Content -Path "$($logFileExact)"
$jobObject = [System.Collections.Generic.List[System.Object]]::new()

[regex]$payRegex = '(|\>).*?(?<pay>\$.*?)(\n|<\/.*?\>)'
[regex]$locationRegex = '(|\>).*?(locale|location|state)(\:|\s*?|\-)(?<location>.*?)(\n|<\/.*?\>)'
$defaultLogoURL = 'https://imgur.com/eNJtDiO'

# Store your webhook urls in the file named below
$discordURLWebhook = Get-Content -Path "$($scriptPath)\discordwebhooks"

# JobSpy endpoint details
$jobSpyEndpointBase = "http://192.168.1.242" # base of URL http://192.x.x.x
$port = ":8008" # port with :
$resourcePath = '/api/v1/search_jobs'

#endpoint uri build
$uri = "$($jobSpyEndpointBase)$($port)$($resourcePath)"

# Request building
$headers = @{
    "accept"       = "application/json"
    "Content-Type" = "application/json"
}

# Define the JSON payload
$body = @{
    site_name                  = @("indeed", "linkedin", "zip_recruiter", "glassdoor", "google")
    search_term                = "software packaging"
    google_search_term         = "software packaging"
    location                   = "USA"
    distance                   = 50
    job_type                   = "fulltime"
    is_remote                  = $true
    results_wanted             = 40
    description_format         = "markdown"
    offset                     = 0
    verbose                    = 2
    linkedin_fetch_description = $true
    linkedin_company_ids       = @(0)
    country_indeed             = "USA"
    enforce_annual_salary      = $false
} | ConvertTo-Json -Depth 10


# Grab data with API request
$jobJSON = (Invoke-WebRequest -Uri $uri -Method POST -Headers $headers -Body $body).content | ConvertFrom-Json -Depth 10
if ($jobJSON.count -eq 0) { Write-Warning "Nothing found, check API/endpoint and config for body."; pause } # In case nothing found

foreach ($jobPost in $($jobJSON.Jobs)) {

    Clear-Variable jobHashTable, payFromDescript -ErrorAction SilentlyContinue

    $jobHashTable = @{}
 
    # Manually handle properties and data that may be missing

    # Find money, if not found in property, look for it in description
    if ([string]::IsNullOrEmpty($jobPost.min_amount) -AND [string]::IsNullOrEmpty($jobPost.min_amount)) { 
        $payFromDescript = ($jobPost.description | Select-String -Pattern $payRegex -AllMatches).Matches.groups | Where-Object { $_.name -eq 'Pay' }
        $payFromDescript = $payFromDescript | Select-object -Last 1 # Making an assumption that it will be nearer the bottom
        $payFromDescript = $payFromDescript -replace ('\.', '.') # Markdown cleanup

        if ([string]::IsNullOrWhiteSpace($payFromDescript)) {
            $jobHashTable['PayInfo'] = "Not Found"
        }
        else {
            $jobHashTable['PayInfo'] = $payFromDescript.Trim()
        }
    }
    else {
        $jobHashTable['PayInfo'] = @("`$$(([int]$jobPost.min_amount).ToString("N0"))", "-", "`$$(([int]$jobPost.max_amount).ToString("N0"))", "$($jobPost.interval)") -join " "
    }

    # Company location check
    if ([string]::IsNullOrEmpty($jobPost.location)) {
        $locFromDescript = ($jobPost.description | Select-String -Pattern $locationRegex -AllMatches).Matches.groups | Where-Object { $_.name -eq 'Location' }
        $locFromDescript = $locFromDescript | Select-object -Last 1
        $locFromDescript = $locFromDescript -replace ('\.', '.') # Markdown cleanup

        Try { $jobHashTable['Location'] = $locFromDescript.Trim() } Catch { $jobHashTable['Location'] = "Not Found" }
    
    }
    else {
        Try { $jobHashTable['Location'] = $jobPost.location.Trim() } Catch { $jobHashTable['Location'] = "Not Found" }
    }

    # Company logo check
    if (-not [string]::IsNullOrEmpty($jobPost.company_logo)) {
        $jobHashTable['CompanyLogo'] = $jobPost.company_logo.Trim()
    }

    Try { $jobHashTable['JobPosted'] = $jobPost.date_posted.Trim() } Catch { $jobHashTable['JobPosted'] = "Not Found" }

    # Build rest of object/data
    Try { $jobHashTable['JobTitle'] = $jobPost.title.ToString().Trim() } Catch { $jobHashTable['JobTitle'] = "Not Found" }
    Try { $jobHashTable['Link'] = $jobPost.job_url.ToString().Trim() } Catch { $jobHashTable['Link'] = "Not Found" }
    Try { $jobHashTable['Company'] = $jobPost.Company.ToString().Trim() } Catch { $jobHashTable['Company'] = "Not Found" }
    Try { $jobHashTable['Description'] = $jobPost.description.ToString().Trim() } Catch { $jobHashTable['Description'] = "Not Found" }
    Try { $jobHashTable['UniqueID'] = $jobPost.id.ToString().Trim() } Catch { $jobHashTable['UniqueID'] = "Not Found" }
    
    $null = $jobObject.Add($jobHashTable)
}

# Report unique jobs to discord

Foreach ($jobFound in $jobObject) {

    # Have we already reported on this? if so skip
    if (!$($logFileData -contains "$($jobFound.UniqueID)")) {

        Clear-Variable jsonbody -ErrorAction SilentlyContinue
        $jsonBody = @{
            embeds   = @(
                @{
                    title       = "$($jobFound.JobTitle)"
                    description = "|| ``````" + $($jobFound.Description[0..1000] -join "") + "..." + "`````` ||"   # $($Post.Selftext[0..1020] -join "") + "..."
                    url         = "$($jobFound.Link)"
                    fields      = @(
                        @{
                            name  = "Location"
                            value = "$($JobFound.Location)"
                        }
                        @{
                            name  = "PayInfo"
                            value = "$($JobFound.PayInfo)"
                        }
                        @{
                            name  = "DatePosted"
                            value = "$($JobFound.JobPosted)"
                        }
                    )
                    author      = @{
                        name     = "$($JobFound.Company)"
                        icon_url = "$(@($jobFound.CompanyLogo,$defaultLogoURL) | Select-Object -First 1)"
                    }
                }
            )
            username = "JobBot"
            flags    = 4096

        } | ConvertTo-Json -Depth 100


        Foreach ($webhook in $discordURLWebhook) {
            Try {
                Clear-Variable r -ErrorAction SilentlyContinue
                $r = Invoke-RestMethod -uri "$($webhook)?wait=true" -Body $jsonbody -Method Post -ContentType "application/json"
                Start-Sleep -Seconds 1

                # Successful post?
                if (-not [string]::IsNullOrEmpty($r.webhook_id)) {
                    # Then save the id so that it isn't reported again
                    # Add the uniqueIdentifier to the Log file
                    $JobFound.uniqueID | Add-Content -LiteralPath "$logFileExact"
                }
            }
            Catch { Write-host "Error found", $_.Exception.Message }
        }
    }
}