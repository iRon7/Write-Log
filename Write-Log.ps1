<#
.Synopsis
	Write-Log
.Description
	A PowerShell framework for sophisticated logging
.Notes
	Author:    Ronald Bode
	Version:   01.00.04
	Created:   2009-03-18
	Modified:  2017-06-11
#>

Function Main {
	Log -File .\Test.log				# Redirect the log file name and location (Optional)
	Log -Color Yellow "Examples:"
	Log "Not set (null):" $NotSet
	Log "Empty string:" ""
	Log "If you want to quote a bare string, consider using CText:" (CText "")
	Log "An empty array:" @()
	Log "An empty array embedded in another array:" @(@()) "Note that PowerShell (and not Write-Log) flattens this."
	Log "Two empty arrays embedded in another array:" @(@(), @())
	Log "An null in an empty array:" @($Null)
	Log "A hashtable:" @{one = 1; two = 2; three = 3}
	Log "A recursive hashtable:" @{one = @{one = @{one = 1; two = 2; three = 3}; two = 2; three = 3}; two = 2; three = 3} -Expand -Depth:9
	$Numbers = Log "The array" @("One", "Two", "Three") ? "is stored in `$Numbers"
	Log "A hashtable in an array:" @(@{one = 1; two = 2; three = 3})
	Log "Character array:" "Hallo World".ToCharArray()
	Log "Volatile Environment:" (Get-Item "HKCU:\Volatile Environment") -Expand
	Log "WinNT user object:" ([ADSI]"WinNT://./$Env:Username") -Depth 5 -Expand
	Log "My Object:" $My -Expand
}

# ------------------------------------- Global --------------------------------
Function Global:ConvertTo-Text([Alias("Value")]$O, [Int]$Depth, [Switch]$Type, [Switch]$Expand, [Int]$Strip = -1, [String]$Prefix, [Int]$i) {
	Function Iterate($Value, [String]$Prefix, [Int]$i = $i + 1) {ConvertTo-Text $Value -Depth:$Depth -Strip:$Strip -Type:$Type -Expand:$Expand -Prefix:$Prefix -i:$i}
	$NewLine = @("`r`n")[!$Expand]; $Space = @("`t" * $i)[!$Expand]
	If ($O -eq $Null) {$V = '$Null'} Else {
		$V = If ($O -is "Boolean")  {"`$$O"}
		ElseIf ($O -is "String") {If ($Strip -ge 0) {'"' + (($O -Replace "[\s]+", " ") -Replace "(?<=[\s\S]{$Strip})[\s\S]+", "...") + '"'} Else {"""$O"""}}
		ElseIf ($O -is "DateTime") {$O.ToString("s")} 
		ElseIf ($O -is "ValueType" -or ($O.Value.GetTypeCode -and $O.ToString.OverloadDefinitions)) {$O}
		ElseIf ($O -is "Xml") {(@(Select-XML -XML $O *) -Join "$NewLine$Space") + $NewLine}
		ElseIf ($i -gt $Depth) {$Type = $True; "..."}
		ElseIf ($O -is "Array") {"@(", @(&{For ($_ = 0; $_ -lt $O.Count; $_++) {Iterate $O[$_]}}), ")"}
		ElseIf ($O.GetEnumerator.OverloadDefinitions) {"@{", @(ForEach($_ in $O.Keys) {Iterate $O.$_ "$_ = "}), "}"}
		ElseIf ($O.PSObject.Properties -and !$O.value.GetTypeCode) {"{", @(ForEach($_ in $O.PSObject.Properties | Select -Exp Name) {Iterate $O.$_ "$_`: "}), "}"}
		Else {$Type = $True; "?"}}
	If ($Type) {$Prefix += "[" + $(Try {$O.GetType()} Catch {$Error.Remove($Error[0]); "$Var.PSTypeNames[0]"}).ToString().Split(".")[-1] + "]"}
	"$Space$Prefix" + $(If ($V -is "Array") {$V[0] + $(If ($V[1]) {$NewLine + ($V[1] -Join ", $NewLine") + "$NewLine$Space"} Else {""}) + $V[2]} Else {$V})
}; Set-Alias CText ConvertTo-Text -Scope:Global -Description "Convert value to readable text"

# ------------------------------------- Logging -------------------------------
Function Global:Write-Log {
	Param(
		$0, $1, $2, $3, $4, $5, $6, $7, $8, $9,									# PSv2 doesn't support PositionalBinding
		[ConsoleColor]$Color, [String]$Delimiter = " ", [Int]$Indent = 0,
		[io.FileInfo]$File = "$Env:Temp\$($My.Name).log",						# Set to "-File $Null" to disable file logging
		[String]$Separator = "",												# Separator between sessions
		[Int]$Preserve = 100e3,													# Size to preserve (0 = do not limit)
		[Switch]$Prefix, [Switch]$Delay, [Switch]$Debug, [Switch]$Verbose,
		[Int]$Depth = 1, [Int]$Strip = 80, [Switch]$Type, [Switch]$Expand
	)
	$Show = (&{If($Script:Debug) {$True} Else {!$Debug}}) -And (&{If($Script:Verbose) {$True} Else {!$Verbose}})
	Function IsQ($Item) {If ($Item -is [String]) {$Item -eq "?"} Else {$False}}
	$Arguments = $MyInvocation.BoundParameters; $Items = @()
	If (!$Script:Log) {$Script:Log = @{Items = @(); Buffer = @(); Error = 0}}
	If (!$Script:Log.ContainsKey("File") -or $Arguments.ContainsKey("File")) {
		If ((Test-Path($File)) -And $Preserve) {
			$Script:Log.Length = (Get-Item($File)).Length 
			If ($Script:Log.Length -gt $Preserve) {								# Prevent the log file to grow indefinitely
				$Content = [String]::Join("`r`n", (Get-Content $File))
				$Start = $Content.LastIndexOf("`r`n$Separator`r`n", $Script:Log.Length - $Preserve)
				If ($Start -gt 0) {Set-Content $File $Content.SubString($Start + $Separator.Length + 4)}
			}
		}
		If ($Log.Length -gt 0) {$Script:Log.Buffer += $Separator}
		$StartTime = (Get-Process -id $PID).StartTime
		$Script:Log.Buffer += ((Get-Date $StartTime -Format "yyyy-MM-dd") + "`t$($My.Name) (version: $($My.Version), PowerShell version: $($PSVersionTable.PSVersion))")
		$Script:Log.Buffer += ((Get-Date $StartTime -Format "HH:mm:ss.ff") + "`t$($My.Path) $($My.Arguments)")
		$Script:Log.File = $File
	}
	While ($Script:Log.Error -lt $Error.Count) {
		$Err = $Error[$Error.Count - ++$Script:Log.Error]
		$ErrLine = "Error at $($Err.InvocationInfo.ScriptLineNumber),$($Err.InvocationInfo.OffsetInLine): $Err"
		Write-Host $ErrLine -ForegroundColor Red
		$Script:Log.Buffer += $ErrLine
	}
	For ($i = 0; $i -le 9; $i++) {
		If ($Arguments.ContainsKey("$i")) {$Argument = $Arguments.Item($i)} Else {$Argument = $Null}
		If ($i) {
			$Text = If ($Item -is [String]) {$Item -Replace "^\s*" -Replace "\s*$" -Replace "\s*`n\s*", "`r`n"}
			Else {ConvertTo-Text $Item -Type:$Type -Depth:$Depth -Strip:$Strip -Expand:$Expand}
		} Else {$Text = $Null}
		If (IsQ($Argument)) {$Item} Else {If (IsQ($Item)) {$Text = $Null}}
		If ($Text -And $Show) {$Script:Log.Items += $Text}
		If ($Arguments.ContainsKey("$i")) {$Item = $Argument} Else {Break}
	}
	If ($Arguments.ContainsKey("0") -And !$Prefix -And $Show) {
		$Tabs = "`t" * $Indent; $Line = $Script:Log.Items -Join $Delimiter; $Show = "$Tabs$Line" -Replace "`r`n", "`r`n$Tabs"; $Script:Log.Items = @()
		If ($Color) {Write-Host $Show -ForegroundColor $Color} Else {Write-Host $Show}
		$Script:Log.Buffer += ((Get-Date -Format "HH:mm:ss.ff") + "`t$Tabs$Line") -Replace "`r`n", "`r`n           `t$Tabs"
	}
	If (($Script:Log.File -ne "") -And ($Script:Log.Buffer.Length -gt 0) -And !$Delay) {
		If ((Add-content $Script:Log.file $Script:Log.Buffer -ErrorAction SilentlyContinue -PassThru).Length -gt 0) {$Script:Log.Buffer = @()}
	}
}; Set-Alias Log Write-Log -Scope:Global -Description "Records cmdlet processing details in a file"

$Error.Clear()
$My = @{File = Get-ChildItem $MyInvocation.MyCommand.Path; Contents = $MyInvocation.MyCommand.ScriptContents}
If ($My.Contents -Match '^\s*\<#([\s\S]*?)#\>') {$My.Help = $Matches[1].Trim()}
[RegEx]::Matches($My.Help, '(^|[\r\n])\s*\.(.+)\s*[\r\n]|$') | ForEach {
	If ($Caption) {$My.$Caption = $My.Help.SubString($Start, $_.Index - $Start)}
	$Caption = $_.Groups[2].ToString().Trim()
	$Start = $_.Index + $_.Length
}
$My.Title = $My.Synopsis.Trim().Split("`r`n")[0].Trim()
$My.ID = (Get-Culture).TextInfo.ToTitleCase($My.Title) -Replace "\W", ""
$My.Notes -Split("\r\n") | ForEach {$Note = $_ -Split(":", 2); If ($Note[0].Trim()) {$My[$Note[0].Trim()] = $Note[1].Trim()}}
$My.Path = $My.File.FullName; $My.Folder = $My.File.DirectoryName; $My.Name = $My.File.BaseName
$My.Arguments = (($MyInvocation.Line + " ") -Replace ("^.*\\" + $My.File.Name.Replace(".", "\.") + "['"" ]"), "").Trim()
$Script:Debug = $MyInvocation.BoundParameters.Debug.IsPresent; $Script:Verbose = $MyInvocation.BoundParameters.Verbose.IsPresent
$MyInvocation.MyCommand.Parameters.Keys | Where {Test-Path Variable:"$_"} | ForEach {
	$Value = Get-Variable -ValueOnly $_
	If ($Value -is [IO.FileInfo]) {Set-Variable $_ -Value ([Environment]::ExpandEnvironmentVariables($Value))}
}

Main
Log "End"					# Log finish time and remaining errors (recommended)
