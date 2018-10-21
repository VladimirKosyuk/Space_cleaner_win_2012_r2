#What: Space cleaner for windows server 2012 r2, need to be run via task scheduler
#
#Date: 21 october 2018 year										 
#
#Variables:
[string[]]$recipients = "" #send email to recpients, for example: "test1@example.ru", "test2@example.ru"
$SmtpLogin = ""
$SmtpPassword = ""

#Log off all users
$sessionIds = (((quser) -replace '^>', '') -replace '\s{2,}', ',').Trim() | ForEach-Object {if ($_.Split(',').Count -eq 5) {Write-Output ($_ -replace '(^[^,]+)', '$1,')} else {Write-Output $_}} | ConvertFrom-Csv | Select-Object -ExpandProperty "id"
foreach ($sessionId in $sessionIds){logoff $sessionId /server:localhost}

#Clearing 1c cache and temp folders
Get-ChildItem "C:\Users\*\AppData\Local\1C\1Cv8\*","C:\Users\*\AppData\Roaming\1C\1Cv8\*" | Where {$_.Name -as [guid]} | rm -Force -Recurse
Get-ChildItem "C:\Users\*\AppData\Local\Temp\*", "C:\Windows\Temp" | rm -Force -Recurse -Verbose 4>&1 

#Purge *.dt, *.cf, *.iso, all zip or rar archives, that exceed 1 Gb, all files, that exceed 2 Gbs
Get-ChildItem "C:\Users\*\" -Recurse | where {($_.name -like "*.dt" -or $_.name -like "*.cf" -or $_.name -like "*.iso") -or (($_.name -like "*.zip" -or $_.name -like "*.rar") -and ($_.Length -gt 1073741824)) -or ($_.Length -gt 2147483648) } | rm -Force -Recurse

#Clearing recycler bin for each user
$Recycler = (New-Object -ComObject Shell.Application).NameSpace(0xa)
$Recycler.items() | foreach { rm $_.path -force -recurse}
 
#Search for user profiles, that exceed 2 GB and if found - send email
$Items = Get-ChildItem "C:\Users" | Where-Object {$_.PSIsContainer -eq $true} | Sort-Object
foreach ($i in $Items)
{
    $subFolderItems = Get-ChildItem $i.FullName -recurse -force -ErrorAction SilentlyContinue| Where-Object {$_.PSIsContainer -eq $false} | Measure-Object -property Length -sum | where {$_.sum -gt "2147483648"} 
    foreach ($s in $subFolderItems) {$Bigprofile = $i.FullName + " -- " + "{0:N2}" -f ($subFolderItems.sum / 1GB) + " GB" |out-file -append $PSScriptRoot\BigProfiles.txt}
}

 if (Get-ChildItem $PSScriptRoot\BigProfiles.txt |where-object {$_.Length -gt 0}) 
 
 {
    $secpasswd = ConvertTo-SecureString $SmtpPassword -AsPlainText -Force
    $mycreds = New-Object System.Management.Automation.PSCredential ($SmtpLogin, $secpasswd)
    $EmailParam = @{
        SmtpServer = 'smtp.gmail.com'
        Port = 587
        UseSsl = $true
        Credential  = $mycreds
        From = $SmtpLogin
        To = $recipients
        Subject = (Get-WmiObject -Class Win32_ComputerSystem |Select-Object -ExpandProperty "name")+" User profile quota exceed, see attachment"
        Body = Get-WmiObject Win32_LogicalDisk -Filter "DriveType=3" -Computer localhost | where-object {($_.DeviceID -eq "C:")} |Select DeviceID,@{Name="size(GB)";Expression={"{0:N1}" -f($_.size/1gb)}},@{Name="freespace(GB)";Expression={"{0:N1}" -f($_.freespace/1gb)}} | Format-Table -AutoSize |Out-String
        Attachments = "$PSScriptRoot\BigProfiles.txt"
}
    
    Send-MailMessage @EmailParam -Encoding ([System.Text.Encoding]::UTF8)
}

Remove-Item $PSScriptRoot\BigProfiles.txt -Force

Remove-Variable -Name *  -Force -ErrorAction SilentlyContinue
