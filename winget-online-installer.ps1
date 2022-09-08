# Winget Online Installer (C) SocioPart 2022
# Install latest Winget without Windows Store on X86/X64/ARM/ARM64.
# Might be useful for Windows 10 LTSC users since there is no Store.

# Thanks to:
# https://github.com/microsoft/winget-cli/issues/1781
# https://gist.github.com/Splaxi/fe168eaa91eb8fb8d62eba21736dc88a
# https://github.com/muradbuyukasik/winget-script
# https://github.com/microsoft/winget-cli/issues/1861
# https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.7.0

# =============================== GLOBAL DEPENDENCIES DATA ===============================
# To add/remove dependencies simply edit depsData array.
# Use <PC_ARCH> phrase to make a URL dynamic for PC architecture (x86/x64/etc).
Enum depsInfo {
	DI_DEPNAME
	DI_DOWNLOADTYPE
	DI_FILEURI
	DI_FILEPATTERN
	DI_OUTFILENAME
	DI_SHOULDINSTALL
	DI_LICFILEREQUIRED
	DI_LICFILENAME
	DI_OUTFILEPATH
}
$depsData =
	# 0
	( "VCLibs", 					  # Dependency name (used in CLI)
	  "REGULAR",                      # Download type (REGULAR/GITHUB/NUGET)
	  "https://aka.ms/Microsoft.VCLibs.<PC_ARCH>.14.00.Desktop.appx", 
	  0,                              # File regex pattern (used only in GITHUB downloads)
	  "VCLibs-Desktop.appx",          # Out file name
	  1,							  # Should be installed or it's a prerequisite?
	  0,							  # Is license file required?
	  "", 							  # License file name
	  ""							  # Out file path (reserved and fills through the code)
	),
	# 1
    ( "XAML",                         # Dependency name (used in CLI)
	  "NUGET",                        # Download type (REGULAR/GITHUB/NUGET)
	  "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.7.0", 
	  0, 		                      # File regex pattern (used only in GITHUB downloads)
	  "Microsoft-UI-Xaml.appx",       # Out filename
	  1,							  # Should be installed or it's a prerequisite?
	  0,							  # Is license file required?
	  "", 							  # License file name
	  "" 							  # Out file path (reserved and fills through the code) 
	),
	# 2 (License should go first cause it doesn't install itself (like APPX))
	( "Winget license file",          # Dependency name (used in CLI)
	  "GITHUB",  					  # Download type (REGULAR/GITHUB/NUGET)
	  "microsoft/winget-cli", 		  # Link / GitHub repository name
	  "*.xml",        				  # File regex pattern (used only in GITHUB downloads)
	  "winget-cli-license.xml",		  # Out filename
	  0,                              # Should be installed or it's a prerequisite?
	  0,							  # Is license file required?
	  "", 							  # License file name
	  ""							  # Out file path (reserved and fills through the code)
	),
	# 3
	( "Winget",                       # Dependency name (used in CLI)
	  "GITHUB",  					  # Download type (REGULAR/GITHUB/NUGET)
	  "microsoft/winget-cli", 		  # Link / GitHub repository name
	  "*.msixbundle", 				  # File regex pattern (used only in GITHUB downloads)
	  "winget-cli-setup.msixbundle",  # Out filename
	  1,                              # Should be installed or it's a prerequisite?
	  1,							  # Is license file required?
	  "winget-cli-license.xml",	      # License file name
	  ""							  # Out file path (reserved and fills through the code)
	)

# ========================================================================================	
# https://docs.microsoft.com/en-us/windows/win32/cimwin32prov/win32-processor
$archInfoString = ("x86", "MIPS", "Alpha", "PowerPC", "UNKNOWN4", "arm", "ia64", 
                   "UNKNOWN7", "UNKNOWN8", "x64", "UNKNOWN10", "UNKNOWN11", "arm64") 
$pcArchitecture = $archInfoString[(Get-CimInstance -ClassName Win32_Processor | Select-Object -ExpandProperty Architecture)]

function Join-Paths {
    $path = $args[0]
    $args[1..$args.Count] | %{ $path = Join-Path $path $_ }
    $path
}

# Download a file from Github (using regex)
function Download-From-Github {
	param (
        $repo,
		$filenamePattern,
		$isPreRelease,
		$filePath
    )
	if ($preRelease) {
		$releasesUri = "https://api.github.com/repos/$repo/releases"
		$dataBuffer  = (Invoke-RestMethod -Method GET -Uri $releasesUri)[0].assets 
		
	}
	else {
		$releasesUri = "https://api.github.com/repos/$repo/releases/latest"
		$dataBuffer = (Invoke-RestMethod -Method GET -Uri $releasesUri).assets
	}
	$downloadUri = ($dataBuffer | Where-Object name -like $filenamePattern ).browser_download_url
	Invoke-WebRequest -Uri $downloadUri -OutFile $filePath 
}

# Download a file from Nuget package store.
function Download-From-Nuget {
	param (
		$downloadUri,
		$fileName,
		$filePath
	)
	
	$downloadPath = $filePath + ".zip"
	$extractPath = $filePath + "_extracted"
	
	Invoke-WebRequest -Uri $downloadUri -OutFile $downloadPath
	Expand-Archive $downloadPath -DestinationPath $extractPath
	
	# Move APPX (depending on architecture) into main folder.
	$tempPath = Join-Paths $extractPath 'tools' 'appx' $pcArchitecture 'Release' '*.appx'
	Move-Item -Path $tempPath -Destination $filePath
	
	#Cleaning up
	Remove-Item $downloadPath
    Remove-Item $extractPath -Recurse
}

function Create-Clean-Dir {
	param (
		$path
	)
	if(!(test-path -PathType container $path))
	{
		New-Item -ItemType Directory -Path $path | Out-Null
	}
	else {
		Remove-Item -LiteralPath $path -Force -Recurse | Out-Null
		New-Item -ItemType Directory -Force -Path $path | Out-Null
	}
}

# Main code
function Install-Winget {
	param (
		$ignorelicense
	)
	$tempDirName = "winget-online-installer"
	$errorLevel = 0
	Write-Host "Winget Online Installer started" -ForegroundColor Green
	try {
		Write-Host "Downloading dependencies and installation files..." -ForegroundColor Yellow
		Create-Clean-Dir (Join-Paths $([System.IO.Path]::GetTempPath()) $tempDirName)
		# Step 1. Download everything to specific folder inside TEMP.
		for ($i = 0; $i -lt $depsData.length; $i++) { 
			Write-Host "["$($i+1)"/"$depsData.length"]: Downloading" $depsData[$i][[depsInfo]::DI_DEPNAME]

			$depsData[$i][[depsInfo]::DI_OUTFILEPATH] =  Join-Paths $([System.IO.Path]::GetTempPath()) `
																	$tempDirName `
																	$depsData[$i][[depsInfo]::DI_OUTFILENAME]
																	
			if ($depsData[$i][[depsInfo]::DI_FILEURI] -match $("<PC_ARCH>")){
				$depsData[$i][[depsInfo]::DI_FILEURI] = $depsData[$i][[depsInfo]::DI_FILEURI].replace("<PC_ARCH>", $pcArchitecture)
			}
			try {
				switch ($depsData[$i][[depsInfo]::DI_DOWNLOADTYPE]) {
					'REGULAR' { 
						Invoke-WebRequest -Uri $depsData[$i][[depsInfo]::DI_FILEURI] `
										  -OutFile $depsData[$i][[depsInfo]::DI_OUTFILEPATH]
					}
					'GITHUB' { 
						Download-From-Github $depsData[$i][[depsInfo]::DI_FILEURI] `
											 $depsData[$i][[depsInfo]::DI_FILEPATTERN] `
											 $false `
											 $depsData[$i][[depsInfo]::DI_OUTFILEPATH] `
					}
					'NUGET' {
						Download-From-Nuget $depsData[$i][[depsInfo]::DI_FILEURI] `
											$depsData[$i][[depsInfo]::DI_OUTFILENAME] `
											$depsData[$i][[depsInfo]::DI_OUTFILEPATH]
						
					}
				}
			}
			catch {
				Write-Host "Error while downloading files." -ForegroundColor Red
				$Host.UI.WriteErrorLine($errorMessage)
				$errorLevel++
			}
		}
		
		# Step 2. Install add needed packages.
		Write-Host "Installing all needed packages..." -ForegroundColor Yellow
		for ($i = 0; $i -lt $depsData.length; $i++) {
			#try {
				if ($depsData[$i][[depsInfo]::DI_SHOULDINSTALL] -eq 1){
					Write-Host "Installing" $depsData[$i][[depsInfo]::DI_DEPNAME]
					Write-Host $depsData[$i][[depsInfo]::DI_OUTFILEPATH]
					# If license file is presented and not ignored, install a package using this file.
						if (($depsData[$i][[depsInfo]::DI_LICFILEREQUIRED] -eq 1) -and ($ignorelicense -eq 0)){
							$licPath = Join-Paths $([System.IO.Path]::GetTempPath()) `
									   $tempDirName $depsData[$i][[depsInfo]::DI_LICFILENAME]
							Write-Host $licPath
							Add-AppxProvisionedPackage -Online `
								-PackagePath $depsData[$i][[depsInfo]::DI_OUTFILEPATH] -LicensePath $licPath
						}
						else {
							Add-AppxPackage $depsData[$i][[depsInfo]::DI_OUTFILEPATH]
						}

				}
			#}
			#catch {
			#	Write-Host "Error during installation." -ForegroundColor Red
			#	$Host.UI.WriteErrorLine($errorMessage)
			#	$errorLevel++
			#}
		}
		Write-Host "Cleaning up..." -ForegroundColor Yellow
		Remove-Item -LiteralPath (Join-Paths $([System.IO.Path]::GetTempPath()) $tempDirName) -Force -Recurse | Out-Null
		if ($errorLevel -lt 0){
			Write-Host "Winget installation exited with errors." -ForegroundColor Red
			try {1/0} catch { $_ | Format-List * -Force | Out-String }
		}
		else {
			Write-Host "Winget is successfully installed!" -ForegroundColor Green
		}
	}
	catch {
		Write-Host "Emergency stop." -ForegroundColor Red
	}
}

# Loader
$isLicenseIgnored = 0
if ($args[0] -eq "--ignore-license"){
	Write-Host "Ignoring license file!" -ForegroundColor Blue
	$isLicenseIgnored = 1
}
Install-Winget $isLicenseIgnored